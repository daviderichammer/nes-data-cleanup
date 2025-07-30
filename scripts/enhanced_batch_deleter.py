#!/usr/bin/env python3
"""
Enhanced NES Database Cleanup - Batch Deleter with Dependency Management
This enhanced version handles proper deletion order and polymorphic relationships
"""

import mysql.connector
import argparse
import json
import logging
import time
import signal
import sys
from typing import Dict, List, Tuple, Optional
from datetime import datetime

class EnhancedBatchDeleter:
    def __init__(self, db_config: dict, cutoff_config: dict):
        """Initialize with database and cutoff configuration"""
        self.db_config = db_config
        self.cutoff_config = cutoff_config
        self.db = None
        self.interrupted = False
        self.object_type_cache = {}
        self.setup_logging()
        self.setup_signal_handlers()
        
    def setup_logging(self):
        """Configure logging"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger(__name__)
        
    def setup_signal_handlers(self):
        """Setup signal handlers for graceful shutdown"""
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
        
    def signal_handler(self, signum, frame):
        """Handle interrupt signals gracefully"""
        self.logger.info("Received interrupt signal. Finishing current batch and shutting down...")
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
            
    def load_object_types(self):
        """Load and cache object type mappings"""
        cursor = self.db.cursor()
        cursor.execute("SELECT object_type_id, object_type FROM object")
        
        for row in cursor.fetchall():
            self.object_type_cache[row[1]] = row[0]  # object_type -> object_type_id
            
        self.logger.info(f"Loaded {len(self.object_type_cache)} object types")
        
    def get_contact_object_type_id(self) -> Optional[int]:
        """Get the object_type_id for Contact entities"""
        return self.object_type_cache.get('Contact')
        
    def delete_polymorphic_records(self, table_name: str, object_id: int, object_type_id: int, batch_size: int = 1000) -> int:
        """
        Delete polymorphic records for a given object_id and object_type_id
        Returns: number of records deleted
        """
        cursor = self.db.cursor()
        total_deleted = 0
        
        while not self.interrupted:
            # Delete in batches to avoid long-running transactions
            cursor.execute(f"""
                DELETE FROM {table_name} 
                WHERE object_id = %s AND object_type_id = %s 
                LIMIT %s
            """, (object_id, object_type_id, batch_size))
            
            deleted_count = cursor.rowcount
            total_deleted += deleted_count
            
            if deleted_count == 0:
                break
                
            self.db.commit()
            
            if deleted_count < batch_size:
                break
                
        return total_deleted
        
    def delete_contact_dependencies(self, contact_id: int) -> Dict[str, int]:
        """
        Delete all dependencies for a contact in proper order
        Returns: dictionary of table_name -> deleted_count
        """
        deleted_counts = {}
        contact_object_type_id = self.get_contact_object_type_id()
        
        if not contact_object_type_id:
            self.logger.warning("Could not find Contact object type ID")
            return deleted_counts
            
        # Level 1: Leaf tables with polymorphic relationships
        polymorphic_tables = ['email_attachment', 'email_preview', 'note', 'phone', 'address']
        
        for table in polymorphic_tables:
            if self.interrupted:
                break
                
            try:
                # For email_attachment and email_preview, we need to delete via email table
                if table in ['email_attachment', 'email_preview']:
                    deleted_count = self.delete_email_dependencies(contact_id, contact_object_type_id, table)
                else:
                    # Direct polymorphic deletion
                    deleted_count = self.delete_polymorphic_records(table, contact_id, contact_object_type_id)
                    
                deleted_counts[table] = deleted_count
                if deleted_count > 0:
                    self.logger.info(f"Deleted {deleted_count} {table} records for contact {contact_id}")
                    
            except Exception as e:
                self.logger.error(f"Error deleting {table} for contact {contact_id}: {e}")
                self.db.rollback()
                raise
                
        # Level 2: Email records (after attachments/previews)
        if not self.interrupted:
            try:
                deleted_count = self.delete_polymorphic_records('email', contact_id, contact_object_type_id)
                deleted_counts['email'] = deleted_count
                if deleted_count > 0:
                    self.logger.info(f"Deleted {deleted_count} email records for contact {contact_id}")
            except Exception as e:
                self.logger.error(f"Error deleting emails for contact {contact_id}: {e}")
                self.db.rollback()
                raise
                
        # Level 3: Tenant records
        if not self.interrupted:
            try:
                deleted_count = self.delete_polymorphic_records('tenant', contact_id, contact_object_type_id)
                deleted_counts['tenant'] = deleted_count
                if deleted_count > 0:
                    self.logger.info(f"Deleted {deleted_count} tenant records for contact {contact_id}")
            except Exception as e:
                self.logger.error(f"Error deleting tenants for contact {contact_id}: {e}")
                self.db.rollback()
                raise
                
        # Level 4: Direct foreign key dependencies
        direct_dependencies = [
            'bank', 'subscription', 'contact_batch', 'contact_logical_unit', 
            'nes_anet_customer_profile'
        ]
        
        for table in direct_dependencies:
            if self.interrupted:
                break
                
            try:
                cursor = self.db.cursor()
                cursor.execute(f"DELETE FROM {table} WHERE contact_id = %s", (contact_id,))
                deleted_count = cursor.rowcount
                deleted_counts[table] = deleted_count
                
                if deleted_count > 0:
                    self.logger.info(f"Deleted {deleted_count} {table} records for contact {contact_id}")
                    
                self.db.commit()
                
            except Exception as e:
                self.logger.error(f"Error deleting {table} for contact {contact_id}: {e}")
                self.db.rollback()
                raise
                
        return deleted_counts
        
    def delete_email_dependencies(self, contact_id: int, contact_object_type_id: int, dependency_table: str) -> int:
        """Delete email attachments/previews for emails belonging to a contact"""
        cursor = self.db.cursor()
        
        # First get all email IDs for this contact
        cursor.execute("""
            SELECT email_id FROM email 
            WHERE object_id = %s AND object_type_id = %s
        """, (contact_id, contact_object_type_id))
        
        email_ids = [row[0] for row in cursor.fetchall()]
        total_deleted = 0
        
        for email_id in email_ids:
            if self.interrupted:
                break
                
            cursor.execute(f"DELETE FROM {dependency_table} WHERE email_id = %s", (email_id,))
            total_deleted += cursor.rowcount
            
        self.db.commit()
        return total_deleted
        
    def delete_contact_batch(self, cutoff_id: int, batch_size: int = 1000) -> Dict[str, int]:
        """
        Delete contacts and all their dependencies in batches
        Returns: summary of deletion counts
        """
        cursor = self.db.cursor()
        total_summary = {}
        processed_contacts = 0
        
        self.logger.info(f"Starting contact deletion up to ID {cutoff_id}")
        
        # Get contacts to delete in batches
        while not self.interrupted:
            cursor.execute("""
                SELECT contact_id FROM contact 
                WHERE contact_id <= %s 
                ORDER BY contact_id 
                LIMIT %s
            """, (cutoff_id, batch_size))
            
            contacts = cursor.fetchall()
            if not contacts:
                break
                
            for (contact_id,) in contacts:
                if self.interrupted:
                    break
                    
                try:
                    # Delete all dependencies first
                    dependency_summary = self.delete_contact_dependencies(contact_id)
                    
                    # Then delete the contact itself
                    cursor.execute("DELETE FROM contact WHERE contact_id = %s", (contact_id,))
                    contact_deleted = cursor.rowcount
                    
                    if contact_deleted > 0:
                        dependency_summary['contact'] = contact_deleted
                        processed_contacts += 1
                        
                        # Update totals
                        for table, count in dependency_summary.items():
                            total_summary[table] = total_summary.get(table, 0) + count
                            
                        self.db.commit()
                        
                        if processed_contacts % 100 == 0:
                            self.logger.info(f"Processed {processed_contacts} contacts")
                            
                except Exception as e:
                    self.logger.error(f"Error deleting contact {contact_id}: {e}")
                    self.db.rollback()
                    continue
                    
            # Update cutoff for next batch
            if contacts:
                last_contact_id = contacts[-1][0]
                cursor.execute("DELETE FROM contact WHERE contact_id <= %s", (last_contact_id,))
                self.db.commit()
                
        self.logger.info(f"Contact deletion completed. Processed {processed_contacts} contacts")
        return total_summary
        
    def delete_readings_batch(self, cutoff_id: int, batch_size: int = 10000) -> int:
        """
        Delete non-billing readings in batches
        Returns: total number of readings deleted
        """
        cursor = self.db.cursor()
        total_deleted = 0
        
        self.logger.info(f"Starting reading deletion up to ID {cutoff_id}")
        
        while not self.interrupted:
            # Delete readings that are NOT used for billing
            cursor.execute("""
                DELETE r FROM reading r
                LEFT JOIN sm_usage su ON r.reading_id = su.reading_id
                WHERE r.reading_id <= %s 
                AND su.reading_id IS NULL
                AND r.reading_date < DATE_SUB(NOW(), INTERVAL 2 YEAR)
                LIMIT %s
            """, (cutoff_id, batch_size))
            
            deleted_count = cursor.rowcount
            total_deleted += deleted_count
            
            if deleted_count == 0:
                break
                
            self.db.commit()
            
            if total_deleted % 50000 == 0:
                self.logger.info(f"Deleted {total_deleted} readings so far")
                
            if deleted_count < batch_size:
                break
                
        self.logger.info(f"Reading deletion completed. Deleted {total_deleted} readings")
        return total_deleted
        
    def run_deletion(self, table_name: Optional[str] = None, dry_run: bool = False):
        """
        Run the deletion process for specified table or all tables
        """
        if dry_run:
            self.logger.info("DRY RUN MODE - No actual deletion will occur")
            return
            
        try:
            self.connect()
            self.load_object_types()
            
            if table_name:
                self.logger.info(f"Processing single table: {table_name}")
                if table_name == 'contact':
                    cutoff_id = self.cutoff_config.get('contact_cutoff', 0)
                    summary = self.delete_contact_batch(cutoff_id)
                    self.logger.info(f"Contact deletion summary: {summary}")
                elif table_name == 'reading':
                    cutoff_id = self.cutoff_config.get('reading_cutoff', 0)
                    deleted = self.delete_readings_batch(cutoff_id)
                    self.logger.info(f"Deleted {deleted} readings")
                else:
                    self.logger.error(f"Table {table_name} not supported yet")
            else:
                self.logger.info("Processing all tables in dependency order")
                
                # Process readings first (independent)
                reading_cutoff = self.cutoff_config.get('reading_cutoff', 0)
                if reading_cutoff > 0:
                    self.delete_readings_batch(reading_cutoff)
                    
                # Process contacts (with all dependencies)
                contact_cutoff = self.cutoff_config.get('contact_cutoff', 0)
                if contact_cutoff > 0:
                    self.delete_contact_batch(contact_cutoff)
                    
        except Exception as e:
            self.logger.error(f"Deletion process failed: {e}")
            if self.db:
                self.db.rollback()
            raise
        finally:
            self.disconnect()

def main():
    parser = argparse.ArgumentParser(description='Enhanced NES Database Cleanup - Batch Deleter')
    parser.add_argument('--host', default='localhost', help='Database host')
    parser.add_argument('--user', required=True, help='Database user')
    parser.add_argument('--password', required=True, help='Database password')
    parser.add_argument('--database', default='nes', help='Database name')
    parser.add_argument('--cutoff-config', required=True, help='Path to cutoff configuration JSON file')
    parser.add_argument('--table', help='Specific table to process (optional)')
    parser.add_argument('--dry-run', action='store_true', help='Perform dry run without actual deletion')
    
    args = parser.parse_args()
    
    # Load cutoff configuration
    try:
        with open(args.cutoff_config, 'r') as f:
            cutoff_config = json.load(f)
    except Exception as e:
        logging.error(f"Failed to load cutoff configuration: {e}")
        sys.exit(1)
    
    db_config = {
        'host': args.host,
        'user': args.user,
        'password': args.password,
        'database': args.database
    }
    
    deleter = EnhancedBatchDeleter(db_config, cutoff_config)
    
    try:
        deleter.run_deletion(args.table, args.dry_run)
    except Exception as e:
        logging.error(f"Deletion failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()

