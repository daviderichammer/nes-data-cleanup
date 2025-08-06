# Additional Tables Analysis for Cleanup

## Overview
Analysis of additional tables mentioned by the user to determine which ones should be included in the cleanup strategy based on size, purpose, and cleanup potential.

## Large Tables Worth Considering

### **HIGH PRIORITY - Large Space Savings**

#### 1. **email_attachment** - 420 GB (!!)
- **Size**: 420,254 MB (6.2M rows)
- **Cleanup Potential**: MASSIVE - largest table by far
- **Strategy**: Delete attachments for emails older than X years
- **Dependencies**: Links to email table via email_id
- **Impact**: Could save 400+ GB of space

#### 2. **subscription_invoice_detail_1** - 11.7 GB
- **Size**: 11,737 MB (136.5M rows) 
- **Cleanup Potential**: HIGH - appears to be a duplicate/backup table
- **Strategy**: Analyze relationship to main subscription_invoice_detail table
- **Impact**: Could save 11+ GB if it's redundant data

#### 3. **email** - 17.2 GB
- **Size**: 17,159 MB (8.6M rows)
- **Cleanup Potential**: HIGH - already in our polymorphic deletion strategy
- **Strategy**: Delete emails for inactive contacts/entities
- **Dependencies**: Has email_attachment and email_preview dependencies

#### 4. **log** - 4.1 GB
- **Size**: 4,058 MB (21.1M rows)
- **Cleanup Potential**: HIGH - log data is typically safe to purge
- **Strategy**: Delete logs older than 1-2 years
- **Impact**: 4+ GB space savings

#### 5. **email_preview** - 3.1 GB
- **Size**: 3,104 MB (11.8M rows)
- **Cleanup Potential**: HIGH - preview data can be regenerated
- **Strategy**: Delete previews for old emails
- **Dependencies**: Links to email table via email_id

### **MEDIUM PRIORITY - Moderate Space Savings**

#### 6. **third_party_api_responses** - 2.8 GB
- **Size**: 2,839 MB (68K rows)
- **Cleanup Potential**: MEDIUM - API response cache
- **Strategy**: Delete responses older than 6-12 months
- **Note**: Very large per-row size (41 MB average!)

#### 7. **email_tracking** - 1.5 GB
- **Size**: 1,475 MB (8.7M rows)
- **Cleanup Potential**: MEDIUM - tracking data for analytics
- **Strategy**: Delete tracking data older than 1-2 years

#### 8. **barcode_serial_number** - 1.2 GB
- **Size**: 1,207 MB (16.7M rows)
- **Cleanup Potential**: MEDIUM - depends on business requirements
- **Strategy**: Delete old/inactive barcode data

#### 9. **nes_portal_translog** - 969 MB
- **Size**: 969 MB (572K rows)
- **Cleanup Potential**: MEDIUM - transaction logs
- **Strategy**: Delete logs older than 1-2 years

#### 10. **token** - 567 MB
- **Size**: 567 MB (3.2M rows)
- **Cleanup Potential**: MEDIUM - authentication tokens
- **Strategy**: Delete expired/old tokens

### **LOW PRIORITY - Small Tables**

#### 11. **third_party_api_requests** - 420 MB
- **Size**: 420 MB (32K rows)
- **Cleanup Potential**: LOW-MEDIUM - API request logs
- **Strategy**: Delete old request logs

#### 12. **nes_login** - 325 MB
- **Size**: 325 MB (1.8M rows)
- **Cleanup Potential**: LOW-MEDIUM - login audit logs
- **Strategy**: Delete old login records

#### 13. **imported_charge_queue** - 86 MB
- **Size**: 86 MB (591K rows)
- **Cleanup Potential**: LOW - processing queue
- **Strategy**: Delete processed/old queue items

#### 14. **late_notification_log_detail** - 78 MB
- **Size**: 78 MB (1.3M rows)
- **Cleanup Potential**: LOW - notification logs
- **Strategy**: Delete old notification logs

#### 15. **third_party_batch_message** - 134 MB
- **Size**: 134 MB (8K rows)
- **Cleanup Potential**: LOW - batch processing messages
- **Strategy**: Delete old batch messages

## Tables NOT Worth Cleanup (Too Small)

These tables are very small and not worth the effort:
- **third_party_payments** - 0.47 MB
- **third_party_batch_detail** - 5.48 MB  
- **tmp_gsheet** - 0.44 MB
- **third_party_batch** - 0.55 MB
- **third_party_batch_result** - 0.26 MB

## Recommended Cleanup Strategy

### **Phase 1: Massive Impact (400+ GB potential)**
1. **email_attachment** - Delete attachments for emails older than 2-3 years
   - Potential savings: 300-400 GB
   - Strategy: Join with email table, check email dates and polymorphic relationships

### **Phase 2: High Impact (20+ GB potential)**
2. **subscription_invoice_detail_1** - Investigate if this is redundant data
3. **log** - Delete logs older than 1-2 years  
4. **email_preview** - Delete previews for old emails
5. **third_party_api_responses** - Delete old API responses

### **Phase 3: Medium Impact (5+ GB potential)**
6. **email_tracking** - Delete old tracking data
7. **barcode_serial_number** - Delete inactive barcode data (if business allows)
8. **nes_portal_translog** - Delete old transaction logs
9. **token** - Delete expired tokens

## Implementation Considerations

### **Dependencies to Handle**
- **email_attachment** → **email** (via email_id)
- **email_preview** → **email** (via email_id)  
- **email_tracking** → **email** (via email_id)

### **Business Logic Checks**
- **Audit requirements**: How long must logs be retained?
- **Legal requirements**: Any regulatory retention periods?
- **Operational needs**: Are old API responses needed for debugging?

### **Safety Measures**
- **Start with logs and cache data** (safest)
- **Test attachment deletion** on small subset first
- **Verify backup procedures** before large deletions

## Estimated Total Impact

**Conservative Estimate**:
- email_attachment cleanup: 200-300 GB
- Other tables: 20-30 GB
- **Total potential savings: 220-330 GB**

**Aggressive Estimate**:
- email_attachment cleanup: 350-400 GB
- Other tables: 40-50 GB  
- **Total potential savings: 390-450 GB**

This could represent a **50-70% reduction** in total database size, significantly exceeding our original 30-50% target!

