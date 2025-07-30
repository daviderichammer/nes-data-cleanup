# NES Data Cleanup - Todo List

## Phase 1: Discovery and Safety
- [x] Create full database backup procedure
- [x] Map all foreign key constraints
- [x] Identify implicit relationships in EAV model
- [x] Document deletion order dependencies

## Phase 2: ID Cutoff Identification (REVISED APPROACH)
- [x] Create SQL scripts to identify ID cutoffs
- [x] Implement Python script for cutoff identification
- [x] Add safety validation for cutoffs
- [x] Create comprehensive cutoff reporting

## Phase 3: Batch Deletion Implementation
- [x] Design batch deletion strategy using ID ranges
- [x] Implement Python batch deletion framework
- [x] Add transaction control and error handling
- [x] Create deletion logging infrastructure
- [x] Implement resumable deletion process

## Phase 4: Scripting and Automation
- [x] Create Python script framework
- [x] Implement configuration management
- [x] Add comprehensive logging
- [x] Implement dry-run mode
- [x] Add safety thresholds and validation
- [x] Create orchestration shell script
- [x] Add progress monitoring and reporting

## Testing and Validation
- [ ] Unit tests for identification logic
- [ ] Integration tests on database copy
- [ ] Safety threshold testing
- [ ] Dry-run validation
- [ ] Performance testing

## Deployment
- [ ] Production dry-run cycles
- [ ] Gradual rollout with small batches
- [ ] Monitoring and alerting setup
- [ ] Documentation for operations team

## Completed
- [x] Create comprehensive data deletion plan
- [x] Set up GitHub repository
- [x] Initial project documentation


## Testing and Validation
- [ ] Test cutoff identification on production database (read-only)
- [ ] Validate batch deletion logic on database copy
- [ ] Test resumption capability after interruption
- [ ] Performance testing with different batch sizes
- [ ] Validate safety thresholds and error handling

## Production Deployment
- [ ] Run cutoff identification on production
- [ ] Perform comprehensive dry-run validation
- [ ] Start with small batch sizes on non-critical tables
- [ ] Monitor system performance impact during deletion
- [ ] Validate database size reduction and space reclamation

## Documentation and Handover
- [ ] Create operational runbook
- [ ] Document troubleshooting procedures
- [ ] Create monitoring and alerting setup
- [ ] Train operations team on script usage

## Completed Major Milestones
- [x] ✅ **MAJOR REVISION**: Switched from staging tables to ID-based deletion approach
- [x] ✅ Created comprehensive revised plan for massive scale datasets
- [x] ✅ Implemented complete cutoff identification system
- [x] ✅ Built robust batch deletion framework with safety features
- [x] ✅ Added resumable processing and comprehensive logging
- [x] ✅ Created user-friendly orchestration scripts
- [x] ✅ **CONTACT TYPE FIX**: Fixed community identification logic to use flexible pattern matching instead of hardcoded 'zy' type
- [x] ✅ **FINAL COMMUNITY LOGIC**: Updated to use actual contact types (Client/Prospect/Closed) and ZY name prefix without LIKE operators for performance

## Next Steps
1. **Test on Production (Read-Only)**: Run cutoff identification to get actual numbers
2. **Validate Approach**: Perform dry-run to validate deletion logic
3. **Gradual Rollout**: Start with readings table (largest, safest to test)
4. **Monitor and Optimize**: Adjust batch sizes based on performance
5. **Full Deployment**: Process all tables according to dependency order

