# Next Steps for NES Database Cleanup

## Current Status ✅

We have successfully completed the foundational work for the NES database cleanup project:

### ✅ Completed
1. **Comprehensive Plan** - Revised for massive scale (500M+ rows)
2. **ID-Based Deletion Approach** - Eliminates staging table overhead
3. **Correct Community Logic** - Uses actual contact types and ZY name prefix
4. **Foreign Key Analysis** - Mapped explicit and implicit relationships
5. **EAV Discovery Queries** - Ready to map polymorphic relationships
6. **Deletion Order Strategy** - Proper dependency management
7. **Enhanced Batch Deleter** - Handles polymorphic cascading

## Immediate Next Steps 🎯

### Step 1: Run Discovery Queries (READ-ONLY)
**Priority: HIGH - Safe to run on production**

```bash
# Connect to production database
mysql -h 198.91.25.229 -u root -p'SecureRootPass123!' nes

# Run discovery queries to understand the data structure
source sql/discover-eav-relationships.sql
source sql/analyze-deletion-dependencies.sql
```

**Purpose**: 
- Map all polymorphic relationships
- Understand object types and their usage
- Validate our deletion order assumptions
- Get actual counts for planning

### Step 2: Test Cutoff Identification
**Priority: HIGH - Safe to run on production**

```bash
export DB_PASSWORD="SecureRootPass123!"
./scripts/run_cleanup.sh identify
```

**Purpose**:
- Get actual cutoff IDs for each table
- Estimate deletion volumes
- Validate community identification logic
- Generate baseline report

### Step 3: Validate Enhanced Deletion Logic
**Priority: MEDIUM - Test on database copy first**

```bash
# Test the enhanced batch deleter on a database copy
./scripts/enhanced_batch_deleter.py --dry-run --cutoff-config cutoff_report.json
```

**Purpose**:
- Validate polymorphic cascade deletion
- Test dependency order logic
- Ensure no referential integrity violations

## Detailed Action Plan

### Phase 1: Data Discovery (This Week)
**Estimated Time: 2-3 hours**

1. **Run EAV Discovery Queries**
   - Execute `discover-eav-relationships.sql` on production
   - Document all polymorphic relationships found
   - Map object types to actual usage patterns

2. **Run Dependency Analysis**
   - Execute `analyze-deletion-dependencies.sql` on production
   - Validate deletion order assumptions
   - Identify any missing dependencies

3. **Test Cutoff Identification**
   - Run cutoff identifier on production (read-only)
   - Review estimated deletion volumes
   - Validate community identification finds correct records

**Deliverables**:
- Complete polymorphic relationship mapping
- Validated deletion order strategy
- Baseline cutoff report with actual numbers

### Phase 2: Enhanced Testing (Next Week)
**Estimated Time: 1-2 days**

1. **Database Copy Testing**
   - Create a copy of production database
   - Test enhanced batch deleter on copy
   - Validate polymorphic cascade deletion works correctly

2. **Performance Testing**
   - Test different batch sizes
   - Measure deletion rates and system impact
   - Optimize batch sizes for production

3. **Interruption Testing**
   - Test graceful shutdown and resumption
   - Validate transaction rollback on errors
   - Ensure no partial deletions occur

**Deliverables**:
- Validated enhanced deletion logic
- Optimized batch sizes for production
- Confirmed resumption capability

### Phase 3: Production Pilot (Following Week)
**Estimated Time: 2-3 days**

1. **Start with Readings Table**
   - Safest table to start with (least dependencies)
   - Largest volume (good test of performance)
   - Easy to validate (check sm_usage references)

2. **Small Batch Pilot**
   - Start with very small batches (1,000 records)
   - Monitor system performance impact
   - Validate space reclamation occurs

3. **Gradual Scale-Up**
   - Increase batch sizes based on performance
   - Process larger volumes as confidence builds
   - Monitor for any unexpected issues

**Deliverables**:
- Proven deletion process on production
- Optimized operational parameters
- Documented procedures for full rollout

### Phase 4: Full Production Rollout
**Estimated Time: 1-2 weeks**

1. **Complete Readings Cleanup**
   - Process all non-billing readings older than 2 years
   - Expected: 200M+ records deleted

2. **Community Cleanup**
   - Process closed and ZY communities older than 7 years
   - Include all polymorphic dependencies

3. **Account Cleanup**
   - Process inactive accounts older than 7 years
   - Include all related data (addresses, phones, emails, etc.)

**Deliverables**:
- Significant database size reduction (30-50% expected)
- Improved system performance
- Established ongoing cleanup procedures

## Risk Mitigation

### Technical Risks
1. **Polymorphic Relationship Errors**
   - Mitigation: Comprehensive testing on database copy
   - Validation: Dry-run mode with detailed logging

2. **Performance Impact**
   - Mitigation: Small batch sizes and monitoring
   - Validation: Gradual scale-up approach

3. **Data Integrity Issues**
   - Mitigation: Transaction-based deletion with rollback
   - Validation: Comprehensive dependency analysis

### Operational Risks
1. **Accidental Data Loss**
   - Mitigation: Full database backup before starting
   - Validation: Conservative identification logic

2. **System Downtime**
   - Mitigation: Off-peak processing and small batches
   - Validation: Performance testing on copy

3. **Process Interruption**
   - Mitigation: Resumable processing design
   - Validation: Interruption testing

## Success Metrics

### Technical Metrics
- **Database Size Reduction**: Target 30-50% reduction
- **Performance Impact**: <5% during processing
- **Error Rate**: <0.1% of processed records
- **Processing Rate**: 10,000+ records/minute sustained

### Business Metrics
- **Storage Cost Savings**: Significant reduction in storage costs
- **System Performance**: Improved query performance
- **Maintenance Efficiency**: Faster backups and maintenance
- **Compliance**: Proper data retention compliance

## Tools and Scripts Ready

### Discovery and Analysis
- ✅ `discover-eav-relationships.sql` - Map polymorphic relationships
- ✅ `analyze-deletion-dependencies.sql` - Validate deletion order
- ✅ `check_contact_types.py` - Analyze contact type usage

### Identification and Planning
- ✅ `cutoff_identifier.py` - Identify deletion cutoffs
- ✅ `identify-cutoffs.sql` - Manual cutoff queries
- ✅ `run_cleanup.sh` - Orchestration script

### Deletion and Processing
- ✅ `enhanced_batch_deleter.py` - Polymorphic-aware deletion
- ✅ `batch_deleter.py` - Original batch deletion framework
- ✅ Configuration and logging infrastructure

## Immediate Action Required

**TODAY**: Run the discovery queries to complete our understanding of the database structure.

**THIS WEEK**: Execute cutoff identification to get actual numbers and validate our logic.

**NEXT WEEK**: Begin testing on database copy to validate enhanced deletion logic.

The foundation is solid and comprehensive. We're ready to move to production discovery and testing phases.

