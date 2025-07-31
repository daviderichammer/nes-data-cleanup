# Quick Start Commands - VPN Server

## TL;DR - Fast Setup and Run

### 1. One-Time Setup
```bash
# Install dependencies (Ubuntu/Debian)
sudo apt update && sudo apt install -y python3 python3-pip git mysql-client
pip3 install mysql-connector-python

# Clone repository
git clone https://github.com/daviderichammer/nes-data-cleanup.git
cd nes-data-cleanup
chmod +x scripts/*.py scripts/*.sh
```

### 2. Set Database Password
```bash
# Replace with your actual database password
export DB_PASSWORD="YOUR_DATABASE_PASSWORD"
```

### 3. Run Cutoff Identification
```bash
# Basic run (uses localhost, root user, nes database)
./scripts/run_cleanup.sh identify

# OR with custom parameters
python3 scripts/cutoff_identifier.py \
    --host YOUR_DB_HOST \
    --user YOUR_DB_USER \
    --password "$DB_PASSWORD" \
    --database YOUR_DB_NAME
```

### 4. Check Results
```bash
# View the generated report
cat cutoff_report_*.json | python3 -m json.tool
```

## Common Database Configurations

### Local Database
```bash
python3 scripts/cutoff_identifier.py \
    --host localhost \
    --user root \
    --password "$DB_PASSWORD" \
    --database nes
```

### Remote Database
```bash
python3 scripts/cutoff_identifier.py \
    --host 192.168.1.100 \
    --user nes_user \
    --password "$DB_PASSWORD" \
    --database nes_production
```

### Custom Port
```bash
python3 scripts/cutoff_identifier.py \
    --host your-db-host \
    --port 3307 \
    --user your_user \
    --password "$DB_PASSWORD" \
    --database your_database
```

## Expected Runtime
- **Small database** (< 1M records): 1-2 minutes
- **Medium database** (1-10M records): 2-5 minutes  
- **Large database** (10M+ records): 5-15 minutes
- **Your database** (500M+ records): 10-30 minutes

## What to Expect
The script will output progress like this:
```
2024-01-15 10:30:15 - INFO - Connected to database successfully
2024-01-15 10:30:16 - INFO - Analyzing contact cutoffs...
2024-01-15 10:30:45 - INFO - Found 3594 communities for deletion
2024-01-15 10:31:20 - INFO - Analyzing reading cutoffs...
2024-01-15 10:35:30 - INFO - Found 200000000 non-billing readings for deletion
2024-01-15 10:35:31 - INFO - Cutoff analysis completed
2024-01-15 10:35:31 - INFO - Report saved to: cutoff_report_20240115_103531.json
```

## Troubleshooting Quick Fixes

### Can't Connect to Database
```bash
# Test connection manually
mysql -h YOUR_HOST -u YOUR_USER -p YOUR_DATABASE
```

### Permission Denied
```bash
# Fix script permissions
chmod +x scripts/*.py scripts/*.sh
```

### Module Not Found
```bash
# Reinstall Python dependencies
pip3 install --upgrade mysql-connector-python
```

### Script Hangs
- Check database connectivity
- Verify database has the expected tables
- Monitor database server performance

## Safety Reminders
- ✅ This is **READ-ONLY** - no data will be deleted
- ✅ Safe to run on production database
- ✅ Can be interrupted at any time (Ctrl+C)
- ✅ Generates detailed report for review

