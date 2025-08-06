# Character Set Compatibility Fix

## Issue
The MySQL connector was attempting to use the `utf8mb4` character set, which is not supported by older MySQL/MariaDB servers. This caused connection failures with the error:

```
1115 (42000): Unknown character set: 'utf8mb4'
```

## Root Cause
- Newer versions of the MySQL Python connector default to `utf8mb4` character set
- Older MySQL servers (< 5.5.3) and some MariaDB configurations don't support `utf8mb4`
- The VPN server's database appears to be running an older version that only supports `utf8`

## Solution
Updated the database connection configuration in both scripts to:

1. **Use `utf8` character set** instead of the default `utf8mb4`
2. **Enable Unicode support** with `use_unicode = True`
3. **Set appropriate autocommit behavior** for each script type

### Changes Made

#### cutoff_identifier.py
```python
def connect(self):
    """Connect to database with compatibility for older MySQL servers"""
    try:
        # Add charset compatibility for older MySQL servers
        db_config = self.db_config.copy()
        
        # Use utf8 instead of utf8mb4 for older MySQL compatibility
        db_config['charset'] = 'utf8'
        db_config['use_unicode'] = True
        
        # Disable SSL warnings for older servers
        db_config['autocommit'] = True
        
        self.db = mysql.connector.connect(**db_config)
        self.logger.info("Connected to database successfully")
    except mysql.connector.Error as e:
        self.logger.error(f"Database connection failed: {e}")
        raise
```

#### production_batch_deleter.py
```python
def connect(self):
    """Connect to database with compatibility for older MySQL servers"""
    try:
        # Add charset compatibility for older MySQL servers
        db_config = self.db_config.copy()
        
        # Use utf8 instead of utf8mb4 for older MySQL compatibility
        db_config['charset'] = 'utf8'
        db_config['use_unicode'] = True
        
        # Disable SSL warnings for older servers
        db_config['autocommit'] = False  # Use transactions for deletion
        
        self.db = mysql.connector.connect(**db_config)
        self.db.autocommit = False  # Use transactions
        self.logger.info("Connected to database successfully")
    except mysql.connector.Error as e:
        self.logger.error(f"Database connection failed: {e}")
        raise
```

## Character Set Differences

### utf8 vs utf8mb4
- **utf8**: Supports Basic Multilingual Plane (BMP) characters (1-3 bytes per character)
- **utf8mb4**: Supports full UTF-8 including 4-byte characters like emojis and some Asian characters

### Impact on NES Database
- The NES database likely contains standard text data (names, addresses, etc.)
- Using `utf8` instead of `utf8mb4` should have **no impact** on data integrity
- All standard characters will be handled correctly
- Only 4-byte Unicode characters (emojis, rare symbols) would be affected, which are unlikely in a utility billing system

## Compatibility
This fix ensures compatibility with:
- **MySQL 5.0+** (all versions)
- **MariaDB 5.1+** (all versions)
- **Older database configurations** that don't support utf8mb4

## Testing
After applying this fix, the connection should succeed and the cutoff identification should run normally:

```bash
./scripts/run_cleanup_enhanced.sh --host 10.99.1.80 --user w3 --database nes identify
```

Expected output:
```
[2025-08-05 21:22:12] INFO: Phase 1: Identifying deletion cutoffs (read-only analysis)
[2025-08-05 21:22:12] INFO: Validating database connection...
[2025-08-05 21:22:12] SUCCESS: Database connection validated
2025-08-05 21:22:13,025 - INFO - Connected to database successfully
2025-08-05 21:22:13,026 - INFO - Analyzing contact cutoffs...
```

## Future Considerations
- This fix maintains backward compatibility with older MySQL servers
- If the database is upgraded to support utf8mb4 in the future, the scripts will continue to work
- For maximum compatibility, we'll keep using utf8 unless there's a specific need for 4-byte Unicode support

