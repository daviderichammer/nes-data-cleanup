-- =============================================================================
-- EAV RELATIONSHIP DISCOVERY QUERIES
-- =============================================================================
-- These queries help identify implicit foreign key relationships in the EAV model
-- that aren't captured by formal foreign key constraints

-- =============================================================================
-- 1. POLYMORPHIC RELATIONSHIPS (object_id + object_type_id patterns)
-- =============================================================================

-- Find all tables with polymorphic relationship patterns
SELECT 
    table_name,
    'polymorphic_relationship' as relationship_type,
    GROUP_CONCAT(column_name ORDER BY column_name) as columns
FROM information_schema.columns 
WHERE table_schema = DATABASE()
AND (
    column_name = 'object_id' 
    OR column_name = 'object_type_id'
)
GROUP BY table_name
HAVING COUNT(*) = 2  -- Must have both object_id and object_type_id
ORDER BY table_name;

-- =============================================================================
-- 2. CONTACT POLYMORPHIC RELATIONSHIPS
-- =============================================================================

-- Discover what object types are referenced in contact table
SELECT 
    o.object_type_id,
    o.object_type,
    COUNT(*) as contact_count,
    MIN(c.contact_id) as min_contact_id,
    MAX(c.contact_id) as max_contact_id
FROM contact c
JOIN object o ON c.object_type_id = o.object_type_id
GROUP BY o.object_type_id, o.object_type
ORDER BY contact_count DESC;

-- =============================================================================
-- 3. EMAIL POLYMORPHIC RELATIONSHIPS  
-- =============================================================================

-- Discover what object types emails are linked to
SELECT 
    o.object_type_id,
    o.object_type,
    COUNT(*) as email_count,
    MIN(e.email_id) as min_email_id,
    MAX(e.email_id) as max_email_id
FROM email e
JOIN object o ON e.object_type_id = o.object_type_id
GROUP BY o.object_type_id, o.object_type
ORDER BY email_count DESC;

-- =============================================================================
-- 4. ADDRESS POLYMORPHIC RELATIONSHIPS
-- =============================================================================

-- Discover what object types addresses are linked to
SELECT 
    o.object_type_id,
    o.object_type,
    COUNT(*) as address_count,
    MIN(a.address_id) as min_address_id,
    MAX(a.address_id) as max_address_id
FROM address a
JOIN object o ON a.object_type_id = o.object_type_id
GROUP BY o.object_type_id, o.object_type
ORDER BY address_count DESC;

-- =============================================================================
-- 5. PHONE POLYMORPHIC RELATIONSHIPS
-- =============================================================================

-- Discover what object types phones are linked to
SELECT 
    o.object_type_id,
    o.object_type,
    COUNT(*) as phone_count,
    MIN(p.phone_id) as min_phone_id,
    MAX(p.phone_id) as max_phone_id
FROM phone p
JOIN object o ON p.object_type_id = o.object_type_id
GROUP BY o.object_type_id, o.object_type
ORDER BY phone_count DESC;

-- =============================================================================
-- 6. NOTE POLYMORPHIC RELATIONSHIPS
-- =============================================================================

-- Discover what object types notes are linked to
SELECT 
    o.object_type_id,
    o.object_type,
    COUNT(*) as note_count,
    MIN(n.note_id) as min_note_id,
    MAX(n.note_id) as max_note_id
FROM note n
JOIN object o ON n.object_type_id = o.object_type_id
GROUP BY o.object_type_id, o.object_type
ORDER BY note_count DESC;

-- =============================================================================
-- 7. TENANT POLYMORPHIC RELATIONSHIPS
-- =============================================================================

-- Discover what object types tenants are linked to
SELECT 
    o.object_type_id,
    o.object_type,
    COUNT(*) as tenant_count,
    MIN(t.tenant_id) as min_tenant_id,
    MAX(t.tenant_id) as max_tenant_id
FROM tenant t
JOIN object o ON t.object_type_id = o.object_type_id
GROUP BY o.object_type_id, o.object_type
ORDER BY tenant_count DESC;

-- =============================================================================
-- 8. READING RELATIONSHIPS (via sm_usage)
-- =============================================================================

-- Discover how readings connect to other entities
-- This is critical for understanding which readings are used for billing
SELECT 
    'reading_to_sm_usage' as relationship_type,
    COUNT(DISTINCT r.reading_id) as readings_with_usage,
    COUNT(DISTINCT su.sm_usage_id) as usage_records,
    MIN(r.reading_id) as min_reading_id,
    MAX(r.reading_id) as max_reading_id
FROM reading r
JOIN sm_usage su ON r.reading_id = su.reading_id;

-- Check readings without sm_usage (candidates for deletion)
SELECT 
    'reading_without_usage' as relationship_type,
    COUNT(*) as orphaned_readings,
    MIN(r.reading_id) as min_reading_id,
    MAX(r.reading_id) as max_reading_id
FROM reading r
LEFT JOIN sm_usage su ON r.reading_id = su.reading_id
WHERE su.reading_id IS NULL;

-- =============================================================================
-- 9. LOGICAL UNIT HIERARCHY
-- =============================================================================

-- Discover logical unit parent-child relationships
SELECT 
    'logical_unit_hierarchy' as relationship_type,
    COUNT(*) as child_units,
    COUNT(DISTINCT logical_unit_parent_id) as parent_units,
    MIN(logical_unit_id) as min_child_id,
    MAX(logical_unit_id) as max_child_id
FROM community_logical_unit
WHERE logical_unit_parent_id IS NOT NULL;

-- =============================================================================
-- 10. INVOICE DETAIL RELATIONSHIPS
-- =============================================================================

-- Discover how invoice details connect to other entities via object_id
SELECT 
    o.object_type,
    COUNT(*) as invoice_detail_count,
    MIN(id.invoice_detail_id) as min_detail_id,
    MAX(id.invoice_detail_id) as max_detail_id
FROM invoice_detail id
JOIN object o ON id.object_type_id = o.object_type_id
GROUP BY o.object_type_id, o.object_type
ORDER BY invoice_detail_count DESC;

-- =============================================================================
-- 11. SUBSCRIPTION RELATIONSHIPS
-- =============================================================================

-- Discover subscription to contact relationships
SELECT 
    'subscription_to_contact' as relationship_type,
    COUNT(*) as subscription_count,
    COUNT(DISTINCT contact_id) as unique_contacts,
    MIN(subscription_id) as min_subscription_id,
    MAX(subscription_id) as max_subscription_id
FROM subscription;

-- =============================================================================
-- 12. BATCH RELATIONSHIPS
-- =============================================================================

-- Discover batch to contact relationships
SELECT 
    'batch_to_contact' as relationship_type,
    COUNT(*) as batch_contact_count,
    COUNT(DISTINCT batch_id) as unique_batches,
    COUNT(DISTINCT contact_id) as unique_contacts
FROM contact_batch;

-- =============================================================================
-- 13. SUMMARY: ALL POLYMORPHIC TABLES
-- =============================================================================

-- List all tables that use polymorphic relationships
SELECT 
    table_name,
    'Uses polymorphic pattern (object_id + object_type_id)' as notes
FROM information_schema.columns 
WHERE table_schema = DATABASE()
AND column_name = 'object_id'
AND table_name IN (
    SELECT table_name 
    FROM information_schema.columns 
    WHERE table_schema = DATABASE()
    AND column_name = 'object_type_id'
)
ORDER BY table_name;

