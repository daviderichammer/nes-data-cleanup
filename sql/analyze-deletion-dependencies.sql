-- =============================================================================
-- DELETION DEPENDENCY ANALYSIS
-- =============================================================================
-- This script analyzes the dependencies to determine safe deletion order
-- Based on foreign keys and polymorphic relationships discovered

-- =============================================================================
-- 1. CONTACT DELETION IMPACT ANALYSIS
-- =============================================================================

-- For a given contact_id, show all dependent records that would be affected
-- Replace @contact_id with actual contact ID for testing
SET @contact_id = 12345;  -- Example contact ID

-- Direct foreign key dependencies
SELECT 'bank' as table_name, COUNT(*) as dependent_records FROM bank WHERE contact_id = @contact_id
UNION ALL
SELECT 'subscription' as table_name, COUNT(*) FROM subscription WHERE contact_id = @contact_id
UNION ALL
SELECT 'contact_batch' as table_name, COUNT(*) FROM contact_batch WHERE contact_id = @contact_id
UNION ALL
SELECT 'contact_logical_unit' as table_name, COUNT(*) FROM contact_logical_unit WHERE contact_id = @contact_id
UNION ALL
SELECT 'nes_anet_customer_profile' as table_name, COUNT(*) FROM nes_anet_customer_profile WHERE contact_id = @contact_id;

-- Polymorphic dependencies (where contact is referenced via object_id)
-- Need to find the object_type_id for contacts first
SELECT 
    'email_polymorphic' as table_name, 
    COUNT(*) as dependent_records 
FROM email e 
JOIN object o ON e.object_type_id = o.object_type_id 
WHERE o.object_type = 'Contact' AND e.object_id = @contact_id

UNION ALL

SELECT 
    'address_polymorphic' as table_name, 
    COUNT(*) 
FROM address a 
JOIN object o ON a.object_type_id = o.object_type_id 
WHERE o.object_type = 'Contact' AND a.object_id = @contact_id

UNION ALL

SELECT 
    'phone_polymorphic' as table_name, 
    COUNT(*) 
FROM phone p 
JOIN object o ON p.object_type_id = o.object_type_id 
WHERE o.object_type = 'Contact' AND p.object_id = @contact_id

UNION ALL

SELECT 
    'note_polymorphic' as table_name, 
    COUNT(*) 
FROM note n 
JOIN object o ON n.object_type_id = o.object_type_id 
WHERE o.object_type = 'Contact' AND n.object_id = @contact_id

UNION ALL

SELECT 
    'tenant_polymorphic' as table_name, 
    COUNT(*) 
FROM tenant t 
JOIN object o ON t.object_type_id = o.object_type_id 
WHERE o.object_type = 'Contact' AND t.object_id = @contact_id;

-- =============================================================================
-- 2. DELETION ORDER STRATEGY
-- =============================================================================

-- Based on foreign key analysis, determine deletion order
-- Tables must be deleted in reverse dependency order

-- LEVEL 1: Leaf tables (no other tables depend on them)
SELECT 'LEVEL_1_LEAF_TABLES' as deletion_level, 
       'email_attachment, email_preview, invoice_detail, itemized_bill_data, tender, work_order_attribute' as tables,
       'These tables only reference other tables, nothing references them' as notes

UNION ALL

-- LEVEL 2: Tables that depend only on Level 1 or lookup tables
SELECT 'LEVEL_2_DEPENDENT', 
       'email, address, phone, note, tenant, reading (non-billing), subscription_component',
       'These can be deleted after Level 1, but before their parent records'

UNION ALL

-- LEVEL 3: Core business entities with dependencies
SELECT 'LEVEL_3_CORE', 
       'invoice, subscription, batch_detail, contact_batch',
       'Core business records that other entities depend on'

UNION ALL

-- LEVEL 4: Primary entities
SELECT 'LEVEL_4_PRIMARY', 
       'contact, batch, journal_entry',
       'Primary entities that many other tables reference'

UNION ALL

-- LEVEL 5: Master data
SELECT 'LEVEL_5_MASTER', 
       'community_logical_unit, contact_type, object_type, etc.',
       'Master/lookup data - should not be deleted in normal cleanup';

-- =============================================================================
-- 3. SAFE DELETION VALIDATION QUERIES
-- =============================================================================

-- Before deleting any contact, verify it's safe by checking all dependencies
-- This query template can be used to validate each contact before deletion

-- Check if contact has any dependencies that would prevent deletion
SELECT 
    c.contact_id,
    c.contact_name,
    ct.contact_type,
    
    -- Count direct dependencies
    (SELECT COUNT(*) FROM subscription WHERE contact_id = c.contact_id) as subscriptions,
    (SELECT COUNT(*) FROM contact_batch WHERE contact_id = c.contact_id) as batches,
    (SELECT COUNT(*) FROM bank WHERE contact_id = c.contact_id) as banks,
    
    -- Count polymorphic dependencies (need to join with object table)
    (SELECT COUNT(*) FROM email e JOIN object o ON e.object_type_id = o.object_type_id 
     WHERE o.object_type = 'Contact' AND e.object_id = c.contact_id) as emails,
    (SELECT COUNT(*) FROM address a JOIN object o ON a.object_type_id = o.object_type_id 
     WHERE o.object_type = 'Contact' AND a.object_id = c.contact_id) as addresses,
    (SELECT COUNT(*) FROM phone p JOIN object o ON p.object_type_id = o.object_type_id 
     WHERE o.object_type = 'Contact' AND p.object_id = c.contact_id) as phones,
    (SELECT COUNT(*) FROM note n JOIN object o ON n.object_type_id = o.object_type_id 
     WHERE o.object_type = 'Contact' AND n.object_id = c.contact_id) as notes,
    (SELECT COUNT(*) FROM tenant t JOIN object o ON t.object_type_id = o.object_type_id 
     WHERE o.object_type = 'Contact' AND t.object_id = c.contact_id) as tenants

FROM contact c
JOIN contact_type ct ON c.contact_type_id = ct.contact_type_id
WHERE c.contact_id = @contact_id;

-- =============================================================================
-- 4. READING DELETION VALIDATION
-- =============================================================================

-- Verify readings are safe to delete (not used for billing)
SELECT 
    r.reading_id,
    r.reading_date,
    CASE 
        WHEN su.reading_id IS NOT NULL THEN 'USED_FOR_BILLING'
        ELSE 'SAFE_TO_DELETE'
    END as billing_status,
    su.sm_usage_id
FROM reading r
LEFT JOIN sm_usage su ON r.reading_id = su.reading_id
WHERE r.reading_date < DATE_SUB(NOW(), INTERVAL 2 YEAR)
ORDER BY r.reading_id
LIMIT 100;  -- Sample for validation

-- =============================================================================
-- 5. BATCH DELETION VALIDATION
-- =============================================================================

-- Check if batches are safe to delete (no recent activity)
SELECT 
    b.batch_id,
    b.created_date,
    bt.batch_type,
    (SELECT COUNT(*) FROM contact_batch WHERE batch_id = b.batch_id) as contact_count,
    (SELECT COUNT(*) FROM batch_detail WHERE batch_id = b.batch_id) as detail_count
FROM batch b
JOIN batch_type bt ON b.batch_type_id = bt.batch_type_id
WHERE b.created_date < DATE_SUB(NOW(), INTERVAL 7 YEAR)
ORDER BY b.batch_id
LIMIT 100;  -- Sample for validation

-- =============================================================================
-- 6. ORPHANED RECORD IDENTIFICATION
-- =============================================================================

-- Find orphaned records that can be safely deleted
-- These are records that reference deleted or non-existent parent records

-- Orphaned emails (referencing non-existent contacts)
SELECT 'orphaned_emails' as record_type, COUNT(*) as count
FROM email e
JOIN object o ON e.object_type_id = o.object_type_id
WHERE o.object_type = 'Contact'
AND NOT EXISTS (SELECT 1 FROM contact WHERE contact_id = e.object_id);

-- Orphaned addresses
SELECT 'orphaned_addresses' as record_type, COUNT(*) as count
FROM address a
JOIN object o ON a.object_type_id = o.object_type_id
WHERE o.object_type = 'Contact'
AND NOT EXISTS (SELECT 1 FROM contact WHERE contact_id = a.object_id);

-- Orphaned phones
SELECT 'orphaned_phones' as record_type, COUNT(*) as count
FROM phone p
JOIN object o ON p.object_type_id = o.object_type_id
WHERE o.object_type = 'Contact'
AND NOT EXISTS (SELECT 1 FROM contact WHERE contact_id = p.object_id);

-- Orphaned notes
SELECT 'orphaned_notes' as record_type, COUNT(*) as count
FROM note n
JOIN object o ON n.object_type_id = o.object_type_id
WHERE o.object_type = 'Contact'
AND NOT EXISTS (SELECT 1 FROM contact WHERE contact_id = n.object_id);

