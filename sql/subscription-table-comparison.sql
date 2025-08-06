-- Subscription Invoice Detail Tables Comparison
-- NES Database Cleanup Project
-- Purpose: Determine if subscription_invoice_detail_1 contains unique data not in subscription_invoice_detail

-- =============================================================================
-- EXECUTIVE SUMMARY QUERY
-- Run this first to get a quick overview
-- =============================================================================

SELECT 
    'SUBSCRIPTION INVOICE DETAIL COMPARISON SUMMARY' as analysis_section,
    '' as metric,
    '' as value,
    '' as interpretation

UNION ALL

SELECT 
    'Table Sizes',
    'Main Table Records',
    FORMAT(COALESCE((SELECT COUNT(*) FROM subscription_invoice_detail), 0), 0),
    'subscription_invoice_detail'

UNION ALL

SELECT 
    'Table Sizes',
    'Backup Table Records', 
    FORMAT(COALESCE((SELECT COUNT(*) FROM subscription_invoice_detail_1), 0), 0),
    'subscription_invoice_detail_1'

UNION ALL

SELECT 
    'Data Overlap',
    'Records in BOTH tables',
    FORMAT(COALESCE((
        SELECT COUNT(*)
        FROM subscription_invoice_detail s1
        INNER JOIN subscription_invoice_detail_1 s2 
            ON s1.subscription_invoice_detail_id = s2.subscription_invoice_detail_id
    ), 0), 0),
    'Exact ID matches'

UNION ALL

SELECT 
    'Unique Data',
    'Records ONLY in main table',
    FORMAT(COALESCE((
        SELECT COUNT(*)
        FROM subscription_invoice_detail s1
        LEFT JOIN subscription_invoice_detail_1 s2 
            ON s1.subscription_invoice_detail_id = s2.subscription_invoice_detail_id
        WHERE s2.subscription_invoice_detail_id IS NULL
    ), 0), 0),
    'Main table exclusives'

UNION ALL

SELECT 
    'Unique Data',
    'Records ONLY in backup table',
    FORMAT(COALESCE((
        SELECT COUNT(*)
        FROM subscription_invoice_detail_1 s2
        LEFT JOIN subscription_invoice_detail s1 
            ON s1.subscription_invoice_detail_id = s2.subscription_invoice_detail_id
        WHERE s1.subscription_invoice_detail_id IS NULL
    ), 0), 0),
    'CRITICAL: Backup table exclusives'

UNION ALL

SELECT 
    'Date Analysis',
    'Main table date range',
    CONCAT(
        COALESCE(DATE((SELECT MIN(COALESCE(created_on, updated_on)) FROM subscription_invoice_detail)), 'NULL'),
        ' to ',
        COALESCE(DATE((SELECT MAX(COALESCE(created_on, updated_on)) FROM subscription_invoice_detail)), 'NULL')
    ),
    'Oldest to newest'

UNION ALL

SELECT 
    'Date Analysis',
    'Backup table date range',
    CONCAT(
        COALESCE(DATE((SELECT MIN(COALESCE(created_on, updated_on)) FROM subscription_invoice_detail_1)), 'NULL'),
        ' to ',
        COALESCE(DATE((SELECT MAX(COALESCE(created_on, updated_on)) FROM subscription_invoice_detail_1)), 'NULL')
    ),
    'Oldest to newest'

UNION ALL

SELECT 
    'Safety Assessment',
    'Safe to delete backup table?',
    CASE 
        WHEN (SELECT COUNT(*) FROM subscription_invoice_detail_1 s2
              LEFT JOIN subscription_invoice_detail s1 
                  ON s1.subscription_invoice_detail_id = s2.subscription_invoice_detail_id
              WHERE s1.subscription_invoice_detail_id IS NULL) = 0 
        THEN '✅ YES - No unique data'
        ELSE '❌ NO - Contains unique data'
    END,
    'Based on ID comparison';

-- =============================================================================
-- DETAILED ANALYSIS QUERIES
-- Run these for deeper investigation if needed
-- =============================================================================

-- 1. Detailed overlap analysis by ID
-- Shows exact breakdown of data relationships
SELECT 
    'Data Relationship Analysis' as analysis_type,
    relationship_type,
    record_count,
    percentage_of_backup_table,
    interpretation
FROM (
    SELECT 
        'Records in BOTH tables (same ID)' as relationship_type,
        COUNT(*) as record_count,
        ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM subscription_invoice_detail_1), 2) as percentage_of_backup_table,
        'Duplicate data - safe to delete from backup' as interpretation
    FROM subscription_invoice_detail s1
    INNER JOIN subscription_invoice_detail_1 s2 
        ON s1.subscription_invoice_detail_id = s2.subscription_invoice_detail_id
    
    UNION ALL
    
    SELECT 
        'Records ONLY in backup table' as relationship_type,
        COUNT(*) as record_count,
        ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM subscription_invoice_detail_1), 2) as percentage_of_backup_table,
        'UNIQUE DATA - must preserve or migrate' as interpretation
    FROM subscription_invoice_detail_1 s2
    LEFT JOIN subscription_invoice_detail s1 
        ON s1.subscription_invoice_detail_id = s2.subscription_invoice_detail_id
    WHERE s1.subscription_invoice_detail_id IS NULL
    
    UNION ALL
    
    SELECT 
        'Records ONLY in main table' as relationship_type,
        COUNT(*) as record_count,
        NULL as percentage_of_backup_table,
        'Newer data not in backup' as interpretation
    FROM subscription_invoice_detail s1
    LEFT JOIN subscription_invoice_detail_1 s2 
        ON s1.subscription_invoice_detail_id = s2.subscription_invoice_detail_id
    WHERE s2.subscription_invoice_detail_id IS NULL
) as analysis
ORDER BY record_count DESC;

-- 2. Content comparison for overlapping records
-- Checks if records with same ID have same content
SELECT 
    'Content Integrity Check' as check_type,
    content_status,
    record_count,
    ROUND(record_count * 100.0 / total_overlapping, 2) as percentage,
    recommendation
FROM (
    SELECT 
        'Identical content' as content_status,
        COUNT(*) as record_count,
        (SELECT COUNT(*) FROM subscription_invoice_detail s1
         INNER JOIN subscription_invoice_detail_1 s2 
             ON s1.subscription_invoice_detail_id = s2.subscription_invoice_detail_id) as total_overlapping,
        'Safe to delete - exact duplicates' as recommendation
    FROM subscription_invoice_detail s1
    INNER JOIN subscription_invoice_detail_1 s2 
        ON s1.subscription_invoice_detail_id = s2.subscription_invoice_detail_id
    WHERE s1.subscription_id = s2.subscription_id
        AND s1.invoice_detail_id = s2.invoice_detail_id
        AND COALESCE(s1.amount, 0) = COALESCE(s2.amount, 0)
        AND COALESCE(s1.created_on, '1900-01-01') = COALESCE(s2.created_on, '1900-01-01')
    
    UNION ALL
    
    SELECT 
        'Different content' as content_status,
        COUNT(*) as record_count,
        (SELECT COUNT(*) FROM subscription_invoice_detail s1
         INNER JOIN subscription_invoice_detail_1 s2 
             ON s1.subscription_invoice_detail_id = s2.subscription_invoice_detail_id) as total_overlapping,
        'INVESTIGATE - same ID, different data' as recommendation
    FROM subscription_invoice_detail s1
    INNER JOIN subscription_invoice_detail_1 s2 
        ON s1.subscription_invoice_detail_id = s2.subscription_invoice_detail_id
    WHERE NOT (s1.subscription_id = s2.subscription_id
        AND s1.invoice_detail_id = s2.invoice_detail_id
        AND COALESCE(s1.amount, 0) = COALESCE(s2.amount, 0)
        AND COALESCE(s1.created_on, '1900-01-01') = COALESCE(s2.created_on, '1900-01-01'))
) as content_analysis;

-- 3. Unique records in backup table (CRITICAL ANALYSIS)
-- Shows details of records that exist ONLY in subscription_invoice_detail_1
SELECT 
    'UNIQUE RECORDS IN BACKUP TABLE' as analysis_section,
    s2.subscription_invoice_detail_id,
    s2.subscription_id,
    s2.invoice_detail_id,
    s2.amount,
    s2.created_on,
    s2.updated_on,
    'CRITICAL: This data would be lost if backup table is deleted' as warning
FROM subscription_invoice_detail_1 s2
LEFT JOIN subscription_invoice_detail s1 
    ON s1.subscription_invoice_detail_id = s2.subscription_invoice_detail_id
WHERE s1.subscription_invoice_detail_id IS NULL
ORDER BY s2.subscription_invoice_detail_id
LIMIT 20;  -- Show first 20 unique records for review

-- 4. Date range analysis for unique records
-- Understand the time period of unique data in backup table
SELECT 
    'Unique Records Date Analysis' as analysis_type,
    YEAR(COALESCE(created_on, updated_on)) as year,
    COUNT(*) as unique_records_count,
    MIN(COALESCE(created_on, updated_on)) as earliest_date,
    MAX(COALESCE(created_on, updated_on)) as latest_date,
    'Records only in backup table' as note
FROM subscription_invoice_detail_1 s2
LEFT JOIN subscription_invoice_detail s1 
    ON s1.subscription_invoice_detail_id = s2.subscription_invoice_detail_id
WHERE s1.subscription_invoice_detail_id IS NULL
GROUP BY YEAR(COALESCE(created_on, updated_on))
ORDER BY year DESC;

-- 5. Business impact assessment of unique records
-- Analyze the financial impact of unique records in backup table
SELECT 
    'Business Impact of Unique Records' as impact_analysis,
    COUNT(*) as unique_record_count,
    COALESCE(SUM(amount), 0) as total_amount_at_risk,
    COALESCE(AVG(amount), 0) as average_amount,
    COALESCE(MAX(amount), 0) as max_amount,
    CASE 
        WHEN COUNT(*) = 0 THEN 'No financial impact - safe to delete'
        WHEN COALESCE(SUM(amount), 0) > 100000 THEN 'HIGH IMPACT - significant financial data'
        WHEN COALESCE(SUM(amount), 0) > 10000 THEN 'MEDIUM IMPACT - moderate financial data'
        ELSE 'LOW IMPACT - minimal financial data'
    END as risk_assessment
FROM subscription_invoice_detail_1 s2
LEFT JOIN subscription_invoice_detail s1 
    ON s1.subscription_invoice_detail_id = s2.subscription_invoice_detail_id
WHERE s1.subscription_invoice_detail_id IS NULL;

-- =============================================================================
-- DECISION SUPPORT QUERY
-- =============================================================================

-- 6. Final recommendation query
-- Provides clear guidance on whether backup table can be safely deleted
SELECT 
    'FINAL RECOMMENDATION' as decision_section,
    recommendation,
    justification,
    next_steps
FROM (
    SELECT 
        CASE 
            WHEN unique_count = 0 THEN '✅ SAFE TO DELETE subscription_invoice_detail_1'
            WHEN unique_count > 0 AND total_amount > 50000 THEN '❌ DO NOT DELETE - High value unique data'
            WHEN unique_count > 0 AND total_amount > 1000 THEN '⚠️ INVESTIGATE FURTHER - Moderate value unique data'
            WHEN unique_count > 0 THEN '⚠️ MIGRATE FIRST - Low value but unique data exists'
            ELSE '❓ UNABLE TO DETERMINE - Manual review required'
        END as recommendation,
        
        CONCAT(
            'Found ', unique_count, ' unique records in backup table. ',
            'Total financial value: $', COALESCE(total_amount, 0), '. ',
            CASE 
                WHEN unique_count = 0 THEN 'All data is duplicated in main table.'
                ELSE 'Backup table contains data not in main table.'
            END
        ) as justification,
        
        CASE 
            WHEN unique_count = 0 THEN 'Execute: DROP TABLE subscription_invoice_detail_1;'
            WHEN unique_count > 0 THEN 'First migrate unique records, then investigate why they exist separately'
            ELSE 'Manual investigation required'
        END as next_steps
        
    FROM (
        SELECT 
            COUNT(*) as unique_count,
            COALESCE(SUM(amount), 0) as total_amount
        FROM subscription_invoice_detail_1 s2
        LEFT JOIN subscription_invoice_detail s1 
            ON s1.subscription_invoice_detail_id = s2.subscription_invoice_detail_id
        WHERE s1.subscription_invoice_detail_id IS NULL
    ) as unique_analysis
) as final_decision;

-- =============================================================================
-- STORAGE IMPACT CALCULATION
-- =============================================================================

-- 7. Storage savings calculation
-- Estimate space savings from deleting subscription_invoice_detail_1
SELECT 
    'Storage Impact Analysis' as analysis_type,
    FORMAT(table_rows, 0) as total_records,
    CONCAT(ROUND(data_mb, 2), ' MB') as data_size,
    CONCAT(ROUND(index_mb, 2), ' MB') as index_size,
    CONCAT(ROUND(total_mb, 2), ' MB') as total_size,
    CASE 
        WHEN (SELECT COUNT(*) FROM subscription_invoice_detail_1 s2
              LEFT JOIN subscription_invoice_detail s1 
                  ON s1.subscription_invoice_detail_id = s2.subscription_invoice_detail_id
              WHERE s1.subscription_invoice_detail_id IS NULL) = 0
        THEN CONCAT('✅ FULL SAVINGS: ', ROUND(total_mb, 2), ' MB can be reclaimed')
        ELSE '⚠️ PARTIAL SAVINGS: Unique data must be preserved'
    END as savings_potential
FROM (
    SELECT 
        table_rows,
        ROUND((data_length) / 1024 / 1024, 2) as data_mb,
        ROUND((index_length) / 1024 / 1024, 2) as index_mb,
        ROUND((data_length + index_length) / 1024 / 1024, 2) as total_mb
    FROM information_schema.tables 
    WHERE table_schema = 'nes' 
    AND table_name = 'subscription_invoice_detail_1'
) as size_info;

