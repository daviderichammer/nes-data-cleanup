# Contact Type Fix Documentation

## Issue
The original community identification logic assumed there was a contact type called 'zy' which doesn't exist in the database. This would have caused the community cleanup to find zero records.

## Solution
Replaced hardcoded contact type names with flexible pattern matching that looks for common patterns in contact type names that might indicate closed or inactive communities.

## Changes Made

### 1. SQL Scripts Updated
- `sql/identify-cutoffs.sql` - Updated community identification logic
- `sql/check-contact-types.sql` - New script to analyze actual contact types

### 2. Python Scripts Updated  
- `scripts/cutoff_identifier.py` - Updated community cutoff identification
- `scripts/check_contact_types.py` - New utility to analyze contact types

### 3. Pattern Matching Logic
Instead of hardcoded types like `'Closed', 'zy'`, now uses flexible patterns:

```sql
WHERE (
    LOWER(ct.contact_type) LIKE '%clos%'
    OR LOWER(ct.contact_type) LIKE '%inact%'
    OR LOWER(ct.contact_type) LIKE '%term%'
    OR LOWER(ct.contact_type) LIKE '%cancel%'
    OR LOWER(ct.contact_type) LIKE '%end%'
    OR LOWER(ct.contact_type) LIKE '%dead%'
)
```

## How to Use

### Step 1: Analyze Contact Types
First, run the contact type checker to see what types actually exist:

```bash
export DB_PASSWORD="your_password"
./scripts/check_contact_types.py --user root --password "$DB_PASSWORD"
```

This will show:
- All contact types in the database
- Types that match closed/inactive patterns
- Types that match community patterns
- Contacts older than 7 years by type

### Step 2: Customize if Needed
Based on the analysis, you may want to:

1. **Add more patterns** to the SQL if you find other naming conventions
2. **Remove patterns** that match too broadly
3. **Use specific type names** if the patterns don't work well

### Step 3: Test the Updated Logic
Run the cutoff identification to see how many communities it finds:

```bash
./scripts/run_cleanup.sh identify
```

## Benefits of This Approach

1. **Flexible**: Works with any naming convention for closed communities
2. **Safe**: Won't break if contact type names change
3. **Discoverable**: The checker script helps you understand your data
4. **Customizable**: Easy to adjust patterns based on your specific database

## Fallback Options

If the pattern matching doesn't work well for your database, you can:

1. **Use the checker results** to create a specific list of contact type names
2. **Focus on date-based criteria** only (communities not updated in 7+ years)
3. **Add business logic** based on other attributes or relationships

The key is that the system is now flexible and can be easily adjusted based on your actual data.

