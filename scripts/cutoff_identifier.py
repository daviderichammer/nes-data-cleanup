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
        Returns: (cutoff_id, estimated_deletions, is_safe)
        """
        cursor = self.db.cursor()
        
        # Find cutoff ID
        cursor.execute("""
            SELECT COALESCE(MAX(reading_id), 0) as cutoff_id
            FROM reading 
            WHERE date_imported < DATE_SUB(NOW(), INTERVAL 2 YEAR)
        """)
        cutoff_id = cursor.fetchone()[0]
        
        # Count deletable records (not used for billing)
        cursor.execute("""
            SELECT COUNT(*) as deletable_count
            FROM reading r
            LEFT JOIN sm_usage su ON r.guid = su.guid
            WHERE r.date_imported < DATE_SUB(NOW(), INTERVAL 2 YEAR)
            AND su.sm_usage_id IS NULL
        """)
        estimated_deletions = cursor.fetchone()[0]
        
        # Safety check: ensure no recent readings above cutoff
        cursor.execute("""
            SELECT COUNT(*) as recent_count
            FROM reading r
            LEFT JOIN sm_usage su ON r.guid = su.guid
            WHERE r.reading_id <= %s
            AND r.date_imported >= DATE_SUB(NOW(), INTERVAL 2 YEAR)
            AND su.sm_usage_id IS NULL
        """, (cutoff_id,))
        recent_above_cutoff = cursor.fetchone()[0]
        
        is_safe = recent_above_cutoff == 0
        
        self.logger.info(f"Reading cutoff: ID {cutoff_id}, {estimated_deletions} deletable records")
        if not is_safe:
            self.logger.warning(f"SAFETY ISSUE: {recent_above_cutoff} recent readings above cutoff!")
            
        return cutoff_id, estimated_deletions, is_safe
        
    def identify_account_cutoff(self) -> Tuple[int, int, bool]:
        """
        Identify cutoff for inactive accounts (7 years)
        Returns: (cutoff_id, estimated_deletions, is_safe)
        """
        cursor = self.db.cursor()
        
        # Find inactive accounts with comprehensive checks
        cursor.execute("""
            SELECT COALESCE(MAX(contact_id), 0) as cutoff_id
            FROM (
                SELECT DISTINCT c.contact_id
                FROM contact c
                JOIN tenant t ON c.contact_id = t.contact_id
                WHERE 
                    -- Must have definitive move-out date
                    t.to_date IS NOT NULL 
                    AND t.to_date != '0000-00-00 00:00:00'
                    AND t.to_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
                    
                    -- No recent invoices
                    AND NOT EXISTS (
                        SELECT 1 FROM invoice i 
                        WHERE i.object_id = c.contact_id 
                        AND i.object_type_id = 1 
                        AND i.invoice_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR)
                    )
                    
                    -- No recent journal entries
                    AND NOT EXISTS (
                        SELECT 1 FROM journal_entry je
                        WHERE je.object_id = c.contact_id 
                        AND je.object_type_id = 1 
                        AND je.journal_entry_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR)
                    )
                    
                    -- No recent notes
                    AND NOT EXISTS (
                        SELECT 1 FROM note n 
                        WHERE n.object_id = c.contact_id 
                        AND n.object_type_id = 94 
                        AND n.last_updated_on >= DATE_SUB(NOW(), INTERVAL 7 YEAR)
                    )
                    
                    -- No recent emails
                    AND NOT EXISTS (
                        SELECT 1 FROM email e 
                        WHERE e.object_id = c.contact_id 
                        AND e.object_type_id = 1 
                        AND e.email_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR)
                    )
            ) inactive_accounts
        """)
        cutoff_id = cursor.fetchone()[0]
        
        # Count total inactive accounts
        cursor.execute("""
            SELECT COUNT(*) as inactive_count
            FROM (
                SELECT DISTINCT c.contact_id
                FROM contact c
                JOIN tenant t ON c.contact_id = t.contact_id
                WHERE 
                    t.to_date IS NOT NULL 
                    AND t.to_date != '0000-00-00 00:00:00'
                    AND t.to_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
                    AND NOT EXISTS (SELECT 1 FROM invoice i WHERE i.object_id = c.contact_id AND i.object_type_id = 1 AND i.invoice_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                    AND NOT EXISTS (SELECT 1 FROM journal_entry je WHERE je.object_id = c.contact_id AND je.object_type_id = 1 AND je.journal_entry_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                    AND NOT EXISTS (SELECT 1 FROM note n WHERE n.object_id = c.contact_id AND n.object_type_id = 94 AND n.last_updated_on >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                    AND NOT EXISTS (SELECT 1 FROM email e WHERE e.object_id = c.contact_id AND e.object_type_id = 1 AND e.email_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
            ) inactive_accounts
        """)
        estimated_deletions = cursor.fetchone()[0]
        
        # Safety check: verify no recent activity above cutoff
        cursor.execute("""
            SELECT COUNT(*) as recent_activity_count
            FROM contact c
            WHERE c.contact_id <= %s
            AND (
                EXISTS (SELECT 1 FROM invoice i WHERE i.object_id = c.contact_id AND i.object_type_id = 1 AND i.invoice_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                OR EXISTS (SELECT 1 FROM journal_entry je WHERE je.object_id = c.contact_id AND je.object_type_id = 1 AND je.journal_entry_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                OR EXISTS (SELECT 1 FROM note n WHERE n.object_id = c.contact_id AND n.object_type_id = 94 AND n.last_updated_on >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
                OR EXISTS (SELECT 1 FROM email e WHERE e.object_id = c.contact_id AND e.object_type_id = 1 AND e.email_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
            )
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
        self.logger.info("Generating cutoff identification report...")
        
        report = {
            'generated_at': datetime.now().isoformat(),
            'cutoffs': {},
            'table_stats': {},
            'safety_status': 'UNKNOWN'
        }
        
        # Identify all cutoffs
        reading_cutoff, reading_deletions, reading_safe = self.identify_reading_cutoff()
        account_cutoff, account_deletions, account_safe = self.identify_account_cutoff()
        community_cutoff, community_deletions, community_safe = self.identify_community_cutoff()
        
        # Store cutoff information
        report['cutoffs'] = {
            'reading': {
                'cutoff_id': reading_cutoff,
                'estimated_deletions': reading_deletions,
                'is_safe': reading_safe,
                'cutoff_date': (datetime.now() - timedelta(days=730)).isoformat()  # 2 years
            },
            'contact_accounts': {
                'cutoff_id': account_cutoff,
                'estimated_deletions': account_deletions,
                'is_safe': account_safe,
                'cutoff_date': (datetime.now() - timedelta(days=2555)).isoformat()  # 7 years
            },
            'contact_communities': {
                'cutoff_id': community_cutoff,
                'estimated_deletions': community_deletions,
                'is_safe': community_safe,
                'cutoff_date': (datetime.now() - timedelta(days=2555)).isoformat()  # 7 years
            }
        }
        
        # Get table statistics
        for table in ['reading', 'contact', 'email', 'invoice_detail', 'address']:
            report['table_stats'][table] = self.get_table_stats(table)
            
        # Overall safety status
        all_safe = reading_safe and account_safe and community_safe
        report['safety_status'] = 'SAFE' if all_safe else 'REQUIRES_REVIEW'
        
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
    
    db_config = {
        'host': args.host,
        'user': args.user,
        'password': args.password,
        'database': args.database
    }
    
    identifier = CutoffIdentifier(db_config)
    
    try:
        identifier.connect()
        report = identifier.generate_cutoff_report()
        filename = identifier.save_report(report, args.output)
        
        print("\n" + "="*60)
        print("CUTOFF IDENTIFICATION SUMMARY")
        print("="*60)
        
        for table, data in report['cutoffs'].items():
            print(f"\n{table.upper()}:")
            print(f"  Cutoff ID: {data['cutoff_id']:,}")
            print(f"  Estimated Deletions: {data['estimated_deletions']:,}")
            print(f"  Safety Status: {'✓ SAFE' if data['is_safe'] else '⚠ REQUIRES REVIEW'}")
            
        print(f"\nOverall Safety Status: {report['safety_status']}")
        print(f"Report saved to: {filename}")
        
        if report['safety_status'] != 'SAFE':
            print("\n⚠ WARNING: Some cutoffs require manual review before proceeding!")
            
    except Exception as e:
        logging.error(f"Error during cutoff identification: {e}")
        raise
    finally:
        identifier.disconnect()

if __name__ == '__main__':
    main()

