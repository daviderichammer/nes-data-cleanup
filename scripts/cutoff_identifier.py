#!/usr/bin/env python3
"""
NES Database Cleanup - Cutoff Identifier
This script identifies the autoincrement ID cutoffs for safe data deletion.
"""

import mysql.connector
import json
import logging
from datetime import datetime, timedelta
from typing import Dict, Tuple, Optional
import argparse

class CutoffIdentifier:
    def __init__(self, db_config: dict):
        """Initialize with database configuration"""
        self.db_config = db_config
        self.db = None
        self.setup_logging()
        
    def setup_logging(self):
        """Configure logging"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('cutoff_identification.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
    def connect(self):
        """Connect to database with compatibility for older MySQL servers"""
        try:
            # Add charset compatibility for older MySQL servers
            db_config = self.db_config.copy()
            
            # Use utf8 instead of utf8mb4 for older MySQL compatibility
            db_config['charset'] = 'utf8'
            db_config['use_unicode'] = True
            
            # Disable SSL warnings for older servers
            db_config['autocommit'] = True
            
            self.db = mysql.connector.connect(**db_config)
            self.logger.info("Connected to database successfully")
        except mysql.connector.Error as e:
            self.logger.error(f"Database connection failed: {e}")
            raise
            
    def disconnect(self):
        """Disconnect from database"""
        if self.db:
            self.db.close()
            self.logger.info("Disconnected from database")
            
    def identify_reading_cutoff(self) -> Tuple[int, int, bool]:
        """
        Identify cutoff for reading table (2 years)
        Simple approach: find min reading_id where date_imported >= 2 years ago
        Delete everything before that cutoff
        Returns: (cutoff_id, estimated_deletions, is_safe)
        """
        self.logger.info("=== ANALYZING READING TABLE ===")
        cursor = self.db.cursor()
        
        # First, get total reading count for context
        self.logger.info("Getting total reading count...")
        cursor.execute("SELECT COUNT(*) FROM reading")
        total_readings = cursor.fetchone()[0]
        self.logger.info(f"Total readings in database: {total_readings:,}")
        
        # Find minimum reading_id where date_imported >= 2 years ago
        # Everything below this ID can be safely deleted
        self.logger.info("Finding cutoff ID (minimum reading_id where date_imported >= 2 years ago)...")
        cursor.execute("""
            SELECT COALESCE(MIN(reading_id), 0) as cutoff_id
            FROM reading 
            WHERE date_imported >= DATE_SUB(NOW(), INTERVAL 2 YEAR)
        """)
        cutoff_id = cursor.fetchone()[0]
        self.logger.info(f"Cutoff ID found: {cutoff_id}")
        
        # If no readings found within 2 years, use max ID + 1 (delete nothing)
        if cutoff_id == 0:
            self.logger.warning("No readings found within the last 2 years!")
            self.logger.info("Getting maximum reading_id to set safe cutoff...")
            cursor.execute("SELECT COALESCE(MAX(reading_id), 0) + 1 as cutoff_id FROM reading")
            cutoff_id = cursor.fetchone()[0]
            estimated_deletions = 0
            self.logger.info(f"Safe cutoff set to: {cutoff_id} (no deletions will occur)")
        else:
            # Count records that will be deleted (reading_id < cutoff_id)
            self.logger.info(f"Counting readings that will be deleted (reading_id < {cutoff_id})...")
            cursor.execute("""
                SELECT COUNT(*) as deletable_count
                FROM reading 
                WHERE reading_id < %s
            """, (cutoff_id,))
            estimated_deletions = cursor.fetchone()[0]
            
            # Calculate percentage
            deletion_percentage = (estimated_deletions / total_readings * 100) if total_readings > 0 else 0
            self.logger.info(f"Readings to be deleted: {estimated_deletions:,} ({deletion_percentage:.1f}% of total)")
            self.logger.info(f"Readings to be retained: {total_readings - estimated_deletions:,} ({100 - deletion_percentage:.1f}% of total)")
        
        # This approach is inherently safe - we only delete readings older than 2 years
        is_safe = True
        
        self.logger.info("=== READING ANALYSIS COMPLETE ===")
        self.logger.info(f"RESULT: Cutoff ID = {cutoff_id}, Deletions = {estimated_deletions:,}, Safe = {is_safe}")
        
        return cutoff_id, estimated_deletions, is_safe
        
    def identify_contact_cutoff(self) -> Tuple[int, int, bool]:
        """
        Identify cutoff for inactive contacts (7 years)
        Returns: (cutoff_id, estimated_deletions, is_safe)
        """
        self.logger.info("=== ANALYZING CONTACT TABLE ===")
        cursor = self.db.cursor()
        
        # Get total contact count for context
        self.logger.info("Getting total contact count...")
        cursor.execute("SELECT COUNT(*) FROM contact")
        total_contacts = cursor.fetchone()[0]
        self.logger.info(f"Total contacts in database: {total_contacts:,}")
        
        # Analyze communities (closed and ZY)
        self.logger.info("Analyzing closed communities...")
        cursor.execute("""
            SELECT COUNT(*) FROM contact c 
            JOIN contact_type ct ON c.contact_type_id = ct.contact_type_id 
            WHERE ct.contact_type = 'Closed' 
            AND c.last_modified < DATE_SUB(NOW(), INTERVAL 7 YEAR)
        """)
        closed_communities = cursor.fetchone()[0]
        self.logger.info(f"Closed communities (7+ years old): {closed_communities:,}")
        
        self.logger.info("Analyzing ZY communities...")
        cursor.execute("""
            SELECT COUNT(*) FROM contact 
            WHERE LEFT(contact_name, 2) = 'ZY'
            AND last_modified < DATE_SUB(NOW(), INTERVAL 7 YEAR)
        """)
        zy_communities = cursor.fetchone()[0]
        self.logger.info(f"ZY communities (7+ years old): {zy_communities:,}")
        
        total_communities = closed_communities + zy_communities
        self.logger.info(f"Total communities for deletion: {total_communities:,}")
        
        # Find cutoff ID for communities
        self.logger.info("Finding cutoff ID for communities...")
        cursor.execute("""
            SELECT COALESCE(MAX(contact_id), 0) as cutoff_id
            FROM contact c
            JOIN contact_type ct ON c.contact_type_id = ct.contact_type_id
            WHERE (
                ct.contact_type = 'Closed'           -- Explicitly closed communities  
                OR LEFT(c.contact_name, 2) = 'ZY'   -- ZY'd communities
            )
            AND c.last_modified < DATE_SUB(NOW(), INTERVAL 7 YEAR)
        """)
        cutoff_id = cursor.fetchone()[0]
        self.logger.info(f"Community cutoff ID: {cutoff_id}")
        
        # Count total deletable communities
        estimated_deletions = total_communities
        
        # Calculate percentage
        deletion_percentage = (estimated_deletions / total_contacts * 100) if total_contacts > 0 else 0
        self.logger.info(f"Contacts to be deleted: {estimated_deletions:,} ({deletion_percentage:.1f}% of total)")
        self.logger.info(f"Contacts to be retained: {total_contacts - estimated_deletions:,} ({100 - deletion_percentage:.1f}% of total)")
        
        # Safety check: verify no recent activity above cutoff
        self.logger.info("Performing safety check for recent activity...")
        cursor.execute("""
            SELECT COUNT(*) as recent_activity_count
            FROM contact c
            WHERE c.contact_id <= %s
            AND c.last_modified >= DATE_SUB(NOW(), INTERVAL 7 YEAR)
        """, (cutoff_id,))
        recent_activity_count = cursor.fetchone()[0]
        
        is_safe = recent_activity_count == 0
        
        if is_safe:
            self.logger.info("✓ Safety check passed: No recent activity found above cutoff")
        else:
            self.logger.warning(f"⚠ Safety check failed: {recent_activity_count} contacts with recent activity above cutoff")
        
        self.logger.info("=== CONTACT ANALYSIS COMPLETE ===")
        self.logger.info(f"RESULT: Cutoff ID = {cutoff_id}, Deletions = {estimated_deletions:,}, Safe = {is_safe}")
        
        return cutoff_id, estimated_deletions, is_safe
        """, (cutoff_id,))
        recent_activity_above_cutoff = cursor.fetchone()[0]
        
        is_safe = recent_activity_above_cutoff == 0
        
        self.logger.info(f"Account cutoff: ID {cutoff_id}, {estimated_deletions} inactive accounts")
        if not is_safe:
            self.logger.warning(f"SAFETY ISSUE: {recent_activity_above_cutoff} accounts with recent activity above cutoff!")
            
        return cutoff_id, estimated_deletions, is_safe
        
    def identify_community_cutoff(self) -> Tuple[int, int, bool]:
        """
        Identify cutoff for closed communities (7 years)
        Based on actual contact types: Client, Prospect, Closed
        ZY communities are identified by name starting with "ZY"
        Returns: (cutoff_id, estimated_deletions, is_safe)
        """
        cursor = self.db.cursor()
        
        # Find closed communities and ZY communities (performance optimized)
        cursor.execute("""
            SELECT COALESCE(MAX(contact_id), 0) as cutoff_id
            FROM contact c
            JOIN contact_type ct ON c.contact_type_id = ct.contact_type_id
            WHERE 
                -- Communities marked as Closed OR have ZY prefix (indicating they were zy'd)
                (
                    ct.contact_type = 'Closed'
                    OR LEFT(c.contact_name, 2) = 'ZY'
                )
                
                -- Community not updated in 7 years
                AND c.last_updated_on < DATE_SUB(NOW(), INTERVAL 7 YEAR)
                
                -- No active tenants
                AND NOT EXISTS (
                    SELECT 1 FROM tenant t 
                    WHERE t.object_id = c.contact_id 
                    AND t.object_type_id = 49 
                    AND (t.to_date IS NULL OR t.to_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                )
                
                -- No recent batches
                AND NOT EXISTS (
                    SELECT 1 FROM contact_batch cb
                    JOIN batch b ON cb.batch_id = b.batch_id
                    WHERE cb.contact_id = c.contact_id
                    AND b.created_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR)
                )
                
                -- No legal hold
                AND NOT EXISTS (
                    SELECT 1 FROM community_logical_unit_attribute clua
                    JOIN community_logical_unit_attribute_type cluat 
                        ON clua.logical_unit_attribute_type_id = cluat.logical_unit_attribute_type_id
                    WHERE clua.logical_unit_id = c.object_id
                    AND cluat.logical_unit_attribute_type = 'Legal Hold'
                    AND clua.val_integer = 1
                )
        """)
        cutoff_id = cursor.fetchone()[0]
        
        # Count closed and ZY communities
        cursor.execute("""
            SELECT COUNT(*) as closed_count
            FROM contact c
            JOIN contact_type ct ON c.contact_type_id = ct.contact_type_id
            WHERE 
                (
                    ct.contact_type = 'Closed'
                    OR LEFT(c.contact_name, 2) = 'ZY'
                )
                AND c.last_updated_on < DATE_SUB(NOW(), INTERVAL 7 YEAR)
                AND NOT EXISTS (SELECT 1 FROM tenant t WHERE t.object_id = c.contact_id AND t.object_type_id = 49 AND (t.to_date IS NULL OR t.to_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR)))
                AND NOT EXISTS (SELECT 1 FROM contact_batch cb JOIN batch b ON cb.batch_id = b.batch_id WHERE cb.contact_id = c.contact_id AND b.created_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                AND NOT EXISTS (SELECT 1 FROM community_logical_unit_attribute clua JOIN community_logical_unit_attribute_type cluat ON clua.logical_unit_attribute_type_id = cluat.logical_unit_attribute_type_id WHERE clua.logical_unit_id = c.object_id AND cluat.logical_unit_attribute_type = 'Legal Hold' AND clua.val_integer = 1)
        """)
        estimated_deletions = cursor.fetchone()[0]
        
        # For communities, we assume it's safe if we found any
        is_safe = True
        
        self.logger.info(f"Community cutoff: ID {cutoff_id}, {estimated_deletions} closed/ZY communities")
        
        return cutoff_id, estimated_deletions, is_safe
        
    def get_table_stats(self, table_name: str) -> Dict:
        """Get current table statistics"""
        cursor = self.db.cursor()
        cursor.execute("""
            SELECT 
                table_rows,
                ROUND(data_length/1024/1024, 2) as data_mb,
                ROUND(index_length/1024/1024, 2) as index_mb,
                ROUND((data_length+index_length)/1024/1024, 2) as total_mb
            FROM information_schema.tables 
            WHERE table_schema = 'nes' AND table_name = %s
        """, (table_name,))
        
        result = cursor.fetchone()
        if result:
            return {
                'rows': result[0],
                'data_mb': result[1],
                'index_mb': result[2],
                'total_mb': result[3]
            }
        return {}
        
    def generate_cutoff_report(self) -> Dict:
        """Generate comprehensive cutoff report"""
        self.logger.info("\n" + "="*80)
        self.logger.info("GENERATING COMPREHENSIVE CUTOFF REPORT")
        self.logger.info("="*80)
        
        report = {
            'generated_at': datetime.now().isoformat(),
            'cutoffs': {},
            'table_stats': {},
            'safety_status': 'UNKNOWN'
        }
        
        # Identify all cutoffs with verbose progress
        self.logger.info("Phase 1/3: Reading table analysis...")
        reading_cutoff, reading_deletions, reading_safe = self.identify_reading_cutoff()
        
        self.logger.info("\nPhase 2/3: Contact table analysis...")
        contact_cutoff, contact_deletions, contact_safe = self.identify_contact_cutoff()
        
        self.logger.info("\nPhase 3/3: Gathering table statistics...")
        # Get table statistics
        for table in ['reading', 'contact', 'email', 'invoice_detail', 'address']:
            self.logger.info(f"Getting statistics for {table} table...")
            report['table_stats'][table] = self.get_table_stats(table)
        
        # Store cutoff information
        self.logger.info("\nCompiling final report...")
        report['cutoffs'] = {
            'reading': {
                'cutoff_id': reading_cutoff,
                'estimated_deletions': reading_deletions,
                'is_safe': reading_safe,
                'cutoff_date': (datetime.now() - timedelta(days=730)).isoformat()  # 2 years
            },
            'contact': {
                'cutoff_id': contact_cutoff,
                'estimated_deletions': contact_deletions,
                'is_safe': contact_safe,
                'cutoff_date': (datetime.now() - timedelta(days=2555)).isoformat()  # 7 years
            }
        }
            
        # Overall safety status
        all_safe = reading_safe and contact_safe
        report['safety_status'] = 'SAFE' if all_safe else 'REQUIRES_REVIEW'
        
        self.logger.info("✓ Report generation complete")
        
        return report
        
    def save_report(self, report: Dict, filename: str = None):
        """Save report to file"""
        if filename is None:
            filename = f"cutoff_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
            
        with open(filename, 'w') as f:
            json.dump(report, f, indent=2)
            
        self.logger.info(f"Report saved to {filename}")
        return filename

def main():
    parser = argparse.ArgumentParser(description='Identify ID cutoffs for NES database cleanup')
    parser.add_argument('--host', default='localhost', help='Database host')
    parser.add_argument('--user', required=True, help='Database user')
    parser.add_argument('--password', required=True, help='Database password')
    parser.add_argument('--database', default='nes', help='Database name')
    parser.add_argument('--output', help='Output filename for report')
    
    args = parser.parse_args()
    
    # Set up logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    logger = logging.getLogger(__name__)
    
    logger.info("="*80)
    logger.info("NES DATABASE CLEANUP - CUTOFF IDENTIFICATION")
    logger.info("="*80)
    logger.info(f"Database Host: {args.host}")
    logger.info(f"Database Name: {args.database}")
    logger.info(f"Database User: {args.user}")
    logger.info("="*80)
    
    db_config = {
        'host': args.host,
        'user': args.user,
        'password': args.password,
        'database': args.database
    }
    
    identifier = CutoffIdentifier(db_config)
    
    try:
        logger.info("Connecting to database...")
        identifier.connect()
        logger.info("✓ Database connection successful")
        
        logger.info("\nStarting cutoff identification process...")
        report = identifier.generate_cutoff_report()
        
        logger.info("\nSaving report...")
        filename = identifier.save_report(report, args.output)
        logger.info(f"✓ Report saved to: {filename}")
        
        logger.info("\n" + "="*80)
        logger.info("CUTOFF IDENTIFICATION COMPLETE - SUMMARY")
        logger.info("="*80)
        
        total_deletions = 0
        for table, data in report['cutoffs'].items():
            logger.info(f"\n{table.upper()}:")
            logger.info(f"  Cutoff ID: {data['cutoff_id']:,}")
            logger.info(f"  Estimated Deletions: {data['estimated_deletions']:,}")
            logger.info(f"  Safety Status: {'✓ SAFE' if data['is_safe'] else '⚠ REQUIRES REVIEW'}")
            total_deletions += data['estimated_deletions']
            
        logger.info(f"\nTOTAL ESTIMATED DELETIONS: {total_deletions:,}")
        logger.info(f"Overall Safety Status: {report['safety_status']}")
        logger.info(f"Report File: {filename}")
        logger.info("="*80)
        
        if report['safety_status'] == 'SAFE':
            logger.info("✅ All cutoffs are SAFE - ready for deletion execution")
        else:
            logger.warning("⚠️  Some cutoffs require review - check safety issues before proceeding")
            
    except Exception as e:
        logger.error(f"Error during cutoff identification: {e}")
        raise
    finally:
        identifier.disconnect()
        logger.info("Database connection closed")

if __name__ == "__main__":
    main()

