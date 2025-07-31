# Production Deletion Strategy

## Based on Discovery Analysis Results

The discovery queries have revealed the actual scale and relationships in the NES database. This document outlines the production-ready deletion strategy.

## Key Findings Summary

### Massive Volumes Discovered
- **Addresses**: 67+ million polymorphic records (largest impact)
- **Phones**: 5.9+ million polymorphic records  
- **Emails**: 6.4+ million polymorphic records
- **Notes**: 3.2+ million polymorphic records

### Object Type Distribution
- **dstTenant** (94): 1.18M contacts - LARGEST GROUP with massive dependencies
- **dstCommunity** (49): 3,594 contacts - OUR PRIMARY TARGET
- **dstContact** (1): 809 contacts
- **dstAdditionalContact** (2): 4,457 contacts

## Production Deletion Plan

### Phase 1: Community Cleanup (RECOMMENDED START)
**Why Start Here**: Smallest volume, safest to test, clear business case

**Target**: Communities with object_type_id = 49
- Contact type = 'Closed' OR name starts with 'ZY'
- No activity for 7+ years

**Expected Deletion Volume**:
- 3,594 community contacts
- 10,783 addresses
- 17,970 phones  
- 3,599 notes
- **Total**: ~36,000 records

**Estimated Time**: 1-2 hours
**Risk Level**: LOW

### Phase 2: Reading Cleanup (LARGEST VOLUME)
**Why Second**: Independent of other deletions, massive space savings

**Target**: Non-billing readings older than 2 years
- NOT referenced in sm_usage table
- reading_date < 2 years ago

**Expected Deletion Volume**:
- 200+ million reading records (estimated)

**Estimated Time**: 1-2 days
**Risk Level**: LOW (independent table)

### Phase 3: Tenant Cleanup (MASSIVE IMPACT)
**Why Last**: Enormous volume, requires careful monitoring

**Target**: Inactive tenants with object_type_id = 94
- No activity for 7+ years
- Comprehensive dependency checks

**Expected Deletion Volume**:
- 1.18M tenant contacts
- 3.5M addresses
- 5.9M phones
- 1.2M notes
- 29K emails
- **Total**: ~11.8 million records

**Estimated Time**: 1-2 weeks
**Risk Level**: MEDIUM (large volume)

## Batch Size Strategy

### Optimized for Actual Volumes
```python
BATCH_SIZES = {
    'address': 500,      # 67M+ records - smallest batches for safety
    'phone': 1000,       # 5.9M+ records
    'email': 1000,       # 6.4M+ records  
    'note': 2000,        # 3.2M+ records
    'contact': 100,      # Process contacts carefully
    'reading': 10000,    # Large batches for independent readings
}
```

### Performance Monitoring
- **Progress reporting**: Every 1,000 batches
- **Performance metrics**: Records/second, batch duration
- **System monitoring**: CPU, memory, disk I/O during deletion
- **Database monitoring**: Lock waits, replication lag

## Safety Measures

### 1. Conservative Identification
- Multiple activity checks for each entity
- Cross-validation of cutoff safety
- Explicit confirmation required for each phase

### 2. Batch Processing Safety
- Small batch sizes prevent long-running transactions
- Transaction rollback on any error within a batch
- Resumable processing from last completed batch
- Graceful shutdown on interruption signals

### 3. Volume-Based Precautions
- **Address table**: Extra small batches (500 records) due to 67M volume
- **Phone table**: Moderate batches (1,000 records) for 5.9M volume
- **Progress monitoring**: Frequent status updates for large operations
- **Time estimates**: Realistic expectations for multi-day operations

## Implementation Commands

### Phase 1: Community Cleanup
```bash
# 1. Identify cutoffs
export DB_PASSWORD="SecureRootPass123!"
./scripts/run_cleanup.sh identify

# 2. Dry run validation
./scripts/run_cleanup.sh dry-run cutoff_report_file.json

# 3. Execute community cleanup only
./scripts/run_cleanup.sh execute cutoff_report_file.json community
```

### Phase 2: Reading Cleanup
```bash
# Execute reading cleanup only
./scripts/run_cleanup.sh execute cutoff_report_file.json reading
```

### Phase 3: Tenant Cleanup
```bash
# Execute all remaining contact types (including tenants)
./scripts/run_cleanup.sh execute cutoff_report_file.json contact
```

## Expected Results

### Database Size Reduction
- **Phase 1**: ~36K records (minimal size impact, validates process)
- **Phase 2**: ~200M records (major size reduction from readings)
- **Phase 3**: ~11.8M records (significant reduction from polymorphic data)
- **Total**: 30-50% database size reduction expected

### Performance Impact
- **During deletion**: 5-10% performance impact during processing
- **After deletion**: Improved query performance, faster backups
- **Storage**: Significant reduction in storage costs

## Risk Mitigation

### Technical Risks
1. **Large Volume Processing**
   - Mitigation: Small batch sizes, frequent commits
   - Monitoring: Progress tracking, performance metrics

2. **Polymorphic Relationship Errors**
   - Mitigation: Comprehensive testing on database copy first
   - Validation: Dry-run mode with detailed logging

3. **System Performance Impact**
   - Mitigation: Off-peak processing, batch size tuning
   - Monitoring: Real-time system metrics

### Operational Risks
1. **Data Integrity**
   - Mitigation: Transaction-based deletion with rollback
   - Validation: Comprehensive dependency analysis

2. **Process Interruption**
   - Mitigation: Resumable processing design
   - Recovery: Detailed logging of progress state

## Success Metrics

### Technical Metrics
- **Deletion Rate**: Target 10,000+ records/minute sustained
- **Error Rate**: <0.1% of processed batches
- **System Impact**: <10% performance degradation during processing
- **Space Reclamation**: Immediate space recovery after deletion

### Business Metrics
- **Storage Savings**: 30-50% database size reduction
- **Performance Improvement**: Faster queries and backups
- **Compliance**: Proper data retention adherence
- **Operational Efficiency**: Reduced maintenance overhead

## Next Steps

### Immediate (This Week)
1. **Run cutoff identification** to get actual numbers
2. **Test on database copy** to validate deletion logic
3. **Start with Phase 1** (community cleanup) as pilot

### Short Term (Next 2 Weeks)
1. **Complete Phase 1** and validate results
2. **Execute Phase 2** (reading cleanup) for major space savings
3. **Monitor and optimize** batch sizes based on performance

### Long Term (Following Month)
1. **Execute Phase 3** (tenant cleanup) with careful monitoring
2. **Establish ongoing procedures** for regular cleanup
3. **Document lessons learned** for future maintenance

The production strategy is now based on **actual data volumes and relationships**, ensuring realistic expectations and appropriate safety measures for the massive scale involved.

