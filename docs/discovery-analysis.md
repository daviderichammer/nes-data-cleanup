# Discovery Query Analysis Results

## Overview
The discovery queries have revealed the actual polymorphic relationships in the NES database. This analysis provides critical insights for updating our deletion strategy.

## Key Findings

### 1. Object Types and Their Usage

Based on the discovery results, here are the key object types and their usage patterns:

#### Contact Table Object Types
- **dstTenant** (94): 1,182,520 contacts - **LARGEST GROUP**
- **dstAdditionalContact** (2): 4,457 contacts
- **dstCommunity** (49): 3,594 contacts - **OUR TARGET FOR COMMUNITY CLEANUP**
- **dstSmOwner** (110): 1,406 contacts
- **dstContact** (1): 809 contacts
- **dstUser** (5): 575 contacts
- **dstServiceProvider** (44): 167 contacts
- **dstLogicalUnit** (41): 3 contacts

#### Email Polymorphic Relationships
- **dstInvoice** (71): 6,337,666 emails - **MASSIVE VOLUME**
- **dstTenant** (94): 29,341 emails
- **dstFundingBatch** (117): 110 emails
- **dstContact** (1): 10 emails

#### Address Polymorphic Relationships
- **dstInvoice** (71): 67,162,916 addresses - **ENORMOUS VOLUME**
- **dstTenant** (94): 3,547,560 addresses
- **dstSmTenantActivity** (109): 1,745,568 addresses
- **dstBill** (115): 26,163 addresses
- **dstCommunity** (49): 10,783 addresses
- **dstSmOwner** (110): 4,218 addresses
- **dstContact** (1): 2,427 addresses

#### Phone Polymorphic Relationships
- **dstTenant** (94): 5,912,600 phones - **HUGE VOLUME**
- **dstCommunity** (49): 17,970 phones
- **dstSmOwner** (110): 7,030 phones
- **dstAdditionalContact** (2): 5,164 phones
- **dstContact** (1): 4,050 phones

#### Note Polymorphic Relationships
- **dstContactNote** (3): 1,958,994 notes - **LARGEST GROUP**
- **dstTenant** (94): 1,184,463 notes
- **dstCycleNote** (118): 82,760 notes
- **dstCommunity** (49): 3,599 notes
- **dstContact** (1): 808 notes

## Critical Insights for Deletion Strategy

### 1. **Community Cleanup Impact**
When deleting communities (object_type_id = 49), we need to cascade delete:
- **10,783 addresses** linked to communities
- **17,970 phones** linked to communities  
- **3,599 notes** linked to communities

### 2. **Tenant Cleanup Impact** 
Tenants (object_type_id = 94) have **MASSIVE** polymorphic dependencies:
- **3,547,560 addresses** - This is huge!
- **5,912,600 phones** - Even bigger!
- **1,184,463 notes** - Substantial
- **29,341 emails** - Moderate

### 3. **Invoice/Address Relationship**
The largest polymorphic relationship is **dstInvoice → address** with **67+ million records**. This suggests addresses are heavily used for billing/invoice purposes.

### 4. **Missing Polymorphic Tables**
Some tables we expected to have polymorphic relationships don't appear in the results, suggesting they either:
- Don't use the polymorphic pattern as expected
- Have different column names
- Are not actively used

## Updated Deletion Strategy

### Phase 1: Community Cleanup (Safest Start)
**Target**: Communities with object_type_id = 49
**Estimated Impact**:
- 3,594 community contacts
- 10,783 addresses
- 17,970 phones
- 3,599 notes
- **Total**: ~36,000 records

### Phase 2: Tenant Cleanup (Massive Impact)
**Target**: Inactive tenants with object_type_id = 94
**Estimated Impact**:
- 1,182,520 tenant contacts
- 3,547,560 addresses
- 5,912,600 phones
- 1,184,463 notes
- 29,341 emails
- **Total**: ~11.8 million records

### Phase 3: Other Contact Types
**Target**: Other inactive contact types
**Estimated Impact**: Varies by type

## Revised Deletion Order

Based on the actual data volumes, here's the updated deletion order:

### Level 1: Polymorphic Dependencies (Largest Impact)
1. **Addresses** (67M+ records) - Delete by object_type_id and object_id
2. **Phones** (5.9M+ records) - Delete by object_type_id and object_id
3. **Notes** (3.2M+ records) - Delete by object_type_id and object_id
4. **Emails** (6.4M+ records) - Delete by object_type_id and object_id

### Level 2: Direct Dependencies
1. Email attachments (via email_id)
2. Email previews (via email_id)
3. Subscription components
4. Contact batches

### Level 3: Core Entities
1. Subscriptions
2. Batches
3. Invoices (careful - heavily used)

### Level 4: Master Entities
1. Contacts (by object_type_id)
2. Logical units

## Performance Considerations

### 1. **Massive Volumes Identified**
- **Addresses**: 67M+ records (largest table impact)
- **Phones**: 5.9M+ records
- **Emails**: 6.4M+ records
- **Notes**: 3.2M+ records

### 2. **Batch Size Recommendations**
- **Addresses**: 500-1,000 per batch (largest volume)
- **Phones**: 1,000-2,000 per batch
- **Emails**: 1,000-2,000 per batch
- **Notes**: 2,000-5,000 per batch

### 3. **Processing Time Estimates**
- **Community cleanup**: ~1-2 hours
- **Tenant cleanup**: ~2-3 days (massive volume)
- **Full cleanup**: ~1-2 weeks

## Object Type Mapping for Scripts

```python
OBJECT_TYPE_MAPPING = {
    'dstTenant': 94,
    'dstCommunity': 49,
    'dstContact': 1,
    'dstAdditionalContact': 2,
    'dstUser': 5,
    'dstSmOwner': 110,
    'dstServiceProvider': 44,
    'dstLogicalUnit': 41,
    'dstInvoice': 71,
    'dstContactNote': 3,
    'dstCycleNote': 118,
    # Add others as needed
}
```

## Next Steps

1. **Update Enhanced Batch Deleter** with actual object type IDs
2. **Implement Volume-Based Batch Sizing** for different table types
3. **Add Progress Monitoring** for massive deletion operations
4. **Test on Database Copy** with actual volumes
5. **Start with Community Cleanup** (smallest, safest volume)

This analysis shows that our deletion strategy needs to handle **much larger volumes** than initially estimated, particularly for polymorphic relationships. The tenant cleanup alone will involve nearly 12 million records across multiple tables.

