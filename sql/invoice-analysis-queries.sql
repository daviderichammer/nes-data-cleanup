-- Invoice Tables Analysis Queries
-- NES Database Cleanup Project
-- Purpose: Analyze invoice_detail and subscription_invoice_detail_1 for cleanup opportunities

-- =============================================================================
-- INVOICE_DETAIL TABLE ANALYSIS
-- =============================================================================

-- 1. Age distribution analysis
-- Shows how records are distributed by year to understand retention patterns
SELECT 
    YEAR(COALESCE(created_date, updated_date, invoice_date)) as year,
    COUNT(*) as records,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM invoice_detail), 2) as percentage,
    ROUND(SUM(amount), 2) as total_amount
FROM invoice_detail 
GROUP BY YEAR(COALESCE(created_date, updated_date, invoice_date))
ORDER BY year DESC;

-- 2. Monthly distribution for recent years
-- More granular view of recent data
SELECT 
    DATE_FORMAT(COALESCE(created_date, updated_date, invoice_date), '%Y-%m') as month,
    COUNT(*) as records,
    ROUND(SUM(amount), 2) as total_amount
FROM invoice_detail 
WHERE COALESCE(created_date, updated_date, invoice_date) >= DATE_SUB(NOW(), INTERVAL 3 YEAR)
GROUP BY DATE_FORMAT(COALESCE(created_date, updated_date, invoice_date), '%Y-%m')
ORDER BY month DESC;

-- 3. Cleanup opportunity analysis - 5 year retention
-- Conservative approach: delete records older than 5 years
SELECT 
    'Records older than 5 years' as category,
    COUNT(*) as deletable_records,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM invoice_detail), 2) as percentage_of_total,
    ROUND(SUM(amount), 2) as total_amount_affected
FROM invoice_detail 
WHERE COALESCE(created_date, updated_date, invoice_date) < DATE_SUB(NOW(), INTERVAL 5 YEAR)

UNION ALL

SELECT 
    'Records to retain (5 year policy)' as category,
    COUNT(*) as records,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM invoice_detail), 2) as percentage_of_total,
    ROUND(SUM(amount), 2) as total_amount
FROM invoice_detail 
WHERE COALESCE(created_date, updated_date, invoice_date) >= DATE_SUB(NOW(), INTERVAL 5 YEAR);

-- 4. Cleanup opportunity analysis - 3 year retention
-- Aggressive approach: delete records older than 3 years
SELECT 
    'Records older than 3 years' as category,
    COUNT(*) as deletable_records,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM invoice_detail), 2) as percentage_of_total,
    ROUND(SUM(amount), 2) as total_amount_affected
FROM invoice_detail 
WHERE COALESCE(created_date, updated_date, invoice_date) < DATE_SUB(NOW(), INTERVAL 3 YEAR)

UNION ALL

SELECT 
    'Records to retain (3 year policy)' as category,
    COUNT(*) as records,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM invoice_detail), 2) as percentage_of_total,
    ROUND(SUM(amount), 2) as total_amount
FROM invoice_detail 
WHERE COALESCE(created_date, updated_date, invoice_date) >= DATE_SUB(NOW(), INTERVAL 3 YEAR);

-- 5. Data quality check
-- Check for records with missing or invalid dates
SELECT 
    'Records with valid dates' as category,
    COUNT(*) as record_count
FROM invoice_detail 
WHERE COALESCE(created_date, updated_date, invoice_date) IS NOT NULL

UNION ALL

SELECT 
    'Records with missing dates' as category,
    COUNT(*) as record_count
FROM invoice_detail 
WHERE COALESCE(created_date, updated_date, invoice_date) IS NULL;

-- =============================================================================
-- SUBSCRIPTION_INVOICE_DETAIL_1 TABLE ANALYSIS
-- =============================================================================

-- 6. Basic statistics for subscription_invoice_detail_1
-- Check if this table exists and get basic info
SELECT 
    'subscription_invoice_detail_1' as table_name,
    COUNT(*) as total_records,
    MIN(COALESCE(created_date, updated_date)) as oldest_record,
    MAX(COALESCE(created_date, updated_date)) as newest_record,
    DATEDIFF(NOW(), MAX(COALESCE(created_date, updated_date))) as days_since_last_update
FROM subscription_invoice_detail_1;

-- 7. Compare subscription tables (if main table exists)
-- Check if subscription_invoice_detail_1 is a duplicate
SELECT 
    'subscription_invoice_detail' as table_name,
    COUNT(*) as records,
    MIN(COALESCE(created_date, updated_date)) as oldest_record,
    MAX(COALESCE(created_date, updated_date)) as newest_record
FROM subscription_invoice_detail

UNION ALL

SELECT 
    'subscription_invoice_detail_1' as table_name,
    COUNT(*) as records,
    MIN(COALESCE(created_date, updated_date)) as oldest_record,
    MAX(COALESCE(created_date, updated_date)) as newest_record
FROM subscription_invoice_detail_1;

-- 8. Check for data overlap between subscription tables
-- Identify if subscription_invoice_detail_1 contains duplicate data
SELECT 
    'Overlapping records' as category,
    COUNT(*) as count
FROM subscription_invoice_detail s1
INNER JOIN subscription_invoice_detail_1 s2 
    ON s1.subscription_id = s2.subscription_id 
    AND s1.invoice_id = s2.invoice_id

UNION ALL

SELECT 
    'Unique to main table' as category,
    COUNT(*) as count
FROM subscription_invoice_detail s1
LEFT JOIN subscription_invoice_detail_1 s2 
    ON s1.subscription_id = s2.subscription_id 
    AND s1.invoice_id = s2.invoice_id
WHERE s2.subscription_id IS NULL

UNION ALL

SELECT 
    'Unique to _1 table' as category,
    COUNT(*) as count
FROM subscription_invoice_detail_1 s2
LEFT JOIN subscription_invoice_detail s1 
    ON s1.subscription_id = s2.subscription_id 
    AND s1.invoice_id = s2.invoice_id
WHERE s1.subscription_id IS NULL;

-- =============================================================================
-- BUSINESS IMPACT ANALYSIS
-- =============================================================================

-- 9. Recent activity check for old invoice_detail records
-- Check if old records are still being accessed/updated
SELECT 
    'Old records with recent updates' as category,
    COUNT(*) as record_count
FROM invoice_detail 
WHERE COALESCE(created_date, invoice_date) < DATE_SUB(NOW(), INTERVAL 5 YEAR)
AND updated_date >= DATE_SUB(NOW(), INTERVAL 1 YEAR);

-- 10. High-value transaction analysis
-- Identify if old records contain high-value transactions that might need retention
SELECT 
    YEAR(COALESCE(created_date, updated_date, invoice_date)) as year,
    COUNT(*) as total_records,
    COUNT(CASE WHEN amount > 10000 THEN 1 END) as high_value_records,
    MAX(amount) as max_amount,
    AVG(amount) as avg_amount
FROM invoice_detail 
WHERE COALESCE(created_date, updated_date, invoice_date) < DATE_SUB(NOW(), INTERVAL 3 YEAR)
GROUP BY YEAR(COALESCE(created_date, updated_date, invoice_date))
ORDER BY year DESC;

-- =============================================================================
-- STORAGE IMPACT ESTIMATION
-- =============================================================================

-- 11. Estimate storage savings for different retention policies
-- Calculate potential space savings based on record distribution
SELECT 
    retention_policy,
    deletable_records,
    ROUND(deletable_records * 100.0 / total_records, 2) as percentage_deletable,
    ROUND(deletable_records * avg_record_size_kb / 1024, 2) as estimated_savings_mb
FROM (
    SELECT 
        '3 year retention' as retention_policy,
        (SELECT COUNT(*) FROM invoice_detail WHERE COALESCE(created_date, updated_date, invoice_date) < DATE_SUB(NOW(), INTERVAL 3 YEAR)) as deletable_records,
        (SELECT COUNT(*) FROM invoice_detail) as total_records,
        (SELECT (data_length + index_length) / table_rows / 1024 FROM information_schema.tables WHERE table_schema = 'nes' AND table_name = 'invoice_detail') as avg_record_size_kb
    
    UNION ALL
    
    SELECT 
        '5 year retention' as retention_policy,
        (SELECT COUNT(*) FROM invoice_detail WHERE COALESCE(created_date, updated_date, invoice_date) < DATE_SUB(NOW(), INTERVAL 5 YEAR)) as deletable_records,
        (SELECT COUNT(*) FROM invoice_detail) as total_records,
        (SELECT (data_length + index_length) / table_rows / 1024 FROM information_schema.tables WHERE table_schema = 'nes' AND table_name = 'invoice_detail') as avg_record_size_kb
    
    UNION ALL
    
    SELECT 
        '7 year retention' as retention_policy,
        (SELECT COUNT(*) FROM invoice_detail WHERE COALESCE(created_date, updated_date, invoice_date) < DATE_SUB(NOW(), INTERVAL 7 YEAR)) as deletable_records,
        (SELECT COUNT(*) FROM invoice_detail) as total_records,
        (SELECT (data_length + index_length) / table_rows / 1024 FROM information_schema.tables WHERE table_schema = 'nes' AND table_name = 'invoice_detail') as avg_record_size_kb
) as analysis;

-- =============================================================================
-- SAFETY AND DEPENDENCY CHECKS
-- =============================================================================

-- 12. Check for foreign key dependencies
-- Identify tables that reference invoice_detail
SELECT 
    table_name,
    column_name,
    referenced_table_name,
    referenced_column_name
FROM information_schema.key_column_usage
WHERE referenced_table_name = 'invoice_detail'
AND table_schema = 'nes';

-- 13. Application access pattern analysis
-- Check recent access patterns (if audit logs exist)
-- Note: This query may need adjustment based on actual audit table structure
-- SELECT 
--     DATE(access_date) as access_date,
--     COUNT(*) as access_count,
--     COUNT(DISTINCT user_id) as unique_users
-- FROM audit_log 
-- WHERE table_name = 'invoice_detail'
-- AND access_date >= DATE_SUB(NOW(), INTERVAL 30 DAY)
-- GROUP BY DATE(access_date)
-- ORDER BY access_date DESC;

-- =============================================================================
-- SUMMARY REPORT QUERY
-- =============================================================================

-- 14. Executive summary query
-- Provides high-level overview for decision making
SELECT 
    'INVOICE_DETAIL ANALYSIS SUMMARY' as report_section,
    '' as metric,
    '' as value,
    '' as notes

UNION ALL

SELECT 
    'Current State',
    'Total Records',
    FORMAT((SELECT COUNT(*) FROM invoice_detail), 0),
    'Current table size'

UNION ALL

SELECT 
    'Current State',
    'Table Size (GB)',
    FORMAT((SELECT ROUND((data_length + index_length) / 1024 / 1024 / 1024, 2) FROM information_schema.tables WHERE table_schema = 'nes' AND table_name = 'invoice_detail'), 2),
    'Data + Index size'

UNION ALL

SELECT 
    '5-Year Retention',
    'Deletable Records',
    FORMAT((SELECT COUNT(*) FROM invoice_detail WHERE COALESCE(created_date, updated_date, invoice_date) < DATE_SUB(NOW(), INTERVAL 5 YEAR)), 0),
    'Conservative approach'

UNION ALL

SELECT 
    '3-Year Retention',
    'Deletable Records', 
    FORMAT((SELECT COUNT(*) FROM invoice_detail WHERE COALESCE(created_date, updated_date, invoice_date) < DATE_SUB(NOW(), INTERVAL 3 YEAR)), 0),
    'Aggressive approach'

UNION ALL

SELECT 
    'Subscription Detail 1',
    'Total Records',
    FORMAT((SELECT COUNT(*) FROM subscription_invoice_detail_1), 0),
    'Potential duplicate table';

