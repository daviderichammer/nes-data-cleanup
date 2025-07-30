#!/usr/bin/env python3
"""
NES Database Cleanup - Contact Type Checker
This script checks the actual contact types in the database to help identify
the correct types for closed/inactive communities.
"""

import mysql.connector
import argparse
import logging
from typing import List, Dict

class ContactTypeChecker:
    def __init__(self, db_config: dict):
        """Initialize with database configuration"""
        self.db_config = db_config
        self.db = None
        self.setup_logging()
        
    def setup_logging(self):
        """Configure logging"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger(__name__)
        
    def connect(self):
        """Connect to database"""
        try:
            self.db = mysql.connector.connect(**self.db_config)
            self.logger.info("Connected to database successfully")
        except mysql.connector.Error as e:
            self.logger.error(f"Database connection failed: {e}")
            raise
            
    def disconnect(self):
        """Disconnect from database"""
        if self.db:
            self.db.close()
            self.logger.info("Disconnected from database")
            
    def get_all_contact_types(self) -> List[Dict]:
        """Get all contact types with counts"""
        cursor = self.db.cursor()
        cursor.execute("""
            SELECT 
                ct.contact_type_id,
                ct.contact_type,
                COUNT(c.contact_id) as contact_count
            FROM contact_type ct
            LEFT JOIN contact c ON ct.contact_type_id = c.contact_type_id
            GROUP BY ct.contact_type_id, ct.contact_type
            ORDER BY contact_count DESC
        """)
        
        results = []
        for row in cursor.fetchall():
            results.append({
                'contact_type_id': row[0],
                'contact_type': row[1],
                'contact_count': row[2]
            })
            
        return results
        
    def find_potential_closed_types(self) -> List[Dict]:
        """Find contact types that might indicate closed/inactive communities"""
        cursor = self.db.cursor()
        cursor.execute("""
            SELECT 
                ct.contact_type_id,
                ct.contact_type,
                COUNT(c.contact_id) as contact_count
            FROM contact_type ct
            LEFT JOIN contact c ON ct.contact_type_id = c.contact_type_id
            WHERE LOWER(ct.contact_type) LIKE '%clos%'
               OR LOWER(ct.contact_type) LIKE '%inact%'
               OR LOWER(ct.contact_type) LIKE '%term%'
               OR LOWER(ct.contact_type) LIKE '%end%'
               OR LOWER(ct.contact_type) LIKE '%zy%'
               OR LOWER(ct.contact_type) LIKE '%dead%'
               OR LOWER(ct.contact_type) LIKE '%cancel%'
               OR LOWER(ct.contact_type) LIKE '%expir%'
               OR LOWER(ct.contact_type) LIKE '%suspend%'
            GROUP BY ct.contact_type_id, ct.contact_type
            ORDER BY contact_count DESC
        """)
        
        results = []
        for row in cursor.fetchall():
            results.append({
                'contact_type_id': row[0],
                'contact_type': row[1],
                'contact_count': row[2]
            })
            
        return results
        
    def find_community_types(self) -> List[Dict]:
        """Find contact types that might be community-related"""
        cursor = self.db.cursor()
        cursor.execute("""
            SELECT 
                ct.contact_type_id,
                ct.contact_type,
                COUNT(c.contact_id) as contact_count
            FROM contact_type ct
            LEFT JOIN contact c ON ct.contact_type_id = c.contact_type_id
            WHERE LOWER(ct.contact_type) LIKE '%commun%'
               OR LOWER(ct.contact_type) LIKE '%proper%'
               OR LOWER(ct.contact_type) LIKE '%build%'
               OR LOWER(ct.contact_type) LIKE '%complex%'
               OR LOWER(ct.contact_type) LIKE '%site%'
               OR LOWER(ct.contact_type) LIKE '%location%'
            GROUP BY ct.contact_type_id, ct.contact_type
            ORDER BY contact_count DESC
        """)
        
        results = []
        for row in cursor.fetchall():
            results.append({
                'contact_type_id': row[0],
                'contact_type': row[1],
                'contact_count': row[2]
            })
            
        return results
        
    def get_old_contacts_by_type(self) -> List[Dict]:
        """Get contacts older than 7 years grouped by contact type"""
        cursor = self.db.cursor()
        cursor.execute("""
            SELECT 
                ct.contact_type,
                COUNT(*) as old_contacts,
                MIN(c.last_updated_on) as oldest_update,
                MAX(c.last_updated_on) as newest_update
            FROM contact c
            JOIN contact_type ct ON c.contact_type_id = ct.contact_type_id
            WHERE c.last_updated_on < DATE_SUB(NOW(), INTERVAL 7 YEAR)
            GROUP BY ct.contact_type_id, ct.contact_type
            HAVING COUNT(*) > 0
            ORDER BY old_contacts DESC
        """)
        
        results = []
        for row in cursor.fetchall():
            results.append({
                'contact_type': row[0],
                'old_contacts': row[1],
                'oldest_update': row[2],
                'newest_update': row[3]
            })
            
        return results
        
    def generate_report(self):
        """Generate comprehensive contact type report"""
        print("\n" + "="*80)
        print("CONTACT TYPE ANALYSIS REPORT")
        print("="*80)
        
        # All contact types
        print("\n1. ALL CONTACT TYPES (by usage count):")
        print("-" * 50)
        all_types = self.get_all_contact_types()
        for ct in all_types[:20]:  # Show top 20
            print(f"  {ct['contact_type']:<30} {ct['contact_count']:>8,} contacts")
            
        if len(all_types) > 20:
            print(f"  ... and {len(all_types) - 20} more types")
            
        # Potential closed types
        print("\n2. POTENTIAL CLOSED/INACTIVE TYPES:")
        print("-" * 50)
        closed_types = self.find_potential_closed_types()
        if closed_types:
            for ct in closed_types:
                print(f"  {ct['contact_type']:<30} {ct['contact_count']:>8,} contacts")
        else:
            print("  No contact types found matching closed/inactive patterns")
            
        # Community types
        print("\n3. POTENTIAL COMMUNITY TYPES:")
        print("-" * 50)
        community_types = self.find_community_types()
        if community_types:
            for ct in community_types:
                print(f"  {ct['contact_type']:<30} {ct['contact_count']:>8,} contacts")
        else:
            print("  No contact types found matching community patterns")
            
        # Old contacts by type
        print("\n4. CONTACTS OLDER THAN 7 YEARS (by type):")
        print("-" * 50)
        old_contacts = self.get_old_contacts_by_type()
        for ct in old_contacts[:15]:  # Show top 15
            print(f"  {ct['contact_type']:<30} {ct['old_contacts']:>8,} old contacts")
            
        print("\n" + "="*80)
        print("RECOMMENDATIONS:")
        print("="*80)
        
        if closed_types:
            print("\nBased on the analysis, consider using these contact types for community cleanup:")
            for ct in closed_types:
                print(f"  - '{ct['contact_type']}' ({ct['contact_count']:,} contacts)")
                
            print("\nUpdate your cutoff identification queries to use:")
            print("  ct.contact_type IN (", end="")
            type_list = [f"'{ct['contact_type']}'" for ct in closed_types]
            print(", ".join(type_list), end="")
            print(")")
        else:
            print("\nNo obvious closed/inactive contact types found.")
            print("You may need to:")
            print("  1. Review the full contact type list above")
            print("  2. Consult with business users about which types indicate closed communities")
            print("  3. Consider using a different approach (e.g., based on last activity date only)")
            
        print("\n" + "="*80)

def main():
    parser = argparse.ArgumentParser(description='Check contact types in NES database')
    parser.add_argument('--host', default='localhost', help='Database host')
    parser.add_argument('--user', required=True, help='Database user')
    parser.add_argument('--password', required=True, help='Database password')
    parser.add_argument('--database', default='nes', help='Database name')
    
    args = parser.parse_args()
    
    db_config = {
        'host': args.host,
        'user': args.user,
        'password': args.password,
        'database': args.database
    }
    
    checker = ContactTypeChecker(db_config)
    
    try:
        checker.connect()
        checker.generate_report()
    except Exception as e:
        logging.error(f"Error during contact type analysis: {e}")
        raise
    finally:
        checker.disconnect()

if __name__ == '__main__':
    main()

