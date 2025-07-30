#!/usr/bin/env python3
"""
NES Database Cleanup - Batch Deleter
This script performs batch deletion using ID ranges for massive datasets.
"""

import mysql.connector
import json
import logging
import time
import argparse
from datetime import datetime
from typing import Dict, List, Optional, Tuple
import signal
import sys

class BatchDeleter:
    def __init__(self, db_config: dict, cutoff_config: dict):
        """Initialize with database and cutoff configuration"""
        self.db_config = db_config
        self.cutoff_config = cutoff_config
        self.db = None
        self.setup_logging()
        self.interrupted = False
        self.setup_signal_handlers()
        
    def setup_logging(self):
        """Configure logging"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('batch_deletion.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
    def setup_signal_handlers(self):
        """Setup signal handlers for graceful shutdown"""
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
        
    def signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully"""
        self.logger.info(f"Received signal {signum}, initiating graceful shutdown...")
        self.interrupted = True
        
    def connect(self):
        """Connect to database"""
        try:
            self.db = mysql.connector.connect(**self.db_config)
            self.db.autocommit = False  # Use transactions
            self.logger.info("Connected to database successfully")
        except mysql.connector.Error as e:
            self.logger.error(f"Database connection failed: {e}")
            raise
            
    def disconnect(self):
        """Disconnect from database"""
        if self.db:
            self.db.close()
            self.logger.info("Disconnected from database")
            
    def create_logging_table(self):
        """Create deletion logging table if it doesn't exist"""
        cursor = self.db.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS deletion_log (
                log_id INT AUTO_INCREMENT PRIMARY KEY,
                table_name VARCHAR(64) NOT NULL,
                batch_start_id BIGINT NOT NULL,
                batch_end_id BIGINT NOT NULL,
                records_deleted INT NOT NULL,
                deleted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                execution_time_ms INT,
                INDEX idx_table_batch (table_name, batch_start_id)
            )
        """)
        self.db.commit()
        self.logger.info("Deletion logging table ready")
        
    def get_last_processed_id(self, table_name: str) -> int:
        """Get the last processed ID for a table to support resumption"""
        cursor = self.db.cursor()
        cursor.execute("""
            SELECT COALESCE(MAX(batch_end_id), 0) as last_id
            FROM deletion_log 
            WHERE table_name = %s
        """, (table_name,))
        
        result = cursor.fetchone()
        return result[0] if result else 0
        
    def log_batch_deletion(self, table_name: str, start_id: int, end_id: int, 
                          deleted_count: int, execution_time_ms: int):
        """Log a batch deletion"""
        cursor = self.db.cursor()
        cursor.execute("""
            INSERT INTO deletion_log 
            (table_name, batch_start_id, batch_end_id, records_deleted, execution_time_ms)
            VALUES (%s, %s, %s, %s, %s)
        """, (table_name, start_id, end_id, deleted_count, execution_time_ms))
        self.db.commit()
        
    def delete_reading_batch(self, start_id: int, end_id: int, cutoff_id: int) -> int:
        """Delete a batch of reading records not used for billing"""
        cursor = self.db.cursor()
        
        start_time = time.time()
        
        # Delete non-billing readings in the ID range
        cursor.execute("""
            DELETE r FROM reading r
            LEFT JOIN sm_usage su ON r.guid = su.guid
            WHERE r.reading_id BETWEEN %s AND %s
            AND r.reading_id <= %s
            AND su.sm_usage_id IS NULL
            AND r.date_imported < DATE_SUB(NOW(), INTERVAL 2 YEAR)
        """, (start_id, end_id, cutoff_id))
        
        deleted_count = cursor.rowcount
        execution_time_ms = int((time.time() - start_time) * 1000)
        
        self.db.commit()
        self.log_batch_deletion('reading', start_id, end_id, deleted_count, execution_time_ms)
        
        return deleted_count
        
    def delete_account_related_batch(self, table_name: str, start_id: int, end_id: int, 
                                   cutoff_id: int) -> int:
        """Delete a batch of account-related records"""
        cursor = self.db.cursor()
        start_time = time.time()
        deleted_count = 0
        
        if table_name == 'email_attachment':
            # Delete email attachments for inactive accounts
            cursor.execute("""
                DELETE ea FROM email_attachment ea
                JOIN email e ON ea.email_id = e.email_id
                WHERE e.object_id BETWEEN %s AND %s
                AND e.object_id <= %s
                AND e.object_type_id = 1
                AND EXISTS (
                    SELECT 1 FROM contact c 
                    JOIN tenant t ON c.contact_id = t.contact_id
                    WHERE c.contact_id = e.object_id
                    AND t.to_date IS NOT NULL 
                    AND t.to_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
                    AND NOT EXISTS (SELECT 1 FROM invoice i WHERE i.object_id = c.contact_id AND i.object_type_id = 1 AND i.invoice_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                )
            """, (start_id, end_id, cutoff_id))
            
        elif table_name == 'email':
            # Delete emails for inactive accounts
            cursor.execute("""
                DELETE e FROM email e
                WHERE e.object_id BETWEEN %s AND %s
                AND e.object_id <= %s
                AND e.object_type_id = 1
                AND EXISTS (
                    SELECT 1 FROM contact c 
                    JOIN tenant t ON c.contact_id = t.contact_id
                    WHERE c.contact_id = e.object_id
                    AND t.to_date IS NOT NULL 
                    AND t.to_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
                    AND NOT EXISTS (SELECT 1 FROM invoice i WHERE i.object_id = c.contact_id AND i.object_type_id = 1 AND i.invoice_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                )
            """, (start_id, end_id, cutoff_id))
            
        elif table_name == 'invoice_detail':
            # Delete invoice details for inactive accounts
            cursor.execute("""
                DELETE id FROM invoice_detail id
                JOIN invoice i ON id.invoice_id = i.invoice_id
                WHERE i.object_id BETWEEN %s AND %s
                AND i.object_id <= %s
                AND i.object_type_id = 1
                AND EXISTS (
                    SELECT 1 FROM contact c 
                    JOIN tenant t ON c.contact_id = t.contact_id
                    WHERE c.contact_id = i.object_id
                    AND t.to_date IS NOT NULL 
                    AND t.to_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
                    AND NOT EXISTS (SELECT 1 FROM invoice i2 WHERE i2.object_id = c.contact_id AND i2.object_type_id = 1 AND i2.invoice_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                )
            """, (start_id, end_id, cutoff_id))
            
        elif table_name == 'invoice':
            # Delete invoices for inactive accounts
            cursor.execute("""
                DELETE i FROM invoice i
                WHERE i.object_id BETWEEN %s AND %s
                AND i.object_id <= %s
                AND i.object_type_id = 1
                AND EXISTS (
                    SELECT 1 FROM contact c 
                    JOIN tenant t ON c.contact_id = t.contact_id
                    WHERE c.contact_id = i.object_id
                    AND t.to_date IS NOT NULL 
                    AND t.to_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
                    AND NOT EXISTS (SELECT 1 FROM invoice i2 WHERE i2.object_id = c.contact_id AND i2.object_type_id = 1 AND i2.invoice_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                )
            """, (start_id, end_id, cutoff_id))
            
        elif table_name == 'address':
            # Delete addresses for inactive accounts
            cursor.execute("""
                DELETE a FROM address a
                WHERE a.object_id BETWEEN %s AND %s
                AND a.object_id <= %s
                AND a.object_type_id = (SELECT object_type_id FROM object WHERE object_name = 'dstContact')
                AND EXISTS (
                    SELECT 1 FROM contact c 
                    JOIN tenant t ON c.contact_id = t.contact_id
                    WHERE c.contact_id = a.object_id
                    AND t.to_date IS NOT NULL 
                    AND t.to_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
                    AND NOT EXISTS (SELECT 1 FROM invoice i WHERE i.object_id = c.contact_id AND i.object_type_id = 1 AND i.invoice_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                )
            """, (start_id, end_id, cutoff_id))
            
        elif table_name == 'phone':
            # Delete phone records for inactive accounts
            cursor.execute("""
                DELETE p FROM phone p
                WHERE p.object_id BETWEEN %s AND %s
                AND p.object_id <= %s
                AND p.object_type_id = (SELECT object_type_id FROM object WHERE object_name = 'dstContact')
                AND EXISTS (
                    SELECT 1 FROM contact c 
                    JOIN tenant t ON c.contact_id = t.contact_id
                    WHERE c.contact_id = p.object_id
                    AND t.to_date IS NOT NULL 
                    AND t.to_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
                    AND NOT EXISTS (SELECT 1 FROM invoice i WHERE i.object_id = c.contact_id AND i.object_type_id = 1 AND i.invoice_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                )
            """, (start_id, end_id, cutoff_id))
            
        elif table_name == 'tenant':
            # Delete tenant records for inactive accounts
            cursor.execute("""
                DELETE t FROM tenant t
                WHERE t.contact_id BETWEEN %s AND %s
                AND t.contact_id <= %s
                AND t.to_date IS NOT NULL 
                AND t.to_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
                AND NOT EXISTS (SELECT 1 FROM invoice i WHERE i.object_id = t.contact_id AND i.object_type_id = 1 AND i.invoice_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
            """, (start_id, end_id, cutoff_id))
            
        elif table_name == 'contact':
            # Delete contact records (final step for accounts)
            cursor.execute("""
                DELETE c FROM contact c
                WHERE c.contact_id BETWEEN %s AND %s
                AND c.contact_id <= %s
                AND EXISTS (
                    SELECT 1 FROM tenant t 
                    WHERE t.contact_id = c.contact_id
                    AND t.to_date IS NOT NULL 
                    AND t.to_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
                )
                AND NOT EXISTS (SELECT 1 FROM invoice i WHERE i.object_id = c.contact_id AND i.object_type_id = 1 AND i.invoice_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                AND NOT EXISTS (SELECT 1 FROM journal_entry je WHERE je.object_id = c.contact_id AND je.object_type_id = 1 AND je.journal_entry_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                AND NOT EXISTS (SELECT 1 FROM note n WHERE n.object_id = c.contact_id AND n.object_type_id = 94 AND n.last_updated_on >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                AND NOT EXISTS (SELECT 1 FROM email e WHERE e.object_id = c.contact_id AND e.object_type_id = 1 AND e.email_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
            """, (start_id, end_id, cutoff_id))
        
        deleted_count = cursor.rowcount
        execution_time_ms = int((time.time() - start_time) * 1000)
        
        self.db.commit()
        self.log_batch_deletion(table_name, start_id, end_id, deleted_count, execution_time_ms)
        
        return deleted_count
        
    def process_table(self, table_name: str, batch_size: int = 1000, 
                     delay_seconds: float = 0.1, dry_run: bool = True) -> Dict:
        """Process an entire table in batches"""
        
        if table_name not in self.cutoff_config:
            raise ValueError(f"No cutoff configuration found for table: {table_name}")
            
        cutoff_id = self.cutoff_config[table_name]['cutoff_id']
        
        if cutoff_id == 0:
            self.logger.info(f"No records to delete for {table_name} (cutoff_id = 0)")
            return {'total_deleted': 0, 'batches_processed': 0}
            
        # Resume from last processed ID
        start_id = self.get_last_processed_id(table_name) + 1
        
        if start_id > cutoff_id:
            self.logger.info(f"Table {table_name} already fully processed")
            return {'total_deleted': 0, 'batches_processed': 0}
            
        total_deleted = 0
        batches_processed = 0
        current_id = start_id
        
        self.logger.info(f"Processing {table_name}: ID range {start_id:,} to {cutoff_id:,}")
        
        if dry_run:
            self.logger.info("DRY RUN MODE - No data will be deleted")
            
        while current_id <= cutoff_id and not self.interrupted:
            end_id = min(current_id + batch_size - 1, cutoff_id)
            
            if dry_run:
                # In dry run, just log what would be deleted
                self.logger.info(f"DRY RUN: Would process {table_name} batch {current_id:,}-{end_id:,}")
                deleted_count = 0
            else:
                # Perform actual deletion
                if table_name == 'reading':
                    deleted_count = self.delete_reading_batch(current_id, end_id, cutoff_id)
                else:
                    deleted_count = self.delete_account_related_batch(table_name, current_id, end_id, cutoff_id)
                    
            total_deleted += deleted_count
            batches_processed += 1
            
            if deleted_count > 0 or batches_processed % 100 == 0:
                self.logger.info(f"{table_name}: Batch {current_id:,}-{end_id:,}, deleted {deleted_count:,} records")
                
            current_id += batch_size
            
            # Add delay to reduce system load
            if delay_seconds > 0:
                time.sleep(delay_seconds)
                
        if self.interrupted:
            self.logger.info(f"Processing interrupted for {table_name} at ID {current_id:,}")
        else:
            self.logger.info(f"Completed processing {table_name}: {total_deleted:,} total records deleted")
            
        return {
            'total_deleted': total_deleted,
            'batches_processed': batches_processed,
            'last_processed_id': current_id - batch_size
        }
        
    def get_progress_report(self) -> Dict:
        """Generate progress report"""
        cursor = self.db.cursor()
        cursor.execute("""
            SELECT 
                table_name,
                COUNT(*) as batches,
                SUM(records_deleted) as total_deleted,
                MAX(batch_end_id) as progress_id,
                MIN(deleted_at) as started,
                MAX(deleted_at) as last_batch,
                AVG(execution_time_ms) as avg_time_ms
            FROM deletion_log 
            GROUP BY table_name
            ORDER BY table_name
        """)
        
        progress = {}
        for row in cursor.fetchall():
            progress[row[0]] = {
                'batches': row[1],
                'total_deleted': row[2],
                'progress_id': row[3],
                'started': row[4],
                'last_batch': row[5],
                'avg_time_ms': row[6]
            }
            
        return progress

def load_cutoff_config(filename: str) -> Dict:
    """Load cutoff configuration from JSON file"""
    with open(filename, 'r') as f:
        data = json.load(f)
    return data.get('cutoffs', {})

def main():
    parser = argparse.ArgumentParser(description='Perform batch deletion using ID ranges')
    parser.add_argument('--host', default='localhost', help='Database host')
    parser.add_argument('--user', required=True, help='Database user')
    parser.add_argument('--password', required=True, help='Database password')
    parser.add_argument('--database', default='nes', help='Database name')
    parser.add_argument('--cutoff-config', required=True, help='Cutoff configuration JSON file')
    parser.add_argument('--table', help='Specific table to process (default: all)')
    parser.add_argument('--batch-size', type=int, default=1000, help='Batch size for deletion')
    parser.add_argument('--delay', type=float, default=0.1, help='Delay between batches (seconds)')
    parser.add_argument('--dry-run', action='store_true', help='Dry run mode (no actual deletion)')
    parser.add_argument('--progress', action='store_true', help='Show progress report only')
    
    args = parser.parse_args()
    
    db_config = {
        'host': args.host,
        'user': args.user,
        'password': args.password,
        'database': args.database
    }
    
    cutoff_config = load_cutoff_config(args.cutoff_config)
    deleter = BatchDeleter(db_config, cutoff_config)
    
    try:
        deleter.connect()
        deleter.create_logging_table()
        
        if args.progress:
            # Show progress report
            progress = deleter.get_progress_report()
            print("\n" + "="*60)
            print("DELETION PROGRESS REPORT")
            print("="*60)
            
            for table, data in progress.items():
                print(f"\n{table.upper()}:")
                print(f"  Batches Processed: {data['batches']:,}")
                print(f"  Records Deleted: {data['total_deleted']:,}")
                print(f"  Progress ID: {data['progress_id']:,}")
                print(f"  Avg Time/Batch: {data['avg_time_ms']:.1f}ms")
                
        else:
            # Perform deletion
            if args.dry_run:
                print("DRY RUN MODE - No data will be deleted")
                
            # Define processing order (children before parents)
            processing_order = [
                'reading',  # Standalone table
                'email_attachment',  # Child of email
                'email',  # Polymorphic to contact
                'invoice_detail',  # Child of invoice
                'invoice',  # Polymorphic to contact
                'address',  # Polymorphic to contact
                'phone',  # Polymorphic to contact
                'tenant',  # References contact
                'contact'  # Parent table
            ]
            
            tables_to_process = [args.table] if args.table else processing_order
            
            for table in tables_to_process:
                if table in cutoff_config:
                    result = deleter.process_table(
                        table, 
                        batch_size=args.batch_size,
                        delay_seconds=args.delay,
                        dry_run=args.dry_run
                    )
                    print(f"Completed {table}: {result['total_deleted']:,} records deleted")
                else:
                    print(f"Skipping {table}: No cutoff configuration")
                    
    except KeyboardInterrupt:
        print("\nInterrupted by user")
    except Exception as e:
        logging.error(f"Error during batch deletion: {e}")
        raise
    finally:
        deleter.disconnect()

if __name__ == '__main__':
    main()

