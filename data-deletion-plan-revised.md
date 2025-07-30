# NES Database Data Deletion Plan - REVISED for Massive Scale

## Overview

**CRITICAL REVISION:** The original staging table approach is impractical for this database scale. With 500+ million rows in some tables, we need a fundamentally different approach using sequential ID-based deletion.

## Scale Reality Check

Based on the table statistics:
- `reading`: 321,937,425 rows (61.6 GB)
- `email_attachment`: 6,208,733 rows (420 GB)
- `address`: 72,622,403 rows (20.9 GB)
- `invoice_detail`: 122,172,327 rows (19 GB)

**Staging tables would:**
- Double the database size temporarily
- Take hours/days to populate
- Risk running out of disk space
- Create unnecessary complexity

## Revised Approach: Sequential ID-Based Deletion

Instead of staging tables, we will:

1. **Identify ID Cutoffs**: Find the autoincrement ID values that correspond to our time-based cutoffs (7 years, 2 years)
2. **Batch Delete by ID Range**: Delete records in small batches using `WHERE id BETWEEN x AND y`
3. **Process Incrementally**: Delete in chunks of 1000-10000 records at a time
4. **Monitor Progress**: Track deletion progress and database size reduction

## Benefits of ID-Based Approach

- **No Additional Storage**: No staging tables needed
- **Incremental Progress**: Can stop/resume at any point
- **Predictable Performance**: Small batch sizes ensure consistent performance
- **Real-time Monitoring**: Can track progress and database size reduction immediately
- **Safer**: Each batch is a small, atomic operation


## Phase 1: ID Cutoff Identification

### 1.1 Identify Time-Based Cutoff Points

For each target table, we need to find the autoincrement ID that corresponds to our time-based cutoffs:

**For Readings (2 years cutoff):**
```sql
-- Find the reading_id cutoff for 2 years ago
SELECT MAX(reading_id) as cutoff_reading_id
FROM reading 
WHERE date_imported < DATE_SUB(NOW(), INTERVAL 2 YEAR);
```

**For Accounts (7 years cutoff):**
```sql
-- Find contact_id cutoff for accounts with no activity in 7 years
-- This requires joining multiple tables to find the latest activity
SELECT MAX(c.contact_id) as cutoff_contact_id
FROM contact c
JOIN tenant t ON c.contact_id = t.contact_id
WHERE t.to_date IS NOT NULL 
AND t.to_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
AND NOT EXISTS (
    -- No recent invoices
    SELECT 1 FROM invoice i 
    WHERE i.object_id = c.contact_id 
    AND i.object_type_id = 1 
    AND i.invoice_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR)
)
AND NOT EXISTS (
    -- No recent notes
    SELECT 1 FROM note n 
    WHERE n.object_id = c.contact_id 
    AND n.object_type_id = 94 
    AND n.last_updated_on >= DATE_SUB(NOW(), INTERVAL 7 YEAR)
);
```

**For Communities (7 years cutoff):**
```sql
-- Find contact_id cutoff for closed communities
SELECT MAX(contact_id) as cutoff_community_id
FROM contact c
JOIN contact_type ct ON c.contact_type_id = ct.contact_type_id
WHERE ct.contact_type IN ('Closed', 'zy')
AND c.last_updated_on < DATE_SUB(NOW(), INTERVAL 7 YEAR);
```

### 1.2 Validate Cutoff Safety

Before proceeding, validate that our cutoffs are safe:

```sql
-- Count how many records would be affected
SELECT 
    'readings' as table_name,
    COUNT(*) as records_to_delete,
    (COUNT(*) * 100.0 / (SELECT COUNT(*) FROM reading)) as percentage
FROM reading r
LEFT JOIN sm_usage su ON r.guid = su.guid
WHERE r.reading_id <= @cutoff_reading_id
AND su.sm_usage_id IS NULL;

-- Verify no recent activity above cutoff
SELECT COUNT(*) as recent_activity_above_cutoff
FROM reading 
WHERE reading_id <= @cutoff_reading_id
AND date_imported >= DATE_SUB(NOW(), INTERVAL 2 YEAR);
```

### 1.3 Create Cutoff Configuration

Store the identified cutoffs in a configuration table or file:

```sql
CREATE TABLE deletion_cutoffs (
    table_name VARCHAR(64) PRIMARY KEY,
    cutoff_id BIGINT NOT NULL,
    cutoff_date DATETIME NOT NULL,
    estimated_deletions BIGINT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO deletion_cutoffs VALUES
('reading', @cutoff_reading_id, DATE_SUB(NOW(), INTERVAL 2 YEAR), @estimated_reading_deletions, NOW()),
('contact_accounts', @cutoff_contact_id, DATE_SUB(NOW(), INTERVAL 7 YEAR), @estimated_account_deletions, NOW()),
('contact_communities', @cutoff_community_id, DATE_SUB(NOW(), INTERVAL 7 YEAR), @estimated_community_deletions, NOW());
```


## Phase 2: Batch Deletion Strategy

### 2.1 Batch Size Determination

Choose batch sizes based on table characteristics:

- **Large tables (>100M rows)**: 1,000 records per batch
- **Medium tables (1M-100M rows)**: 5,000 records per batch  
- **Small tables (<1M rows)**: 10,000 records per batch

### 2.2 Deletion Order (Respecting Foreign Keys)

Based on foreign key analysis, delete in this order:

**For Account Cleanup:**
1. `email_attachment` (references `email`)
2. `email` (polymorphic to `contact`)
3. `tender_detail` (references `tender`)
4. `tender` (references `journal_entry`, polymorphic to `contact`)
5. `invoice_detail` (references `invoice`)
6. `invoice` (references `journal_entry`, polymorphic to `contact`)
7. `journal_entry` (polymorphic to `contact`)
8. `sm_bill_note` (references `sm_bill`)
9. `sm_bill` (references `tenant`)
10. `phone`, `address`, `note` (polymorphic to `contact`)
11. `tenant` (references `contact`)
12. `contact` (parent table)

**For Reading Cleanup:**
1. `reading` (standalone, not referenced by `sm_usage`)

### 2.3 Batch Deletion Logic

```sql
-- Example: Delete readings in batches
SET @batch_size = 1000;
SET @current_min_id = 1;
SET @cutoff_id = (SELECT cutoff_id FROM deletion_cutoffs WHERE table_name = 'reading');

WHILE @current_min_id <= @cutoff_id DO
    -- Delete batch
    DELETE r FROM reading r
    LEFT JOIN sm_usage su ON r.guid = su.guid
    WHERE r.reading_id BETWEEN @current_min_id AND (@current_min_id + @batch_size - 1)
    AND r.reading_id <= @cutoff_id
    AND su.sm_usage_id IS NULL;
    
    -- Log progress
    INSERT INTO deletion_log (table_name, batch_start_id, batch_end_id, records_deleted, deleted_at)
    VALUES ('reading', @current_min_id, @current_min_id + @batch_size - 1, ROW_COUNT(), NOW());
    
    -- Move to next batch
    SET @current_min_id = @current_min_id + @batch_size;
    
    -- Optional: Add delay to reduce system load
    SELECT SLEEP(0.1);
END WHILE;
```

### 2.4 Progress Monitoring

Create a logging table to track progress:

```sql
CREATE TABLE deletion_log (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(64) NOT NULL,
    batch_start_id BIGINT NOT NULL,
    batch_end_id BIGINT NOT NULL,
    records_deleted INT NOT NULL,
    deleted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_table_batch (table_name, batch_start_id)
);
```

Monitor progress with:

```sql
-- Check deletion progress
SELECT 
    table_name,
    COUNT(*) as batches_completed,
    SUM(records_deleted) as total_deleted,
    MAX(batch_end_id) as highest_id_processed,
    MIN(deleted_at) as started_at,
    MAX(deleted_at) as last_batch_at
FROM deletion_log 
GROUP BY table_name;

-- Check database size reduction
SELECT 
    table_name,
    ROUND(data_length/1024/1024, 2) AS data_mb,
    ROUND(index_length/1024/1024, 2) AS index_mb,
    ROUND((data_length+index_length)/1024/1024, 2) AS total_mb
FROM information_schema.tables 
WHERE table_schema = 'nes'
AND table_name IN ('reading', 'contact', 'email', 'invoice_detail')
ORDER BY (data_length+index_length) DESC;
```


## Phase 3: Automation and Safety Features

### 3.1 Python Script Framework

```python
import mysql.connector
import time
import logging
from datetime import datetime, timedelta

class DatabaseCleaner:
    def __init__(self, config):
        self.config = config
        self.db = mysql.connector.connect(**config['database'])
        self.setup_logging()
    
    def identify_cutoffs(self):
        """Phase 1: Identify ID cutoffs for each table"""
        cutoffs = {}
        
        # Reading cutoff (2 years)
        cursor = self.db.cursor()
        cursor.execute("""
            SELECT COALESCE(MAX(reading_id), 0) as cutoff_id
            FROM reading 
            WHERE date_imported < DATE_SUB(NOW(), INTERVAL 2 YEAR)
        """)
        cutoffs['reading'] = cursor.fetchone()[0]
        
        # Account cutoff (7 years) - more complex logic
        cursor.execute("""
            SELECT COALESCE(MAX(c.contact_id), 0) as cutoff_id
            FROM contact c
            JOIN tenant t ON c.contact_id = t.contact_id
            WHERE t.to_date IS NOT NULL 
            AND t.to_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
            -- Add additional safety checks here
        """)
        cutoffs['contact_accounts'] = cursor.fetchone()[0]
        
        return cutoffs
    
    def validate_cutoffs(self, cutoffs):
        """Validate that cutoffs are safe"""
        for table, cutoff_id in cutoffs.items():
            if table == 'reading':
                # Verify no recent readings above cutoff
                cursor = self.db.cursor()
                cursor.execute("""
                    SELECT COUNT(*) FROM reading 
                    WHERE reading_id <= %s 
                    AND date_imported >= DATE_SUB(NOW(), INTERVAL 2 YEAR)
                """, (cutoff_id,))
                
                recent_count = cursor.fetchone()[0]
                if recent_count > 0:
                    raise ValueError(f"Found {recent_count} recent readings above cutoff!")
    
    def delete_batch(self, table_name, start_id, end_id, cutoff_id):
        """Delete a single batch of records"""
        cursor = self.db.cursor()
        
        if table_name == 'reading':
            # Delete non-billing readings
            cursor.execute("""
                DELETE r FROM reading r
                LEFT JOIN sm_usage su ON r.guid = su.guid
                WHERE r.reading_id BETWEEN %s AND %s
                AND r.reading_id <= %s
                AND su.sm_usage_id IS NULL
            """, (start_id, end_id, cutoff_id))
        
        deleted_count = cursor.rowcount
        
        # Log the batch
        cursor.execute("""
            INSERT INTO deletion_log 
            (table_name, batch_start_id, batch_end_id, records_deleted)
            VALUES (%s, %s, %s, %s)
        """, (table_name, start_id, end_id, deleted_count))
        
        self.db.commit()
        return deleted_count
    
    def process_table(self, table_name, cutoff_id, batch_size=1000):
        """Process an entire table in batches"""
        current_id = 1
        total_deleted = 0
        
        while current_id <= cutoff_id:
            end_id = min(current_id + batch_size - 1, cutoff_id)
            
            deleted = self.delete_batch(table_name, current_id, end_id, cutoff_id)
            total_deleted += deleted
            
            self.logger.info(f"{table_name}: Processed batch {current_id}-{end_id}, deleted {deleted} records")
            
            current_id += batch_size
            
            # Small delay to reduce system load
            time.sleep(0.1)
        
        return total_deleted
```

### 3.2 Safety Features

**Mandatory Dry-Run Mode:**
```python
def run_cleanup(self, dry_run=True):
    """Main cleanup process"""
    if dry_run:
        self.logger.info("DRY RUN MODE - No data will be deleted")
        # Only identify and validate cutoffs
        cutoffs = self.identify_cutoffs()
        self.validate_cutoffs(cutoffs)
        self.log_estimated_deletions(cutoffs)
    else:
        self.logger.info("LIVE MODE - Data will be deleted")
        # Require explicit confirmation
        if not self.config.get('confirmed', False):
            raise ValueError("Must set 'confirmed': True in config for live mode")
```

**Safety Thresholds:**
```python
def check_safety_threshold(self, table_name, estimated_deletions):
    """Prevent accidental mass deletion"""
    cursor = self.db.cursor()
    cursor.execute(f"SELECT COUNT(*) FROM {table_name}")
    total_rows = cursor.fetchone()[0]
    
    deletion_percentage = (estimated_deletions / total_rows) * 100
    
    if deletion_percentage > self.config.get('max_deletion_percentage', 50):
        raise ValueError(
            f"Deletion would remove {deletion_percentage:.1f}% of {table_name} "
            f"(exceeds {self.config['max_deletion_percentage']}% threshold)"
        )
```

### 3.3 Configuration Management

```yaml
# config.yaml
database:
  host: "localhost"
  user: "cleanup_user"
  password: "secure_password"
  database: "nes"

safety:
  max_deletion_percentage: 50  # Never delete more than 50% of a table
  require_confirmation: true
  backup_required: true

batch_sizes:
  reading: 1000
  contact: 5000
  email: 2000

logging:
  level: "INFO"
  file: "/var/log/nes_cleanup.log"
```

### 3.4 Monitoring and Alerting

```python
def monitor_progress(self):
    """Generate progress report"""
    cursor = self.db.cursor()
    cursor.execute("""
        SELECT 
            table_name,
            COUNT(*) as batches,
            SUM(records_deleted) as total_deleted,
            MAX(batch_end_id) as progress_id,
            MIN(deleted_at) as started,
            MAX(deleted_at) as last_batch
        FROM deletion_log 
        GROUP BY table_name
    """)
    
    for row in cursor.fetchall():
        self.logger.info(f"Progress: {row}")

def estimate_completion_time(self, table_name, cutoff_id):
    """Estimate how long deletion will take"""
    cursor = self.db.cursor()
    cursor.execute("""
        SELECT 
            AVG(records_deleted) as avg_per_batch,
            AVG(TIMESTAMPDIFF(SECOND, LAG(deleted_at) OVER (ORDER BY deleted_at), deleted_at)) as avg_seconds_per_batch
        FROM deletion_log 
        WHERE table_name = %s
        AND deleted_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
    """, (table_name,))
    
    result = cursor.fetchone()
    if result and result[0]:
        remaining_records = cutoff_id - self.get_current_progress(table_name)
        estimated_batches = remaining_records / result[0]
        estimated_seconds = estimated_batches * result[1]
        
        return timedelta(seconds=estimated_seconds)
    
    return None
```


## Phase 4: Implementation Timeline

### Week 1: Cutoff Identification
- [ ] Create SQL scripts to identify ID cutoffs for each table
- [ ] Implement safety validation for cutoffs
- [ ] Test cutoff identification on production database (read-only)
- [ ] Document cutoff values and estimated deletion counts

### Week 2: Batch Deletion Framework
- [ ] Implement Python script framework
- [ ] Create deletion logging infrastructure
- [ ] Implement batch deletion logic for readings table
- [ ] Test batch deletion on database copy

### Week 3: Account and Community Deletion
- [ ] Implement complex deletion logic for accounts
- [ ] Handle foreign key dependencies correctly
- [ ] Implement community deletion logic
- [ ] Add comprehensive error handling

### Week 4: Safety and Monitoring
- [ ] Implement all safety features and thresholds
- [ ] Add progress monitoring and reporting
- [ ] Create alerting for failures or anomalies
- [ ] Performance testing and optimization

### Week 5: Production Testing
- [ ] Run dry-run mode on production for full validation
- [ ] Start with small batch sizes on non-critical tables
- [ ] Monitor system performance impact
- [ ] Validate database size reduction

## Advantages of Revised Approach

### Efficiency
- **No Staging Overhead**: No temporary tables consuming disk space
- **Incremental Progress**: Can stop and resume at any point
- **Predictable Performance**: Small batches ensure consistent response times
- **Real-time Monitoring**: Immediate feedback on progress and space savings

### Safety
- **Atomic Operations**: Each batch is a small, reversible transaction
- **Progressive Validation**: Can validate approach on small batches first
- **Granular Control**: Can adjust batch sizes based on system performance
- **Detailed Logging**: Complete audit trail of all deletions

### Scalability
- **Handles Any Size**: Works equally well for millions or billions of rows
- **Resource Friendly**: Low memory footprint, predictable I/O patterns
- **Parallel Capable**: Can run multiple tables simultaneously if needed
- **Resumable**: Can restart from last completed batch after interruption

## Success Metrics

### Primary Goals
- **Database Size Reduction**: Target 30-50% reduction in total database size
- **Zero Data Loss**: No false positive deletions
- **System Stability**: No performance degradation during cleanup
- **Completion Time**: Full cleanup within planned maintenance windows

### Monitoring KPIs
- **Deletion Rate**: Records deleted per minute/hour
- **Space Reclaimed**: GB freed per table
- **System Impact**: CPU/Memory/I/O usage during cleanup
- **Error Rate**: Failed batches or rollbacks

### Validation Checks
- **Referential Integrity**: No orphaned records after cleanup
- **Business Logic**: No deletion of records that should be retained
- **Performance**: Query performance maintained or improved post-cleanup
- **Backup Verification**: Ability to restore if needed

## Risk Mitigation

### Technical Risks
- **Disk Space**: Monitor free space during cleanup (deleted space may not be immediately reclaimed)
- **Performance Impact**: Use small batch sizes and monitor system load
- **Foreign Key Violations**: Strict adherence to deletion order
- **Long-Running Transactions**: Keep batch sizes small to avoid lock timeouts

### Business Risks
- **Data Loss**: Comprehensive dry-run testing and validation
- **System Downtime**: Schedule during maintenance windows
- **Compliance Issues**: Document all deletions for audit purposes
- **Recovery Time**: Maintain recent backups and test restore procedures

This revised approach is specifically designed for the massive scale of the NES database while maintaining the highest safety standards.

