-- Check actual contact types in the database
-- This will help us identify the correct contact types for communities

-- List all contact types
SELECT 
    contact_type_id,
    contact_type,
    COUNT(*) as contact_count
FROM contact_type ct
LEFT JOIN contact c ON ct.contact_type_id = c.contact_type_id
GROUP BY ct.contact_type_id, ct.contact_type
ORDER BY contact_count DESC;

-- Look for contact types that might indicate closed/inactive communities
SELECT 
    contact_type_id,
    contact_type,
    COUNT(*) as contact_count
FROM contact_type ct
LEFT JOIN contact c ON ct.contact_type_id = c.contact_type_id
WHERE LOWER(ct.contact_type) LIKE '%clos%'
   OR LOWER(ct.contact_type) LIKE '%inact%'
   OR LOWER(ct.contact_type) LIKE '%term%'
   OR LOWER(ct.contact_type) LIKE '%end%'
   OR LOWER(ct.contact_type) LIKE '%zy%'
   OR LOWER(ct.contact_type) LIKE '%dead%'
   OR LOWER(ct.contact_type) LIKE '%cancel%'
GROUP BY ct.contact_type_id, ct.contact_type
ORDER BY contact_count DESC;

-- Check if there are any community-specific contact types
SELECT 
    contact_type_id,
    contact_type,
    COUNT(*) as contact_count
FROM contact_type ct
LEFT JOIN contact c ON ct.contact_type_id = c.contact_type_id
WHERE LOWER(ct.contact_type) LIKE '%commun%'
   OR LOWER(ct.contact_type) LIKE '%proper%'
   OR LOWER(ct.contact_type) LIKE '%build%'
   OR LOWER(ct.contact_type) LIKE '%complex%'
GROUP BY ct.contact_type_id, ct.contact_type
ORDER BY contact_count DESC;

-- Show contacts with last_updated_on older than 7 years by contact type
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
ORDER BY old_contacts DESC;

