# Final Community Identification Logic

## Database Reality
Based on the actual database structure, there are only **3 contact types**:
1. **Client** (contact_type_id = 1)
2. **Prospect** (contact_type_id = 2) 
3. **Closed** (contact_type_id = 3)

## ZY Process Understanding
When a community is "zy'd" (marked for deletion), the process is:
- The community name gets prefixed with "ZY" (e.g., "ZY Original Community Name")
- This puts it at the end of lexicographically sorted lists
- The contact type may or may not be changed to "Closed"

## Final Logic Implementation

### Communities to Delete
We identify communities for deletion using **two criteria**:

1. **Contact Type = 'Closed'** - Communities explicitly marked as closed
2. **Name starts with 'ZY'** - Communities that have been "zy'd"

### Performance Optimization
- **No LIKE operators** - Uses `LEFT(c.contact_name, 2) = 'ZY'` instead of `LIKE 'ZY%'`
- **Direct equality** - Uses `ct.contact_type = 'Closed'` instead of pattern matching
- **Indexed operations** - Both checks use efficient operations that can leverage indexes

### SQL Logic
```sql
WHERE (
    ct.contact_type = 'Closed'           -- Explicitly closed communities
    OR LEFT(c.contact_name, 2) = 'ZY'   -- ZY'd communities (fast, no LIKE)
)
```

### Additional Safety Checks
All communities must also meet these criteria:
- Not updated in 7+ years
- No active tenants in the last 7 years
- No recent batches in the last 7 years  
- No legal hold attributes

## Benefits of This Approach

### Accuracy
- **Covers both closure methods** - explicit closure and ZY process
- **Based on actual data structure** - uses real contact types
- **Handles edge cases** - ZY communities that aren't marked as "Closed"

### Performance
- **No LIKE operators** - avoids slow pattern matching
- **Index-friendly** - uses equality and LEFT() function
- **Minimal overhead** - simple, fast conditions

### Maintainability
- **Clear logic** - easy to understand and modify
- **Well documented** - explains the business process
- **Future-proof** - handles both current and future closure methods

## Testing Recommendations

### Before Running Cleanup
1. **Check ZY communities**: `SELECT COUNT(*) FROM contact WHERE LEFT(contact_name, 2) = 'ZY'`
2. **Check closed communities**: `SELECT COUNT(*) FROM contact c JOIN contact_type ct ON c.contact_type_id = ct.contact_type_id WHERE ct.contact_type = 'Closed'`
3. **Verify overlap**: Check if any ZY communities are also marked as Closed

### Validation Queries
```sql
-- See examples of ZY communities
SELECT contact_id, contact_name, ct.contact_type 
FROM contact c 
JOIN contact_type ct ON c.contact_type_id = ct.contact_type_id 
WHERE LEFT(c.contact_name, 2) = 'ZY' 
LIMIT 10;

-- See examples of closed communities  
SELECT contact_id, contact_name, ct.contact_type 
FROM contact c 
JOIN contact_type ct ON c.contact_type_id = ct.contact_type_id 
WHERE ct.contact_type = 'Closed' 
LIMIT 10;
```

This logic now accurately reflects the actual database structure and business processes while maintaining optimal performance.

