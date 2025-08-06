-- Invoice Tables Cutoff Analysis
-- NES Database Cleanup Project
-- Purpose: Create accurate cutoff queries for subscription_invoice_detail and invoice_detail
-- Date Path: subscription_invoice_detail → invoice_detail → invoice → sm_bill → payment_due_date

-- =============================================================================
-- SCHEMA RELATIONSHIP VERIFICATION
-- =============================================================================

-- First, let's verify the relationship chain works
SELECT 
    'Relationship Chain Verification' as analysis_section,
    relationship_step,
    record_count,
    notes
FROM (
    SELECT 
        '1. subscription_invoice_detail records' as relationship_step,
        COUNT(*) as record_count,
        'Base table for analysis' as notes
    FROM subscription_invoice_detail
    
    UNION ALL
    
    SELECT 
        '2. subscription_invoice_detail → invoice_detail' as relationship_step,
        COUNT(*) as record_count,
        'Records with valid invoice_detail_id' as notes
    FROM subscription_invoice_detail sid
    INNER JOIN invoice_detail id ON sid.invoice_detail_id = id.invoice_detail_id
    
    UNION ALL
    
    SELECT 
        '3. invoice_detail → invoice' as relationship_step,
        COUNT(*) as record_count,
        'Records with valid invoice_id' as notes
    FROM subscription_invoice_detail sid
    INNER JOIN invoice_detail id ON sid.invoice_detail_id = id.invoice_detail_id
    INNER JOIN invoice i ON id.invoice_id = i.invoice_id
    
    UNION ALL
    
    SELECT 
        '4. invoice → sm_bill (payment_due_date)' as relationship_step,
        COUNT(*) as record_count,
        'Records with payment_due_date available' as notes
    FROM subscription_invoice_detail sid
    INNER JOIN invoice_detail id ON sid.invoice_detail_id = id.invoice_detail_id
    INNER JOIN invoice i ON id.invoice_id = i.invoice_id
    INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
    
    UNION ALL
    
    SELECT 
        '5. Records with valid payment_due_date' as relationship_step,
        COUNT(*) as record_count,
        'Excluding default/invalid dates' as notes
    FROM subscription_invoice_detail sid
    INNER JOIN invoice_detail id ON sid.invoice_detail_id = id.invoice_detail_id
    INNER JOIN invoice i ON id.invoice_id = i.invoice_id
    INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
    WHERE sb.payment_due_date > '1900-01-01'
    AND sb.payment_due_date < '2030-01-01'
) as relationship_analysis
ORDER BY relationship_step;

-- =============================================================================
-- SUBSCRIPTION_INVOICE_DETAIL CUTOFF ANALYSIS
-- =============================================================================

-- Age distribution analysis for subscription_invoice_detail
SELECT 
    'SUBSCRIPTION_INVOICE_DETAIL AGE ANALYSIS' as analysis_section,
    YEAR(sb.payment_due_date) as payment_year,
    COUNT(*) as record_count,
    ROUND(COUNT(*) * 100.0 / total_records.total, 2) as percentage,
    MIN(sb.payment_due_date) as earliest_payment_due,
    MAX(sb.payment_due_date) as latest_payment_due
FROM subscription_invoice_detail sid
INNER JOIN invoice_detail id ON sid.invoice_detail_id = id.invoice_detail_id
INNER JOIN invoice i ON id.invoice_id = i.invoice_id
INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
CROSS JOIN (
    SELECT COUNT(*) as total
    FROM subscription_invoice_detail sid2
    INNER JOIN invoice_detail id2 ON sid2.invoice_detail_id = id2.invoice_detail_id
    INNER JOIN invoice i2 ON id2.invoice_id = i2.invoice_id
    INNER JOIN sm_bill sb2 ON i2.invoice_id = sb2.invoice_id
    WHERE sb2.payment_due_date > '1900-01-01'
) as total_records
WHERE sb.payment_due_date > '1900-01-01'
AND sb.payment_due_date < '2030-01-01'
GROUP BY YEAR(sb.payment_due_date)
ORDER BY payment_year DESC;

-- Cutoff analysis for subscription_invoice_detail - 5 year retention
SELECT 
    'SUBSCRIPTION_INVOICE_DETAIL CUTOFF ANALYSIS (5 YEAR)' as analysis_section,
    retention_category,
    record_count,
    percentage,
    cutoff_id_range,
    recommendation
FROM (
    SELECT 
        'Records older than 5 years (DELETABLE)' as retention_category,
        COUNT(*) as record_count,
        ROUND(COUNT(*) * 100.0 / total_records.total, 2) as percentage,
        CONCAT('ID range: ', MIN(sid.subscription_invoice_detail_id), ' to ', MAX(sid.subscription_invoice_detail_id)) as cutoff_id_range,
        'Safe to delete - old billing data' as recommendation
    FROM subscription_invoice_detail sid
    INNER JOIN invoice_detail id ON sid.invoice_detail_id = id.invoice_detail_id
    INNER JOIN invoice i ON id.invoice_id = i.invoice_id
    INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
    CROSS JOIN (
        SELECT COUNT(*) as total
        FROM subscription_invoice_detail sid2
        INNER JOIN invoice_detail id2 ON sid2.invoice_detail_id = id2.invoice_detail_id
        INNER JOIN invoice i2 ON id2.invoice_id = i2.invoice_id
        INNER JOIN sm_bill sb2 ON i2.invoice_id = sb2.invoice_id
        WHERE sb2.payment_due_date > '1900-01-01'
    ) as total_records
    WHERE sb.payment_due_date < DATE_SUB(NOW(), INTERVAL 5 YEAR)
    AND sb.payment_due_date > '1900-01-01'
    
    UNION ALL
    
    SELECT 
        'Records within 5 years (RETAIN)' as retention_category,
        COUNT(*) as record_count,
        ROUND(COUNT(*) * 100.0 / total_records.total, 2) as percentage,
        CONCAT('ID range: ', MIN(sid.subscription_invoice_detail_id), ' to ', MAX(sid.subscription_invoice_detail_id)) as cutoff_id_range,
        'Must retain - recent billing data' as recommendation
    FROM subscription_invoice_detail sid
    INNER JOIN invoice_detail id ON sid.invoice_detail_id = id.invoice_detail_id
    INNER JOIN invoice i ON id.invoice_id = i.invoice_id
    INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
    CROSS JOIN (
        SELECT COUNT(*) as total
        FROM subscription_invoice_detail sid2
        INNER JOIN invoice_detail id2 ON sid2.invoice_detail_id = id2.invoice_detail_id
        INNER JOIN invoice i2 ON id2.invoice_id = i2.invoice_id
        INNER JOIN sm_bill sb2 ON i2.invoice_id = sb2.invoice_id
        WHERE sb2.payment_due_date > '1900-01-01'
    ) as total_records
    WHERE sb.payment_due_date >= DATE_SUB(NOW(), INTERVAL 5 YEAR)
    AND sb.payment_due_date > '1900-01-01'
) as cutoff_analysis;

-- Find the exact cutoff ID for subscription_invoice_detail (5 year retention)
SELECT 
    'SUBSCRIPTION_INVOICE_DETAIL CUTOFF ID (5 YEAR)' as analysis_section,
    COALESCE(MAX(sid.subscription_invoice_detail_id), 0) as cutoff_id,
    COUNT(*) as deletable_records,
    MIN(sb.payment_due_date) as oldest_payment_due,
    MAX(sb.payment_due_date) as newest_payment_due,
    'DELETE WHERE subscription_invoice_detail_id <= cutoff_id' as deletion_logic
FROM subscription_invoice_detail sid
INNER JOIN invoice_detail id ON sid.invoice_detail_id = id.invoice_detail_id
INNER JOIN invoice i ON id.invoice_id = i.invoice_id
INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
WHERE sb.payment_due_date < DATE_SUB(NOW(), INTERVAL 5 YEAR)
AND sb.payment_due_date > '1900-01-01';

-- =============================================================================
-- INVOICE_DETAIL CUTOFF ANALYSIS
-- =============================================================================

-- Age distribution analysis for invoice_detail
SELECT 
    'INVOICE_DETAIL AGE ANALYSIS' as analysis_section,
    YEAR(sb.payment_due_date) as payment_year,
    COUNT(*) as record_count,
    ROUND(COUNT(*) * 100.0 / total_records.total, 2) as percentage,
    MIN(sb.payment_due_date) as earliest_payment_due,
    MAX(sb.payment_due_date) as latest_payment_due
FROM invoice_detail id
INNER JOIN invoice i ON id.invoice_id = i.invoice_id
INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
CROSS JOIN (
    SELECT COUNT(*) as total
    FROM invoice_detail id2
    INNER JOIN invoice i2 ON id2.invoice_id = i2.invoice_id
    INNER JOIN sm_bill sb2 ON i2.invoice_id = sb2.invoice_id
    WHERE sb2.payment_due_date > '1900-01-01'
) as total_records
WHERE sb.payment_due_date > '1900-01-01'
AND sb.payment_due_date < '2030-01-01'
GROUP BY YEAR(sb.payment_due_date)
ORDER BY payment_year DESC;

-- Cutoff analysis for invoice_detail - 5 year retention
SELECT 
    'INVOICE_DETAIL CUTOFF ANALYSIS (5 YEAR)' as analysis_section,
    retention_category,
    record_count,
    percentage,
    cutoff_id_range,
    recommendation
FROM (
    SELECT 
        'Records older than 5 years (DELETABLE)' as retention_category,
        COUNT(*) as record_count,
        ROUND(COUNT(*) * 100.0 / total_records.total, 2) as percentage,
        CONCAT('ID range: ', MIN(id.invoice_detail_id), ' to ', MAX(id.invoice_detail_id)) as cutoff_id_range,
        'Safe to delete - old billing data' as recommendation
    FROM invoice_detail id
    INNER JOIN invoice i ON id.invoice_id = i.invoice_id
    INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
    CROSS JOIN (
        SELECT COUNT(*) as total
        FROM invoice_detail id2
        INNER JOIN invoice i2 ON id2.invoice_id = i2.invoice_id
        INNER JOIN sm_bill sb2 ON i2.invoice_id = sb2.invoice_id
        WHERE sb2.payment_due_date > '1900-01-01'
    ) as total_records
    WHERE sb.payment_due_date < DATE_SUB(NOW(), INTERVAL 5 YEAR)
    AND sb.payment_due_date > '1900-01-01'
    
    UNION ALL
    
    SELECT 
        'Records within 5 years (RETAIN)' as retention_category,
        COUNT(*) as record_count,
        ROUND(COUNT(*) * 100.0 / total_records.total, 2) as percentage,
        CONCAT('ID range: ', MIN(id.invoice_detail_id), ' to ', MAX(id.invoice_detail_id)) as cutoff_id_range,
        'Must retain - recent billing data' as recommendation
    FROM invoice_detail id
    INNER JOIN invoice i ON id.invoice_id = i.invoice_id
    INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
    CROSS JOIN (
        SELECT COUNT(*) as total
        FROM invoice_detail id2
        INNER JOIN invoice i2 ON id2.invoice_id = i2.invoice_id
        INNER JOIN sm_bill sb2 ON i2.invoice_id = sb2.invoice_id
        WHERE sb2.payment_due_date > '1900-01-01'
    ) as total_records
    WHERE sb.payment_due_date >= DATE_SUB(NOW(), INTERVAL 5 YEAR)
    AND sb.payment_due_date > '1900-01-01'
) as cutoff_analysis;

-- Find the exact cutoff ID for invoice_detail (5 year retention)
SELECT 
    'INVOICE_DETAIL CUTOFF ID (5 YEAR)' as analysis_section,
    COALESCE(MAX(id.invoice_detail_id), 0) as cutoff_id,
    COUNT(*) as deletable_records,
    MIN(sb.payment_due_date) as oldest_payment_due,
    MAX(sb.payment_due_date) as newest_payment_due,
    'DELETE WHERE invoice_detail_id <= cutoff_id' as deletion_logic
FROM invoice_detail id
INNER JOIN invoice i ON id.invoice_id = i.invoice_id
INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
WHERE sb.payment_due_date < DATE_SUB(NOW(), INTERVAL 5 YEAR)
AND sb.payment_due_date > '1900-01-01';

-- =============================================================================
-- ALTERNATIVE RETENTION PERIODS
-- =============================================================================

-- 3-year retention analysis (more aggressive)
SELECT 
    'ALTERNATIVE RETENTION ANALYSIS (3 YEAR)' as analysis_section,
    table_name,
    deletable_records,
    percentage_deletable,
    estimated_space_savings_gb
FROM (
    SELECT 
        'subscription_invoice_detail' as table_name,
        COUNT(*) as deletable_records,
        ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM subscription_invoice_detail), 2) as percentage_deletable,
        'TBD - need table size analysis' as estimated_space_savings_gb
    FROM subscription_invoice_detail sid
    INNER JOIN invoice_detail id ON sid.invoice_detail_id = id.invoice_detail_id
    INNER JOIN invoice i ON id.invoice_id = i.invoice_id
    INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
    WHERE sb.payment_due_date < DATE_SUB(NOW(), INTERVAL 3 YEAR)
    AND sb.payment_due_date > '1900-01-01'
    
    UNION ALL
    
    SELECT 
        'invoice_detail' as table_name,
        COUNT(*) as deletable_records,
        ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM invoice_detail), 2) as percentage_deletable,
        ROUND(COUNT(*) * 19.0 / (SELECT COUNT(*) FROM invoice_detail), 2) as estimated_space_savings_gb
    FROM invoice_detail id
    INNER JOIN invoice i ON id.invoice_id = i.invoice_id
    INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
    WHERE sb.payment_due_date < DATE_SUB(NOW(), INTERVAL 3 YEAR)
    AND sb.payment_due_date > '1900-01-01'
) as retention_analysis;

-- 7-year retention analysis (conservative)
SELECT 
    'ALTERNATIVE RETENTION ANALYSIS (7 YEAR)' as analysis_section,
    table_name,
    deletable_records,
    percentage_deletable,
    estimated_space_savings_gb
FROM (
    SELECT 
        'subscription_invoice_detail' as table_name,
        COUNT(*) as deletable_records,
        ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM subscription_invoice_detail), 2) as percentage_deletable,
        'TBD - need table size analysis' as estimated_space_savings_gb
    FROM subscription_invoice_detail sid
    INNER JOIN invoice_detail id ON sid.invoice_detail_id = id.invoice_detail_id
    INNER JOIN invoice i ON id.invoice_id = i.invoice_id
    INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
    WHERE sb.payment_due_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
    AND sb.payment_due_date > '1900-01-01'
    
    UNION ALL
    
    SELECT 
        'invoice_detail' as table_name,
        COUNT(*) as deletable_records,
        ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM invoice_detail), 2) as percentage_deletable,
        ROUND(COUNT(*) * 19.0 / (SELECT COUNT(*) FROM invoice_detail), 2) as estimated_space_savings_gb
    FROM invoice_detail id
    INNER JOIN invoice i ON id.invoice_id = i.invoice_id
    INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
    WHERE sb.payment_due_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
    AND sb.payment_due_date > '1900-01-01'
) as retention_analysis;

-- =============================================================================
-- DEPENDENCY AND SAFETY CHECKS
-- =============================================================================

-- Check for orphaned records (invoice_detail without sm_bill)
SELECT 
    'ORPHANED RECORDS ANALYSIS' as analysis_section,
    orphan_type,
    record_count,
    impact_assessment
FROM (
    SELECT 
        'invoice_detail without sm_bill' as orphan_type,
        COUNT(*) as record_count,
        'These records cannot be dated - need special handling' as impact_assessment
    FROM invoice_detail id
    INNER JOIN invoice i ON id.invoice_id = i.invoice_id
    LEFT JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
    WHERE sb.invoice_id IS NULL
    
    UNION ALL
    
    SELECT 
        'subscription_invoice_detail without sm_bill' as orphan_type,
        COUNT(*) as record_count,
        'These records cannot be dated - need special handling' as impact_assessment
    FROM subscription_invoice_detail sid
    INNER JOIN invoice_detail id ON sid.invoice_detail_id = id.invoice_detail_id
    INNER JOIN invoice i ON id.invoice_id = i.invoice_id
    LEFT JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
    WHERE sb.invoice_id IS NULL
) as orphan_analysis;

-- Check for records with invalid payment_due_date
SELECT 
    'INVALID DATE ANALYSIS' as analysis_section,
    date_issue_type,
    record_count,
    handling_recommendation
FROM (
    SELECT 
        'payment_due_date = 0000-00-00' as date_issue_type,
        COUNT(*) as record_count,
        'Exclude from date-based cleanup' as handling_recommendation
    FROM invoice_detail id
    INNER JOIN invoice i ON id.invoice_id = i.invoice_id
    INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
    WHERE sb.payment_due_date = '0000-00-00 00:00:00'
    
    UNION ALL
    
    SELECT 
        'payment_due_date in future (>2030)' as date_issue_type,
        COUNT(*) as record_count,
        'Exclude from cleanup - likely data error' as handling_recommendation
    FROM invoice_detail id
    INNER JOIN invoice i ON id.invoice_id = i.invoice_id
    INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
    WHERE sb.payment_due_date > '2030-01-01'
    
    UNION ALL
    
    SELECT 
        'payment_due_date too old (<1990)' as date_issue_type,
        COUNT(*) as record_count,
        'Exclude from cleanup - likely data error' as handling_recommendation
    FROM invoice_detail id
    INNER JOIN invoice i ON id.invoice_id = i.invoice_id
    INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
    WHERE sb.payment_due_date < '1990-01-01'
    AND sb.payment_due_date != '0000-00-00 00:00:00'
) as date_issue_analysis;

-- =============================================================================
-- EXECUTIVE SUMMARY
-- =============================================================================

-- Final summary with recommendations
SELECT 
    'EXECUTIVE SUMMARY - INVOICE TABLES CLEANUP' as summary_section,
    metric,
    value,
    recommendation
FROM (
    SELECT 
        'Total invoice_detail records' as metric,
        FORMAT((SELECT COUNT(*) FROM invoice_detail), 0) as value,
        '19 GB table - major cleanup opportunity' as recommendation
    
    UNION ALL
    
    SELECT 
        'invoice_detail with valid dates' as metric,
        FORMAT((
            SELECT COUNT(*)
            FROM invoice_detail id
            INNER JOIN invoice i ON id.invoice_id = i.invoice_id
            INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
            WHERE sb.payment_due_date > '1900-01-01'
            AND sb.payment_due_date < '2030-01-01'
        ), 0) as value,
        'Records that can be safely date-filtered' as recommendation
    
    UNION ALL
    
    SELECT 
        'invoice_detail deletable (5-year)' as metric,
        FORMAT((
            SELECT COUNT(*)
            FROM invoice_detail id
            INNER JOIN invoice i ON id.invoice_id = i.invoice_id
            INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
            WHERE sb.payment_due_date < DATE_SUB(NOW(), INTERVAL 5 YEAR)
            AND sb.payment_due_date > '1900-01-01'
        ), 0) as value,
        'Conservative cleanup target' as recommendation
    
    UNION ALL
    
    SELECT 
        'subscription_invoice_detail deletable (5-year)' as metric,
        FORMAT((
            SELECT COUNT(*)
            FROM subscription_invoice_detail sid
            INNER JOIN invoice_detail id ON sid.invoice_detail_id = id.invoice_detail_id
            INNER JOIN invoice i ON id.invoice_id = i.invoice_id
            INNER JOIN sm_bill sb ON i.invoice_id = sb.invoice_id
            WHERE sb.payment_due_date < DATE_SUB(NOW(), INTERVAL 5 YEAR)
            AND sb.payment_due_date > '1900-01-01'
        ), 0) as value,
        'Dependent cleanup after invoice_detail' as recommendation
) as summary_metrics;

