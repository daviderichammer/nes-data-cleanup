# Foreign Key and Dependency Analysis

## Overview
This document analyzes the foreign key relationships and implicit EAV dependencies in the NES database to determine the proper deletion order for the cleanup process.

## Explicit Foreign Key Relationships

Based on the foreign key analysis, here are the key relationships that affect our deletion strategy:

### 1. Contact Dependencies
**Tables that reference `contact.contact_id`:**
- `bank.contact_id` → `contact.contact_id`
- `subscription.contact_id` → `contact.contact_id`
- `contact_batch.contact_id` → `contact.contact_id`
- `contact_logical_unit.contact_id` → `contact.contact_id`
- `nes_anet_customer_profile.contact_id` → `contact.contact_id`

### 2. Batch Dependencies
**Tables that reference `batch.batch_id`:**
- `batch_detail.batch_id` → `batch.batch_id`
- `contact_batch.batch_id` → `batch.batch_id`
- `sm_batch.batch_id` → `batch.batch_id`
- `sm_closeout.batch_id` → `batch.batch_id`
- `third_party_batch.batch_id` → `batch.batch_id`

### 3. Invoice Dependencies
**Tables that reference `invoice.invoice_id`:**
- `invoice_detail.invoice_id` → `invoice.invoice_id`
- `itemized_bill_data.invoice_id` → `invoice.invoice_id`

### 4. Email Dependencies
**Tables that reference `email.email_id`:**
- `email_attachment.email_id` → `email.email_id`
- `email_preview.email_id` → `email.email_id`

### 5. Logical Unit Dependencies
**Tables that reference `community_logical_unit.logical_unit_id`:**
- `community_logical_unit_attribute.logical_unit_id` → `community_logical_unit.logical_unit_id`
- `contact_logical_unit.logical_unit_id` → `community_logical_unit.logical_unit_id`
- `subscription_logical_unit.logical_unit_id` → `community_logical_unit.logical_unit_id`
- `sm_gun_content.logical_unit_id` → `community_logical_unit.logical_unit_id`
- `sm_work_order.logical_unit_id` → `community_logical_unit.logical_unit_id`

## Implicit EAV Relationships (Polymorphic)

The database uses an Entity-Attribute-Value (EAV) pattern with polymorphic relationships via `object_id` + `object_type_id` pairs. These are **not enforced by foreign keys** but are critical for data integrity.

### Tables Using Polymorphic Pattern:
- `contact` (references various entity types via `object_id` + `object_type_id`)
- `email` (can be linked to contacts, tenants, etc.)
- `address` (can be linked to contacts, properties, etc.)
- `phone` (can be linked to contacts, properties, etc.)
- `note` (can be linked to any entity type)
- `tenant` (linked to contacts or properties)
- `invoice_detail` (can reference various billable entities)

### Object Types Discovery Needed:
We need to run discovery queries to understand:
1. What object types exist in the `object` table
2. Which polymorphic tables reference contacts (object_type = 'Contact')
3. Which polymorphic tables reference other entities we might delete

## Critical Relationships for Cleanup

### 1. Reading → sm_usage Relationship
```sql
reading.reading_id → sm_usage.reading_id
```
**Critical**: Only delete readings that are NOT referenced in `sm_usage` (not used for billing)

### 2. Contact Polymorphic References
When deleting a contact, we must also delete:
- `email` records where `object_type_id` = Contact type AND `object_id` = contact_id
- `address` records where `object_type_id` = Contact type AND `object_id` = contact_id  
- `phone` records where `object_type_id` = Contact type AND `object_id` = contact_id
- `note` records where `object_type_id` = Contact type AND `object_id` = contact_id
- `tenant` records where `object_type_id` = Contact type AND `object_id` = contact_id

## Proposed Deletion Order

Based on the dependency analysis, here's the safe deletion order:

### Level 1: Leaf Tables (No Dependencies)
Delete first - these tables only reference others, nothing references them:
- `email_attachment`
- `email_preview` 
- `invoice_detail`
- `itemized_bill_data`
- `tender`
- `work_order_attribute`
- `community_logical_unit_attribute`

### Level 2: Dependent Tables
Delete second - these depend on Level 1 or lookup tables:
- `email` (polymorphic - after email_attachment/preview)
- `address` (polymorphic)
- `phone` (polymorphic)
- `note` (polymorphic)
- `tenant` (polymorphic)
- `reading` (non-billing only)
- `subscription_component`
- `subscription_logical_unit`

### Level 3: Core Business Entities
Delete third - these have dependencies but are referenced by Level 2:
- `invoice` (after invoice_detail)
- `subscription` (after subscription_component)
- `batch_detail`
- `contact_batch`

### Level 4: Primary Entities
Delete fourth - these are heavily referenced:
- `batch` (after all batch dependencies)
- `journal_entry` (after invoice/tender)

### Level 5: Master Entities
Delete last - these are the main entities:
- `contact` (after all polymorphic and direct dependencies)
- `community_logical_unit` (after all logical unit dependencies)

## Safety Validation Required

Before implementing deletion, we need to:

1. **Run EAV Discovery Queries** to map all polymorphic relationships
2. **Validate Object Types** to understand the `object` table structure
3. **Test Dependency Chains** on a small dataset first
4. **Implement Cascade Logic** for polymorphic relationships
5. **Add Orphan Cleanup** for records referencing deleted entities

## Implementation Strategy

### Phase 1: Discovery
- Run `discover-eav-relationships.sql` to map all implicit relationships
- Identify all object types and their usage patterns
- Create comprehensive dependency mapping

### Phase 2: Validation
- Run `analyze-deletion-dependencies.sql` on sample data
- Validate that our deletion order doesn't break referential integrity
- Test cascade deletion logic for polymorphic relationships

### Phase 3: Implementation
- Update batch deletion scripts to handle proper deletion order
- Implement polymorphic cascade deletion
- Add comprehensive validation before each deletion batch

## Next Steps

1. **Run Discovery Queries** on production database (read-only)
2. **Analyze Results** to complete the dependency mapping
3. **Update Deletion Scripts** to handle proper order and cascading
4. **Test on Database Copy** before production implementation

This analysis ensures we maintain data integrity while achieving maximum space savings through the cleanup process.

