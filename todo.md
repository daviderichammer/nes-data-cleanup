# NES Data Cleanup - Todo List

## Phase 1: Discovery and Safety
- [ ] Create full database backup procedure
- [ ] Map all foreign key constraints
- [ ] Identify implicit relationships in EAV model
- [ ] Document deletion order dependencies

## Phase 2: Staging and Identification
- [ ] Create staging table schemas
- [ ] Implement stale account identification logic
- [ ] Implement closed community identification logic  
- [ ] Implement old reading identification logic
- [ ] Test identification queries on sample data

## Phase 3: Execution Logic
- [ ] Design deletion order for accounts
- [ ] Design deletion order for communities
- [ ] Implement deletion scripts with transaction control
- [ ] Add safety checks and validation

## Phase 4: Scripting and Automation
- [ ] Create Python script framework
- [ ] Implement configuration management
- [ ] Add comprehensive logging
- [ ] Implement dry-run mode
- [ ] Add safety thresholds
- [ ] Create archiving functionality
- [ ] Set up scheduling and monitoring

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

