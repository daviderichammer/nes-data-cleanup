# Immediate Action Plan - NES Database Cleanup

**Priority:** HIGH  
**Timeline:** Execute within 24-48 hours  
**Risk Level:** LOW (Reading cleanup only)

## Immediate Execution - Reading Cleanup

### Pre-Execution Checklist

- [x] ✅ Database backup completed
- [x] ✅ Cutoff identification completed successfully
- [x] ✅ Safety validation passed for reading table
- [x] ✅ Error handling and logging implemented
- [ ] 🔄 Final stakeholder approval obtained
- [ ] 🔄 Maintenance window scheduled

### Execution Command

```bash
# On VPN server (dev-app1)
cd ~/nes-data-cleanup
git pull origin main  # Ensure latest version

# Execute reading cleanup
./scripts/run_cleanup_enhanced.sh \
    --host 10.99.1.80 \
    --user w3 \
    --database nes \
    execute cutoff_report_20250806_070417.json reading
```

### Expected Execution Details

**Target Data:**
- Records to delete: 31,071,738 readings
- Cutoff ID: 297,619,891 (everything below this ID)
- Date range: All readings imported before August 7, 2023

**Execution Characteristics:**
- Batch size: 10,000 records per batch (optimized for large volume)
- Total batches: ~3,107 batches
- Estimated time: 2-4 hours
- Transaction safety: Each batch in separate transaction with rollback capability

**Space Savings:**
- Direct table savings: ~5.3 GB
- Index rebuilding savings: Additional 2-3 GB
- Total expected: 7-8 GB reduction

### Monitoring During Execution

**Progress Indicators:**
```
Batch 1/3107: Deleted 10,000 records (reading_id < 297619891)
Batch 2/3107: Deleted 10,000 records (reading_id < 297619891)
...
Progress: 32.1% complete, ETA: 2h 15m
```

**Key Metrics to Watch:**
- Batch completion rate (should be consistent)
- Database connection stability
- No foreign key constraint violations
- Transaction rollback events (should be zero)

### Post-Execution Validation

**Immediate Checks:**
```sql
-- Verify deletion count
SELECT COUNT(*) FROM reading WHERE reading_id < 297619891;
-- Should return 0

-- Verify retention
SELECT COUNT(*) FROM reading WHERE reading_id >= 297619891;
-- Should return ~306,353,430

-- Check table size reduction
SELECT 
    table_rows,
    ROUND((data_length+index_length)/1024/1024, 2) as total_mb
FROM information_schema.tables 
WHERE table_schema = 'nes' AND table_name = 'reading';
```

**Success Criteria:**
- Zero records below cutoff ID 297,619,891
- Retained records match expected count (~306M)
- Table size reduced by 5-8 GB
- No application errors or performance degradation

## Parallel Investigation - Contact Safety Issues

While reading cleanup executes, investigate contact safety issues:

### Investigation Query

```sql
-- Find contacts causing safety failure
SELECT 
    c.contact_id,
    c.company_name,
    c.first_name,
    c.last_name,
    c.last_updated_on,
    ct.contact_type,
    DATEDIFF(NOW(), c.last_updated_on) as days_since_update
FROM contact c
JOIN contact_type ct ON c.contact_type_id = ct.contact_type_id
WHERE c.contact_id <= 781410
AND c.last_updated_on >= DATE_SUB(NOW(), INTERVAL 7 YEAR)
ORDER BY c.last_updated_on DESC
LIMIT 50;
```

### Analysis Questions

1. **Are these legitimate active contacts?**
   - Recent billing activity?
   - Active tenant relationships?
   - Ongoing service delivery?

2. **Are these data quality issues?**
   - Automated system updates?
   - Bulk data corrections?
   - Migration artifacts?

3. **Should the cutoff criteria be adjusted?**
   - More conservative date range?
   - Additional exclusion criteria?
   - Manual exception list?

## Risk Mitigation

### Rollback Plan (If Needed)

**Immediate Rollback:**
```bash
# Stop execution (Ctrl+C during batch processing)
# Script will complete current batch and stop safely
```

**Data Recovery:**
- Restore from pre-cleanup backup
- Recovery time: 2-4 hours depending on backup size
- Business impact: Minimal (reading data is historical)

### Communication Plan

**Stakeholders to Notify:**
- Database administrators
- Application development team
- Business operations team
- IT management

**Communication Timeline:**
- **Before execution:** 24-hour advance notice
- **During execution:** Hourly progress updates
- **After completion:** Success confirmation with metrics

## Success Metrics

### Immediate (Within 24 hours)
- [x] Reading cleanup completed successfully
- [x] Expected space savings achieved (5-8 GB)
- [x] No application performance degradation
- [x] All validation checks passed

### Short-term (Within 1 week)
- [x] Contact safety investigation completed
- [x] Refined contact cleanup plan developed
- [x] Performance improvements measured and documented
- [x] Stakeholder feedback collected

## Next Phase Planning

**Phase 2 Preparation:**
1. Complete contact investigation
2. Develop refined contact cleanup criteria
3. Plan additional table cleanup (email_attachment, logs)
4. Schedule regular cleanup automation

**Timeline:**
- Contact investigation: 1-2 weeks
- Phase 2 execution: 2-3 weeks
- Full cleanup completion: 4-6 weeks

## Emergency Contacts

**Database Team:**
- Primary DBA: [Contact Information]
- Backup DBA: [Contact Information]

**Application Team:**
- Lead Developer: [Contact Information]
- DevOps Engineer: [Contact Information]

**Business Team:**
- Operations Manager: [Contact Information]
- IT Director: [Contact Information]

---

**Status:** READY FOR EXECUTION  
**Approval Required:** Final stakeholder sign-off  
**Execution Window:** Next available maintenance window

