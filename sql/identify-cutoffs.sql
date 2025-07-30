-- NES Database Cleanup: ID Cutoff Identification
-- This script identifies the autoincrement ID cutoffs for data deletion
-- Run in DRY-RUN mode first to validate cutoffs before any deletion

-- =============================================================================
-- READINGS TABLE CUTOFF (2 years)
-- =============================================================================

-- Find the highest reading_id for readings older than 2 years
-- These are candidates for deletion if not used for billing
SELECT 
    'READINGS_CUTOFF' as cutoff_type,
    COALESCE(MAX(reading_id), 0) as cutoff_id,
    DATE_SUB(NOW(), INTERVAL 2 YEAR) as cutoff_date,
    COUNT(*) as total_candidates
FROM reading 
WHERE date_imported < DATE_SUB(NOW(), INTERVAL 2 YEAR);

-- Validate: Count how many of these are NOT used for billing
SELECT 
    'READINGS_DELETABLE' as validation_type,
    COUNT(*) as deletable_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM reading), 2) as percentage_of_total
FROM reading r
LEFT JOIN sm_usage su ON r.guid = su.guid
WHERE r.date_imported < DATE_SUB(NOW(), INTERVAL 2 YEAR)
AND su.sm_usage_id IS NULL;

-- Safety check: Ensure no recent readings would be deleted
SELECT 
    'READINGS_SAFETY_CHECK' as check_type,
    COUNT(*) as recent_readings_above_cutoff,
    CASE 
        WHEN COUNT(*) = 0 THEN 'SAFE' 
        ELSE 'DANGER - RECENT DATA ABOVE CUTOFF' 
    END as safety_status
FROM reading r
LEFT JOIN sm_usage su ON r.guid = su.guid
WHERE r.reading_id <= (
    SELECT COALESCE(MAX(reading_id), 0) 
    FROM reading 
    WHERE date_imported < DATE_SUB(NOW(), INTERVAL 2 YEAR)
)
AND r.date_imported >= DATE_SUB(NOW(), INTERVAL 2 YEAR)
AND su.sm_usage_id IS NULL;

-- =============================================================================
-- ACCOUNT CUTOFF (7 years - Conservative Approach)
-- =============================================================================

-- Find accounts that are truly inactive for 7+ years
-- This is a conservative approach that checks multiple activity indicators
SELECT 
    'ACCOUNT_CUTOFF' as cutoff_type,
    COALESCE(MAX(contact_id), 0) as cutoff_id,
    DATE_SUB(NOW(), INTERVAL 7 YEAR) as cutoff_date,
    COUNT(*) as total_candidates
FROM (
    SELECT DISTINCT c.contact_id
    FROM contact c
    JOIN tenant t ON c.contact_id = t.contact_id
    WHERE 
        -- Must have a definitive move-out date
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
        
        -- No recent journal entries (payments, charges)
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
) inactive_accounts;

-- Validate account cutoff safety
SELECT 
    'ACCOUNT_SAFETY_CHECK' as check_type,
    COUNT(*) as accounts_with_recent_activity_above_cutoff,
    CASE 
        WHEN COUNT(*) = 0 THEN 'SAFE' 
        ELSE 'DANGER - RECENT ACTIVITY ABOVE CUTOFF' 
    END as safety_status
FROM contact c
WHERE c.contact_id <= (
    -- Get the cutoff from the previous query
    SELECT COALESCE(MAX(contact_id), 0)
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
)
AND (
    -- Check for any recent activity
    EXISTS (SELECT 1 FROM invoice i WHERE i.object_id = c.contact_id AND i.object_type_id = 1 AND i.invoice_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
    OR EXISTS (SELECT 1 FROM journal_entry je WHERE je.object_id = c.contact_id AND je.object_type_id = 1 AND je.journal_entry_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
    OR EXISTS (SELECT 1 FROM note n WHERE n.object_id = c.contact_id AND n.object_type_id = 94 AND n.last_updated_on >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
    OR EXISTS (SELECT 1 FROM email e WHERE e.object_id = c.contact_id AND e.object_type_id = 1 AND e.email_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
);

-- =============================================================================
-- COMMUNITY CUTOFF (7 years - Closed/ZY communities)
-- =============================================================================

-- Find communities with no recent activity (flexible contact type matching)
-- NOTE: This query needs to be customized based on actual contact types in your database
-- Run check-contact-types.sql first to identify the correct contact types for closed communities
SELECT 
    'COMMUNITY_CUTOFF' as cutoff_type,
    COALESCE(MAX(contact_id), 0) as cutoff_id,
    DATE_SUB(NOW(), INTERVAL 7 YEAR) as cutoff_date,
    COUNT(*) as total_candidates
FROM contact c
JOIN contact_type ct ON c.contact_type_id = ct.contact_type_id
WHERE 
    -- CUSTOMIZE THIS: Replace with actual contact types for closed/inactive communities
    -- Examples of what to look for: 'Closed', 'Inactive', 'Terminated', 'Cancelled', etc.
    (
        LOWER(ct.contact_type) LIKE '%clos%'
        OR LOWER(ct.contact_type) LIKE '%inact%'
        OR LOWER(ct.contact_type) LIKE '%term%'
        OR LOWER(ct.contact_type) LIKE '%cancel%'
        -- Add more patterns based on your actual contact types
    )
    
    -- Community itself hasn't been updated in 7 years
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
    
    -- No legal hold (assuming object_id links to logical_unit_id)
    AND NOT EXISTS (
        SELECT 1 FROM community_logical_unit_attribute clua
        JOIN community_logical_unit_attribute_type cluat 
            ON clua.logical_unit_attribute_type_id = cluat.logical_unit_attribute_type_id
        WHERE clua.logical_unit_id = c.object_id
        AND cluat.logical_unit_attribute_type = 'Legal Hold'
        AND clua.val_integer = 1
    );

-- =============================================================================
-- SUMMARY REPORT
-- =============================================================================

-- Generate a summary of all cutoffs for review
SELECT 
    'SUMMARY' as report_type,
    'Use these cutoff values for batch deletion' as instructions;

-- Reading cutoff summary
SELECT 
    'reading' as table_name,
    (SELECT COALESCE(MAX(reading_id), 0) FROM reading WHERE date_imported < DATE_SUB(NOW(), INTERVAL 2 YEAR)) as cutoff_id,
    (SELECT COUNT(*) FROM reading r LEFT JOIN sm_usage su ON r.guid = su.guid 
     WHERE r.date_imported < DATE_SUB(NOW(), INTERVAL 2 YEAR) AND su.sm_usage_id IS NULL) as estimated_deletions,
    ROUND((SELECT COUNT(*) FROM reading r LEFT JOIN sm_usage su ON r.guid = su.guid 
           WHERE r.date_imported < DATE_SUB(NOW(), INTERVAL 2 YEAR) AND su.sm_usage_id IS NULL) * 100.0 / 
          (SELECT COUNT(*) FROM reading), 2) as percentage_of_table;

-- Account cutoff summary  
SELECT 
    'contact_accounts' as table_name,
    (SELECT COALESCE(MAX(contact_id), 0) FROM (
        SELECT DISTINCT c.contact_id FROM contact c JOIN tenant t ON c.contact_id = t.contact_id
        WHERE t.to_date IS NOT NULL AND t.to_date != '0000-00-00 00:00:00' AND t.to_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
        AND NOT EXISTS (SELECT 1 FROM invoice i WHERE i.object_id = c.contact_id AND i.object_type_id = 1 AND i.invoice_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
        AND NOT EXISTS (SELECT 1 FROM journal_entry je WHERE je.object_id = c.contact_id AND je.object_type_id = 1 AND je.journal_entry_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
        AND NOT EXISTS (SELECT 1 FROM note n WHERE n.object_id = c.contact_id AND n.object_type_id = 94 AND n.last_updated_on >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
        AND NOT EXISTS (SELECT 1 FROM email e WHERE e.object_id = c.contact_id AND e.object_type_id = 1 AND e.email_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
    ) inactive_accounts) as cutoff_id,
    (SELECT COUNT(*) FROM (
        SELECT DISTINCT c.contact_id FROM contact c JOIN tenant t ON c.contact_id = t.contact_id
        WHERE t.to_date IS NOT NULL AND t.to_date != '0000-00-00 00:00:00' AND t.to_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
        AND NOT EXISTS (SELECT 1 FROM invoice i WHERE i.object_id = c.contact_id AND i.object_type_id = 1 AND i.invoice_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
        AND NOT EXISTS (SELECT 1 FROM journal_entry je WHERE je.object_id = c.contact_id AND je.object_type_id = 1 AND je.journal_entry_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
        AND NOT EXISTS (SELECT 1 FROM note n WHERE n.object_id = c.contact_id AND n.object_type_id = 94 AND n.last_updated_on >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
        AND NOT EXISTS (SELECT 1 FROM email e WHERE e.object_id = c.contact_id AND e.object_type_id = 1 AND e.email_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
    ) inactive_accounts) as estimated_deletions,
    'TBD' as percentage_of_table;

-- Community cutoff summary
SELECT 
    'contact_communities' as table_name,
    (SELECT COALESCE(MAX(contact_id), 0) FROM contact c JOIN contact_type ct ON c.contact_type_id = ct.contact_type_id
     WHERE (LOWER(ct.contact_type) LIKE '%clos%' OR LOWER(ct.contact_type) LIKE '%inact%' OR LOWER(ct.contact_type) LIKE '%term%' OR LOWER(ct.contact_type) LIKE '%cancel%')
     AND c.last_updated_on < DATE_SUB(NOW(), INTERVAL 7 YEAR)
     AND NOT EXISTS (SELECT 1 FROM tenant t WHERE t.object_id = c.contact_id AND t.object_type_id = 49 AND (t.to_date IS NULL OR t.to_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR)))
     AND NOT EXISTS (SELECT 1 FROM contact_batch cb JOIN batch b ON cb.batch_id = b.batch_id WHERE cb.contact_id = c.contact_id AND b.created_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
     AND NOT EXISTS (SELECT 1 FROM community_logical_unit_attribute clua JOIN community_logical_unit_attribute_type cluat ON clua.logical_unit_attribute_type_id = cluat.logical_unit_attribute_type_id WHERE clua.logical_unit_id = c.object_id AND cluat.logical_unit_attribute_type = 'Legal Hold' AND clua.val_integer = 1)
    ) as cutoff_id,
    (SELECT COUNT(*) FROM contact c JOIN contact_type ct ON c.contact_type_id = ct.contact_type_id
     WHERE (LOWER(ct.contact_type) LIKE '%clos%' OR LOWER(ct.contact_type) LIKE '%inact%' OR LOWER(ct.contact_type) LIKE '%term%' OR LOWER(ct.contact_type) LIKE '%cancel%')
     AND c.last_updated_on < DATE_SUB(NOW(), INTERVAL 7 YEAR)
     AND NOT EXISTS (SELECT 1 FROM tenant t WHERE t.object_id = c.contact_id AND t.object_type_id = 49 AND (t.to_date IS NULL OR t.to_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR)))
     AND NOT EXISTS (SELECT 1 FROM contact_batch cb JOIN batch b ON cb.batch_id = b.batch_id WHERE cb.contact_id = c.contact_id AND b.created_date >= DATE_SUB(NOW(), INTERVAL 7 YEAR))
     AND NOT EXISTS (SELECT 1 FROM community_logical_unit_attribute clua JOIN community_logical_unit_attribute_type cluat ON clua.logical_unit_attribute_type_id = cluat.logical_unit_attribute_type_id WHERE clua.logical_unit_id = c.object_id AND cluat.logical_unit_attribute_type = 'Legal Hold' AND clua.val_integer = 1)
    ) as estimated_deletions,
    'TBD' as percentage_of_table;

