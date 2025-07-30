# Database Data Deletion Plan

## Overview

This document outlines a comprehensive plan for implementing periodic data deletion in the NES database to reduce database size while maintaining data integrity and ensuring zero false positives.

## Objectives

The primary goal is to safely remove:
- Resident account information for accounts last billed more than 7 years ago
- Communities closed or "zy"ed more than 7 years ago (excluding those in legal hold)
- Readings not used for billing (not in sm_usage table) older than 2 years

## Critical Requirements

- **Zero False Positives**: We cannot delete data that should be retained
- **False Negatives Acceptable**: Missing some deletable data is acceptable as long as it doesn't cause significant database growth
- **Referential Integrity**: Must respect foreign key constraints and application-level relationships
- **Periodic Execution**: Script must be designed for regular automated execution

## Database Context

The NES database uses an Entity-Attribute-Value (EAV) model with:
- Some enforced foreign key constraints
- Many application-level relationships not enforced by database constraints
- Polymorphic relationships using object_id and object_type_id patterns



## Phase 1: Discovery and Safety

This initial phase is crucial for preventing accidental data loss and understanding the complex relationships in the EAV-model database.

### 1.1 Full Database Backup

**Action:** Before any analysis or scripting that involves writing to the database, perform a complete, verified backup of the `nes` database.

**Rationale:** This is a non-negotiable safety net. Any unexpected issues during the deletion process can be reverted.

**Implementation:**
```bash
mysqldump -u root -p --single-transaction --routines --triggers nes > nes_backup_$(date +%Y%m%d_%H%M%S).sql
```

### 1.2 Foreign Key Inventory

**Action:** Systematically query the `INFORMATION_SCHEMA` to map out all existing foreign key constraints.

```sql
SELECT 
    TABLE_NAME,
    COLUMN_NAME,
    CONSTRAINT_NAME,
    REFERENCED_TABLE_NAME,
    REFERENCED_COLUMN_NAME
FROM
    INFORMATION_SCHEMA.KEY_COLUMN_USAGE
WHERE
    REFERENCED_TABLE_SCHEMA = 'nes'
ORDER BY TABLE_NAME, COLUMN_NAME;
```

**Rationale:** Although the database is described as an EAV model, the schema shows numerous foreign keys (e.g., `FK_batch_detail_1`, `FK_invoice_1`). A complete map is essential for determining the correct order of deletion to avoid referential integrity errors.

### 1.3 Implicit Relationship Mapping

**Action:** Analyze table structures and column names to identify likely relationships that are not enforced by foreign keys.

**Key Relationships Identified:**
- `sm_bill` is linked to `tenant` via `tenant_id` and `logical_unit_id`
- `invoice` is linked to a `contact` via `object_id` where `object_type_id` = 1
- `address` and `phone` are polymorphic, linking to various objects via `object_id` and `object_type_id`
- `note` table links to various objects using the same polymorphic pattern

**Rationale:** In an EAV model, the application logic enforces referential integrity. We must replicate this understanding to ensure that deleting a "parent" record (like an account) also removes all its "child" data across various tables.


## Phase 2: Staging and Conservative Identification

This phase focuses on identifying and isolating the primary keys of records to be deleted using a conservative approach that prioritizes safety over completeness.

### 2.1 Create Staging Tables

**Action:** Create temporary tables to hold the IDs of records marked for deletion.

```sql
CREATE TABLE staging_deletion_accounts (
    contact_id INT PRIMARY KEY,
    last_activity_date DATETIME,
    reason VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE staging_deletion_communities (
    contact_id INT PRIMARY KEY,
    community_name VARCHAR(255),
    closed_date DATETIME,
    reason VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE staging_deletion_readings (
    reading_id INT PRIMARY KEY,
    date_imported DATETIME,
    logical_unit_id INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 2.2 Identify Stale Resident Accounts (> 7 years) - Conservative Logic

**Challenge:** The term "last billed" can be ambiguous. A resident might have an old bill but recent account activity.

**Conservative Approach:** Identify accounts where the most recent timestamp of any associated activity is older than 7 years, including move-out date, last invoice, last payment, and last note.

```sql
INSERT INTO staging_deletion_accounts (contact_id, last_activity_date, reason)
SELECT 
    contact_id,
    last_activity_date,
    'No activity for > 7 years, definitive move-out date exists'
FROM (
    SELECT 
        t.contact_id,
        -- Find the most recent date across all relevant activities for a tenant
        GREATEST(
            IFNULL(MAX(t.to_date), '1970-01-01'), -- Last move-out date
            IFNULL(MAX(je.journal_entry_date), '1970-01-01'), -- Last invoice/payment date
            IFNULL(MAX(n.last_updated_on), '1970-01-01') -- Last note update
        ) AS last_activity_date
    FROM tenant t
    -- Join to get invoice/payment dates
    LEFT JOIN invoice i ON t.contact_id = i.object_id AND i.object_type_id = 1
    LEFT JOIN journal_entry je ON i.journal_entry_id = je.journal_entry_id
    -- Join to get note dates
    LEFT JOIN note n ON t.contact_id = n.object_id AND n.object_type_id = 94
    WHERE
        -- Crucially, only consider tenants who have a definitive move-out date in the past
        t.to_date IS NOT NULL 
        AND t.to_date != '0000-00-00 00:00:00'
        AND t.to_date < NOW()
    GROUP BY t.contact_id
) AS last_activities
WHERE last_activity_date < DATE_SUB(NOW(), INTERVAL 7 YEAR);
```

**Safety Rationale:** This query anchors on an explicit `to_date` from the `tenant` table, ensuring we only consider former tenants. It cross-references with other activity timestamps to ensure the account is truly dormant.

### 2.3 Identify Closed Communities (> 7 years) - Conservative Logic

**Challenge:** "Closed" or "zy'ed" needs a concrete definition and verification of no recent activity.

**Conservative Approach:** Only target communities that are explicitly marked as 'Closed' or 'zy' AND have no active tenants or recent batches associated with them.

```sql
INSERT INTO staging_deletion_communities (contact_id, community_name, closed_date, reason)
SELECT 
    c.contact_id,
    c.contact_name,
    c.last_updated_on,
    'Marked as closed/zy with no recent activity or legal holds'
FROM contact c
-- Ensure it's marked as a closed type
JOIN contact_type ct ON c.contact_type_id = ct.contact_type_id 
    AND ct.contact_type IN ('Closed', 'zy')
-- Ensure there are no active tenants
LEFT JOIN tenant t ON c.contact_id = t.object_id 
    AND t.object_type_id = 49 
    AND (t.to_date IS NULL OR t.to_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
-- Ensure there are no recent batches
LEFT JOIN contact_batch cb ON c.contact_id = cb.contact_id
LEFT JOIN batch b ON cb.batch_id = b.batch_id 
    AND b.created_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR)
WHERE
    -- The community itself hasn't been touched in 7 years
    c.last_updated_on < DATE_SUB(NOW(), INTERVAL 7 YEAR)
    -- Explicitly check that our LEFT JOINs found no conflicting data
    AND t.tenant_id IS NULL
    AND b.batch_id IS NULL
    -- Add the legal hold check
    AND NOT EXISTS (
        SELECT 1 FROM community_logical_unit_attribute
        WHERE logical_unit_id = c.object_id
        AND logical_unit_attribute_type_id = (
            SELECT logical_unit_attribute_type_id 
            FROM community_logical_unit_attribute_type 
            WHERE logical_unit_attribute_type = 'Legal Hold'
        )
        AND val_integer = 1
    );
```

**Safety Rationale:** This query actively looks for reasons not to delete a community (active tenants, recent batches, legal holds). Only if no such reasons are found is the community staged for deletion.

### 2.4 Identify Old Non-Billing Readings (> 2 years) - Conservative Logic

**Challenge:** Ensure readings aren't associated with any other processes we might not be aware of.

**Conservative Approach:** The logic is already quite safe - readings not in `sm_usage` are definitionally non-billing reads.

```sql
INSERT INTO staging_deletion_readings (reading_id, date_imported, logical_unit_id)
SELECT 
    r.reading_id,
    r.date_imported,
    r.logical_unit_id
FROM reading r
LEFT JOIN sm_usage su ON r.guid = su.guid
WHERE 
    su.sm_usage_id IS NULL 
    AND r.date_imported < DATE_SUB(NOW(), INTERVAL 2 YEAR);
```

**Safety Rationale:** The `sm_usage` table is the single source of truth for billing-related usage. If a reading's `guid` isn't there, it wasn't used for billing.


## Phase 3: Execution of Deletion

With target IDs staged, we can now execute DELETE statements. The order is critical and must follow the dependency mapping from Phase 1 (children before parents).

### 3.1 Deletion Order Strategy

**Approach:** Top-Down Identification, Bottom-Up Deletion
- We identified parent objects (accounts, communities) first
- Now we must delete their dependencies (child records) before deleting the parent objects themselves

### 3.2 Deletion Order for Stale Accounts

Based on foreign key analysis, the deletion order should be:

1. **Email attachments and emails**
   ```sql
   DELETE ea FROM email_attachment ea
   JOIN email e ON ea.email_id = e.email_id
   JOIN staging_deletion_accounts sda ON e.object_id = sda.contact_id
   WHERE e.object_type_id = 1;
   
   DELETE e FROM email e
   JOIN staging_deletion_accounts sda ON e.object_id = sda.contact_id
   WHERE e.object_type_id = 1;
   ```

2. **Tender details and tenders**
   ```sql
   DELETE td FROM tender_detail td
   JOIN tender t ON td.tender_id = t.tender_id
   JOIN staging_deletion_accounts sda ON t.object_id = sda.contact_id
   WHERE t.object_type_id = 1;
   
   DELETE t FROM tender t
   JOIN staging_deletion_accounts sda ON t.object_id = sda.contact_id
   WHERE t.object_type_id = 1;
   ```

3. **Invoice details and invoices**
   ```sql
   DELETE id FROM invoice_detail id
   JOIN invoice i ON id.invoice_id = i.invoice_id
   JOIN staging_deletion_accounts sda ON i.object_id = sda.contact_id
   WHERE i.object_type_id = 1;
   
   DELETE i FROM invoice i
   JOIN staging_deletion_accounts sda ON i.object_id = sda.contact_id
   WHERE i.object_type_id = 1;
   ```

4. **Journal entries**
   ```sql
   DELETE je FROM journal_entry je
   JOIN staging_deletion_accounts sda ON je.object_id = sda.contact_id
   WHERE je.object_type_id = 1;
   ```

5. **SM bill notes and bills**
   ```sql
   DELETE sbn FROM sm_bill_note sbn
   JOIN sm_bill sb ON sbn.sm_bill_id = sb.sm_bill_id
   JOIN tenant t ON sb.tenant_id = t.tenant_id
   JOIN staging_deletion_accounts sda ON t.contact_id = sda.contact_id;
   
   DELETE sb FROM sm_bill sb
   JOIN tenant t ON sb.tenant_id = t.tenant_id
   JOIN staging_deletion_accounts sda ON t.contact_id = sda.contact_id;
   ```

6. **Polymorphic relationships (phone, address, note)**
   ```sql
   DELETE p FROM phone p
   JOIN staging_deletion_accounts sda ON p.object_id = sda.contact_id
   WHERE p.object_type_id = (SELECT object_type_id FROM object WHERE object_name = 'dstContact');
   
   DELETE a FROM address a
   JOIN staging_deletion_accounts sda ON a.object_id = sda.contact_id
   WHERE a.object_type_id = (SELECT object_type_id FROM object WHERE object_name = 'dstContact');
   
   DELETE n FROM note n
   JOIN staging_deletion_accounts sda ON n.object_id = sda.contact_id
   WHERE n.object_type_id = (SELECT object_type_id FROM object WHERE object_name = 'dstContact');
   ```

7. **Tenant records**
   ```sql
   DELETE t FROM tenant t
   JOIN staging_deletion_accounts sda ON t.contact_id = sda.contact_id;
   ```

8. **Contact records (final step)**
   ```sql
   DELETE c FROM contact c
   JOIN staging_deletion_accounts sda ON c.contact_id = sda.contact_id;
   ```

### 3.3 Deletion Order for Closed Communities

Similar approach for communities, but must also handle:
- Community logical unit attributes
- Associated logical units and their hierarchies
- Any linked services or meters

### 3.4 Deletion for Old Readings

This is the most straightforward deletion:

```sql
DELETE r FROM reading r
JOIN staging_deletion_readings sdr ON r.reading_id = sdr.reading_id;
```


## Phase 4: Scripting and Automation

The final step is to combine all logic into a robust, repeatable script with enhanced safeguards.

### 4.1 Technology Choice

**Recommendation:** Python with `mysql-connector-python` or `PyMySQL`
- Superior error handling compared to plain SQL scripts
- Comprehensive logging capabilities
- Configuration management
- Transaction control
- Dry-run capabilities

### 4.2 Script Structure

#### Configuration Management
- Store database credentials in separate configuration file (`config.ini` or `.env`)
- Configurable date thresholds (7 years, 2 years)
- Logging levels and output destinations
- Safety thresholds for maximum deletions

#### Comprehensive Logging
- Script start and end times
- Number of records identified in each staging table
- Number of records deleted from each table
- Any errors encountered with full stack traces
- Performance metrics (execution time per phase)

#### Transaction Control
- Wrap each logical block of deletions in database transactions
- If any part of a block fails, roll back the entire transaction for that entity
- Prevents partial deletions that could leave data in inconsistent state

#### Safety Features

**Mandatory Dry-Run Mode:**
```python
# Script defaults to dry-run mode
# Explicit flag required for actual execution
if not args.execute:
    logger.info("DRY RUN MODE - No data will be deleted")
    # Perform all identification and logging without DELETE statements
```

**Record Counting and Thresholds:**
```python
# Safety threshold: abort if deletion count exceeds percentage of table
def check_deletion_threshold(table_name, deletion_count, total_count, threshold_pct=10):
    if deletion_count > (total_count * threshold_pct / 100):
        raise SafetyThresholdExceeded(
            f"Deletion count {deletion_count} exceeds {threshold_pct}% of {table_name}"
        )
```

**Archiving Step (Recommended):**
- Before DELETE, INSERT rows into corresponding archive tables
- Provides application-level undo capability
- Much faster to restore than full database backup
- Archive tables can be periodically cleaned or moved to cold storage

### 4.3 Script Modules

#### Core Functions
```python
def identify_stale_accounts(cursor, cutoff_date):
    """Populate staging_deletion_accounts table"""
    
def identify_closed_communities(cursor, cutoff_date):
    """Populate staging_deletion_communities table"""
    
def identify_old_readings(cursor, cutoff_date):
    """Populate staging_deletion_readings table"""
    
def delete_staged_accounts(cursor, dry_run=True):
    """Execute deletion sequence for staged accounts"""
    
def delete_staged_communities(cursor, dry_run=True):
    """Execute deletion sequence for staged communities"""
    
def delete_staged_readings(cursor, dry_run=True):
    """Execute deletion sequence for staged readings"""
```

#### Safety and Monitoring
```python
def create_backup(config):
    """Create database backup before any operations"""
    
def validate_foreign_keys(cursor):
    """Verify foreign key constraints are intact"""
    
def generate_deletion_report(cursor):
    """Generate summary report of what will be/was deleted"""
```

### 4.4 Scheduling and Automation

#### Cron Job Setup
```bash
# Run at 3 AM every Sunday
0 3 * * 0 /usr/bin/python3 /path/to/deletion_script.py --execute >> /var/log/data_deletion.log 2>&1

# Monthly dry-run for monitoring
0 2 1 * * /usr/bin/python3 /path/to/deletion_script.py --dry-run >> /var/log/data_deletion_dryrun.log 2>&1
```

#### Monitoring and Alerting
- Log analysis for errors or unusual deletion volumes
- Email notifications for script completion/failure
- Database size monitoring to track effectiveness
- Regular validation of staging table contents

### 4.5 Testing Strategy

#### Development Testing
1. **Unit Tests:** Test each identification function with known test data
2. **Integration Tests:** Test full workflow on copy of production database
3. **Safety Tests:** Verify safety thresholds and dry-run mode work correctly

#### Production Validation
1. **Initial Dry Runs:** Run in dry-run mode for several cycles to validate identification logic
2. **Small Batch Testing:** Start with very conservative thresholds
3. **Gradual Rollout:** Increase deletion scope gradually as confidence builds

## Implementation Timeline

1. **Week 1:** Implement Phase 1 (Discovery and Safety)
2. **Week 2:** Implement Phase 2 (Staging and Identification)
3. **Week 3:** Implement Phase 3 (Execution Logic)
4. **Week 4:** Implement Phase 4 (Scripting and Automation)
5. **Week 5:** Testing and Validation
6. **Week 6:** Production Deployment and Monitoring

## Success Metrics

- **Database Size Reduction:** Measurable decrease in database size
- **Zero Data Loss:** No false positive deletions
- **Performance Impact:** Minimal impact on application performance during execution
- **Reliability:** Consistent successful execution over time
- **Maintainability:** Clear logs and easy troubleshooting when issues arise

