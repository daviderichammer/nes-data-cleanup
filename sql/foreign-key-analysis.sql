-- Foreign Key Analysis for NES Database
-- This script analyzes foreign key relationships to determine deletion order

-- Get all foreign key constraints
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

-- Analyze dependency depth for contact-related tables
-- This helps determine deletion order for account cleanup
WITH RECURSIVE dependency_tree AS (
    -- Base case: tables that reference contact directly
    SELECT 
        TABLE_NAME as dependent_table,
        REFERENCED_TABLE_NAME as parent_table,
        1 as depth_level
    FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
    WHERE REFERENCED_TABLE_SCHEMA = 'nes'
    AND REFERENCED_TABLE_NAME = 'contact'
    
    UNION ALL
    
    -- Recursive case: tables that reference the dependent tables
    SELECT 
        kcu.TABLE_NAME as dependent_table,
        dt.dependent_table as parent_table,
        dt.depth_level + 1 as depth_level
    FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
    JOIN dependency_tree dt ON kcu.REFERENCED_TABLE_NAME = dt.dependent_table
    WHERE kcu.REFERENCED_TABLE_SCHEMA = 'nes'
    AND dt.depth_level < 5  -- Prevent infinite recursion
)
SELECT 
    dependent_table,
    parent_table,
    depth_level
FROM dependency_tree
ORDER BY depth_level DESC, dependent_table;

-- Find tables that have no foreign key dependencies (safe to delete first)
SELECT DISTINCT t.TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES t
LEFT JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu 
    ON t.TABLE_NAME = kcu.TABLE_NAME 
    AND kcu.REFERENCED_TABLE_SCHEMA = 'nes'
WHERE t.TABLE_SCHEMA = 'nes'
AND t.TABLE_TYPE = 'BASE TABLE'
AND kcu.TABLE_NAME IS NULL
ORDER BY t.TABLE_NAME;

-- Identify circular dependencies (if any)
SELECT DISTINCT
    a.TABLE_NAME as table_a,
    a.REFERENCED_TABLE_NAME as references_table_b,
    b.TABLE_NAME as table_b,
    b.REFERENCED_TABLE_NAME as references_table_a
FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE a
JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE b 
    ON a.REFERENCED_TABLE_NAME = b.TABLE_NAME
    AND b.REFERENCED_TABLE_NAME = a.TABLE_NAME
WHERE a.REFERENCED_TABLE_SCHEMA = 'nes'
AND b.REFERENCED_TABLE_SCHEMA = 'nes';

