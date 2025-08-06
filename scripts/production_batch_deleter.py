#!/usr/bin/env python3
"""
Production NES Database Cleanup - Batch Deleter
Based on actual discovery query results and polymorphic relationship analysis
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

class ProductionBatchDeleter:
    def __init__(self, db_config: dict, cutoff_config: dict):
        """Initialize with database and cutoff configuration"""
        self.db_config = db_config
        self.cutoff_config = cutoff_config
        self.db = None
        self.interrupted = False
        
        # Object type mappings based on discovery results
        self.OBJECT_TYPES = {
            'dstTenant': 94,
            'dstCommunity': 49,
            'dstContact': 1,
            'dstAdditionalContact': 2,
            'dstUser': 5,
            'dstSmOwner': 110,
            'dstServiceProvider': 44,
            'dstLogicalUnit': 41,
            'dstInvoice': 71,
            'dstContactNote': 3,
            'dstCycleNote': 118,
            'dstFundingBatch': 117,
            'dstBill': 115,
            'dstSmTenantActivity': 109
        }
        
        # Batch sizes optimized for different table volumes
        self.BATCH_SIZES = {
            'address': 500,      # 67M+ records - smallest batches
            'phone': 1000,       # 5.9M+ records
            'email': 1000,       # 6.4M+ records  
            'note': 2000,        # 3.2M+ records
            'contact': 100,      # Process contacts in small batches
            'reading': 10000,    # Large batches for readings
            'default': 1000
        }
        
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
        """Connect to database with compatibility for older MySQL servers"""
        try:
            # Add charset compatibility for older MySQL servers
            db_config = self.db_config.copy()
            
            # Use utf8 instead of utf8mb4 for older MySQL compatibility
            db_config['charset'] = 'utf8'
            db_config['use_unicode'] = True
            
            # Disable SSL warnings for older servers
            db_config['autocommit'] = False  # Use transactions for deletion
            
            self.db = mysql.connector.connect(**db_config)
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
            
    def delete_polymorphic_records_by_type(self, table_name: str, object_type_id: int, 
                                         contact_ids: List[int], batch_size: int = None) -> int:
        """
        Delete polymorphic records for specific object type and contact IDs
        Returns: number of records deleted
        """
        if not contact_ids:
            return 0
            
        if batch_size is None:
            batch_size = self.BATCH_SIZES.get(table_name, self.BATCH_SIZES['default'])
            
        cursor = self.db.cursor()
        total_deleted = 0
        
        # Process contact IDs in chunks to avoid huge IN clauses
        chunk_size = 1000
        for i in range(0, len(contact_ids), chunk_size):
            if self.interrupted:
                break
                
            chunk = contact_ids[i:i + chunk_size]
            placeholders = ','.join(['%s'] * len(chunk))
            
            while not self.interrupted:
                # Delete in batches
                cursor.execute(f"""
                    DELETE FROM {table_name} 
                    WHERE object_type_id = %s 
                    AND object_id IN ({placeholders})
                    LIMIT %s
                """, [object_type_id] + chunk + [batch_size])
                
                deleted_count = cursor.rowcount
                total_deleted += deleted_count
                
                if deleted_count == 0:
                    break
                    
                self.db.commit()
                
                if deleted_count < batch_size:
                    break
                    
        return total_deleted
        
    def delete_community_polymorphic_dependencies(self, community_ids: List[int]) -> Dict[str, int]:
        """
        Delete all polymorphic dependencies for communities
        Based on discovery results: addresses, phones, notes
        """
        deleted_counts = {}
        community_object_type = self.OBJECT_TYPES['dstCommunity']
        
        # Level 1: Delete polymorphic dependencies in order of volume (largest first)
        polymorphic_tables = [
            ('address', 10783),   # From discovery results
            ('phone', 17970),
            ('note', 3599)
        ]
        
        for table_name, expected_volume in polymorphic_tables:
            if self.interrupted:
                break
                
            try:
                self.logger.info(f"Deleting {table_name} records for {len(community_ids)} communities (expected ~{expected_volume:,} records)")
                deleted_count = self.delete_polymorphic_records_by_type(
                    table_name, community_object_type, community_ids
                )
                deleted_counts[table_name] = deleted_count
                
                if deleted_count > 0:
                    self.logger.info(f"Deleted {deleted_count:,} {table_name} records for communities")
                    
            except Exception as e:
                self.logger.error(f"Error deleting {table_name} for communities: {e}")
                self.db.rollback()
                raise
                
        return deleted_counts
        
    def delete_tenant_polymorphic_dependencies(self, tenant_ids: List[int]) -> Dict[str, int]:
        """
        Delete all polymorphic dependencies for tenants
        Based on discovery results: MASSIVE volumes
        """
        deleted_counts = {}
        tenant_object_type = self.OBJECT_TYPES['dstTenant']
        
        # Level 1: Delete polymorphic dependencies in order of volume (largest first)
        # These are MASSIVE volumes - need careful batch processing
        polymorphic_tables = [
            ('phone', 5912600),    # 5.9M+ records
            ('address', 3547560),  # 3.5M+ records  
            ('note', 1184463),     # 1.2M+ records
            ('email', 29341)       # 29K+ records
        ]
        
        for table_name, expected_volume in polymorphic_tables:
            if self.interrupted:
                break
                
            try:
                self.logger.info(f"Deleting {table_name} records for {len(tenant_ids)} tenants (expected ~{expected_volume:,} records)")
                self.logger.warning(f"This may take a LONG time due to volume!")
                
                deleted_count = self.delete_polymorphic_records_by_type(
                    table_name, tenant_object_type, tenant_ids
                )
                deleted_counts[table_name] = deleted_count
                
                if deleted_count > 0:
                    self.logger.info(f"Deleted {deleted_count:,} {table_name} records for tenants")
                    
            except Exception as e:
                self.logger.error(f"Error deleting {table_name} for tenants: {e}")
                self.db.rollback()
                raise
                
        return deleted_counts
        
    def delete_contact_dependencies(self, contact_id: int, object_type_id: int) -> Dict[str, int]:
        """
        Delete all dependencies for a single contact based on its object type
        """
        deleted_counts = {}
        
        # Determine deletion strategy based on object type
        if object_type_id == self.OBJECT_TYPES['dstCommunity']:
            # Community - moderate volume
            deleted_counts = self.delete_community_polymorphic_dependencies([contact_id])
        elif object_type_id == self.OBJECT_TYPES['dstTenant']:
            # Tenant - MASSIVE volume, handle carefully
            self.logger.warning(f"Deleting tenant {contact_id} - this may take a while due to large volume")
            deleted_counts = self.delete_tenant_polymorphic_dependencies([contact_id])
        else:
            # Other contact types - use generic polymorphic deletion
            deleted_counts = self.delete_generic_polymorphic_dependencies([contact_id], object_type_id)
            
        # Delete direct foreign key dependencies
        direct_dependencies = [
            'bank', 'subscription', 'contact_batch', 'contact_logical_unit', 
            'nes_anet_customer_profile'
        ]
        
        cursor = self.db.cursor()
        for table in direct_dependencies:
            if self.interrupted:
                break
                
            try:
                cursor.execute(f"DELETE FROM {table} WHERE contact_id = %s", (contact_id,))
                deleted_count = cursor.rowcount
                deleted_counts[table] = deleted_counts.get(table, 0) + deleted_count
                
                if deleted_count > 0:
                    self.logger.debug(f"Deleted {deleted_count} {table} records for contact {contact_id}")
                    
                self.db.commit()
                
            except Exception as e:
                self.logger.error(f"Error deleting {table} for contact {contact_id}: {e}")
                self.db.rollback()
                raise
                
        return deleted_counts
        
    def delete_generic_polymorphic_dependencies(self, contact_ids: List[int], object_type_id: int) -> Dict[str, int]:
        """
        Delete polymorphic dependencies for generic contact types
        """
        deleted_counts = {}
        
        # Standard polymorphic tables
        polymorphic_tables = ['address', 'phone', 'note', 'email']
        
        for table_name in polymorphic_tables:
            if self.interrupted:
                break
                
            try:
                deleted_count = self.delete_polymorphic_records_by_type(
                    table_name, object_type_id, contact_ids
                )
                deleted_counts[table_name] = deleted_count
                
                if deleted_count > 0:
                    self.logger.info(f"Deleted {deleted_count:,} {table_name} records")
                    
            except Exception as e:
                self.logger.error(f"Error deleting {table_name}: {e}")
                self.db.rollback()
                raise
                
        return deleted_counts
        
    def delete_contacts_batch(self, cutoff_id: int, object_type_filter: Optional[int] = None) -> Dict[str, int]:
        """
        Delete contacts and all their dependencies in batches
        """
        cursor = self.db.cursor()
        total_summary = {}
        processed_contacts = 0
        batch_size = self.BATCH_SIZES['contact']
        
        # Build query with optional object type filter
        where_clause = "WHERE contact_id <= %s"
        params = [cutoff_id]
        
        if object_type_filter:
            where_clause += " AND object_type_id = %s"
            params.append(object_type_filter)
            
        self.logger.info(f"Starting contact deletion up to ID {cutoff_id}")
        if object_type_filter:
            self.logger.info(f"Filtering to object_type_id = {object_type_filter}")
            
        while not self.interrupted:
            cursor.execute(f"""
                SELECT contact_id, object_type_id FROM contact 
                {where_clause}
                ORDER BY contact_id 
                LIMIT %s
            """, params + [batch_size])
            
            contacts = cursor.fetchall()
            if not contacts:
                break
                
            for contact_id, object_type_id in contacts:
                if self.interrupted:
                    break
                    
                try:
                    # Delete all dependencies first
                    dependency_summary = self.delete_contact_dependencies(contact_id, object_type_id)
                    
                    # Then delete the contact itself
                    cursor.execute("DELETE FROM contact WHERE contact_id = %s", (contact_id,))
                    contact_deleted = cursor.rowcount
                    
                    if contact_deleted > 0:
                        dependency_summary['contact'] = dependency_summary.get('contact', 0) + contact_deleted
                        processed_contacts += 1
                        
                        # Update totals
                        for table, count in dependency_summary.items():
                            total_summary[table] = total_summary.get(table, 0) + count
                            
                        self.db.commit()
                        
                        if processed_contacts % 10 == 0:
                            self.logger.info(f"Processed {processed_contacts} contacts")
                            
                except Exception as e:
                    self.logger.error(f"Error deleting contact {contact_id}: {e}")
                    self.db.rollback()
                    continue
                    
            # Update params for next batch
            if contacts:
                last_contact_id = contacts[-1][0]
                params[0] = last_contact_id - 1  # Avoid reprocessing
                
        self.logger.info(f"Contact deletion completed. Processed {processed_contacts} contacts")
        return total_summary
        
    def delete_readings_batch(self, cutoff_id: int) -> int:
        """
        Delete non-billing readings in batches (optimized for large volume)
        """
        cursor = self.db.cursor()
        total_deleted = 0
        batch_size = self.BATCH_SIZES['reading']
        
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
            
            if total_deleted % 100000 == 0:
                self.logger.info(f"Deleted {total_deleted:,} readings so far")
                
            if deleted_count < batch_size:
                break
                
        self.logger.info(f"Reading deletion completed. Deleted {total_deleted:,} readings")
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
            
            if table_name:
                self.logger.info(f"Processing single table: {table_name}")
                
                if table_name == 'contact':
                    cutoff_id = self.cutoff_config.get('contact_cutoff', 0)
                    summary = self.delete_contacts_batch(cutoff_id)
                    self.logger.info(f"Contact deletion summary: {summary}")
                    
                elif table_name == 'community':
                    cutoff_id = self.cutoff_config.get('contact_cutoff', 0)
                    community_type = self.OBJECT_TYPES['dstCommunity']
                    summary = self.delete_contacts_batch(cutoff_id, community_type)
                    self.logger.info(f"Community deletion summary: {summary}")
                    
                elif table_name == 'reading':
                    cutoff_id = self.cutoff_config.get('reading_cutoff', 0)
                    deleted = self.delete_readings_batch(cutoff_id)
                    self.logger.info(f"Deleted {deleted:,} readings")
                    
                else:
                    self.logger.error(f"Table {table_name} not supported")
                    
            else:
                self.logger.info("Processing all tables in dependency order")
                
                # Process readings first (independent, largest volume)
                reading_cutoff = self.cutoff_config.get('reading_cutoff', 0)
                if reading_cutoff > 0:
                    self.delete_readings_batch(reading_cutoff)
                    
                # Process communities first (smaller volume, safer)
                contact_cutoff = self.cutoff_config.get('contact_cutoff', 0)
                if contact_cutoff > 0:
                    community_type = self.OBJECT_TYPES['dstCommunity']
                    self.logger.info("Starting with community cleanup (safest)")
                    self.delete_contacts_batch(contact_cutoff, community_type)
                    
                    # Then process other contact types
                    self.logger.info("Processing remaining contact types")
                    self.delete_contacts_batch(contact_cutoff)
                    
        except Exception as e:
            self.logger.error(f"Deletion process failed: {e}")
            if self.db:
                self.db.rollback()
            raise
        finally:
            self.disconnect()

def main():
    parser = argparse.ArgumentParser(description='Production NES Database Cleanup - Batch Deleter')
    parser.add_argument('--host', default='localhost', help='Database host')
    parser.add_argument('--user', required=True, help='Database user')
    parser.add_argument('--password', required=True, help='Database password')
    parser.add_argument('--database', default='nes', help='Database name')
    parser.add_argument('--cutoff-config', required=True, help='Path to cutoff configuration JSON file')
    parser.add_argument('--table', help='Specific table to process (contact, community, reading)')
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
    
    deleter = ProductionBatchDeleter(db_config, cutoff_config)
    
    try:
        deleter.run_deletion(args.table, args.dry_run)
    except Exception as e:
        logging.error(f"Deletion failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()

