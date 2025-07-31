# VPN Server Installation and Run Guide

## Overview
This guide provides step-by-step instructions to install and run the NES Database Cleanup tools on your VPN server to perform cutoff identification.

## Prerequisites
- Access to your VPN server with sudo privileges
- MySQL/MariaDB client installed
- Python 3.6+ installed
- Git installed
- Network access to the NES database

## Step 1: System Preparation

### Check System Requirements
```bash
# Check Python version (need 3.6+)
python3 --version

# Check if git is installed
git --version

# Check if mysql client is installed
mysql --version

# Check if pip is available
pip3 --version
```

### Install Missing Dependencies (if needed)
```bash
# On Ubuntu/Debian systems:
sudo apt update
sudo apt install -y python3 python3-pip git mysql-client

# On CentOS/RHEL systems:
sudo yum install -y python3 python3-pip git mysql

# On newer CentOS/RHEL systems:
sudo dnf install -y python3 python3-pip git mysql
```

## Step 2: Clone the Repository

### Create Working Directory
```bash
# Create a dedicated directory for the cleanup project
mkdir -p /opt/nes-cleanup
cd /opt/nes-cleanup

# Or use your preferred location:
# mkdir -p ~/nes-cleanup
# cd ~/nes-cleanup
```

### Clone from GitHub
```bash
# Clone the repository
git clone https://github.com/daviderichammer/nes-data-cleanup.git

# Navigate to the project directory
cd nes-data-cleanup

# Verify the clone was successful
ls -la
```

You should see the following structure:
```
nes-data-cleanup/
├── config/
├── docs/
├── scripts/
├── sql/
├── README.md
├── todo.md
└── data-deletion-plan-revised.md
```

## Step 3: Install Python Dependencies

### Install Required Python Packages
```bash
# Install the MySQL connector for Python
pip3 install mysql-connector-python

# If you get permission errors, use:
sudo pip3 install mysql-connector-python

# Or install for current user only:
pip3 install --user mysql-connector-python
```

### Verify Installation
```bash
# Test that the MySQL connector is working
python3 -c "import mysql.connector; print('MySQL connector installed successfully')"
```

## Step 4: Database Connection Setup

### Test Database Connectivity
```bash
# Test connection to your NES database
# Replace with your actual database host and credentials
mysql -h YOUR_DB_HOST -u YOUR_DB_USER -p YOUR_DATABASE_NAME

# Example (adjust for your setup):
# mysql -h localhost -u root -p nes
# mysql -h 192.168.1.100 -u nes_user -p nes_production
```

### Set Environment Variables
```bash
# Set the database password as an environment variable
# This avoids having to type it repeatedly
export DB_PASSWORD="YOUR_DATABASE_PASSWORD"

# Verify it's set
echo "Password set: ${DB_PASSWORD:+YES}"
```

## Step 5: Make Scripts Executable

### Set Execute Permissions
```bash
# Make all scripts executable
chmod +x scripts/*.py
chmod +x scripts/*.sh

# Verify permissions
ls -la scripts/
```

You should see executable permissions (x) on the script files.

## Step 6: Run Cutoff Identification

### Basic Cutoff Identification
```bash
# Run the cutoff identification (read-only, safe)
./scripts/run_cleanup.sh identify
```

### With Custom Database Parameters
If you need to specify different database connection parameters:

```bash
# Edit the run_cleanup.sh script to set your database details
# Or run the Python script directly with parameters:

python3 scripts/cutoff_identifier.py \
    --host YOUR_DB_HOST \
    --user YOUR_DB_USER \
    --password "$DB_PASSWORD" \
    --database YOUR_DB_NAME
```

### Example with Typical Parameters
```bash
# Example for local database
python3 scripts/cutoff_identifier.py \
    --host localhost \
    --user root \
    --password "$DB_PASSWORD" \
    --database nes

# Example for remote database
python3 scripts/cutoff_identifier.py \
    --host 192.168.1.100 \
    --user nes_user \
    --password "$DB_PASSWORD" \
    --database nes_production
```

## Step 7: Review Results

### Check Output Files
```bash
# The cutoff identification will create a report file
ls -la cutoff_report_*.json

# View the results
cat cutoff_report_*.json | python3 -m json.tool
```

### Expected Output Format
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "database_info": {
    "host": "your-db-host",
    "database": "nes"
  },
  "cutoffs": {
    "contact_cutoff": 123456,
    "reading_cutoff": 789012
  },
  "estimated_deletions": {
    "communities_closed": 1500,
    "communities_zy": 2094,
    "community_addresses": 10783,
    "community_phones": 17970,
    "community_notes": 3599,
    "non_billing_readings": 200000000,
    "total_estimated": 200035946
  },
  "safety_checks": {
    "recent_activity_excluded": true,
    "billing_readings_excluded": true,
    "legal_holds_checked": true
  }
}
```

## Step 8: Validate Results

### Review the Numbers
1. **Check community counts**: Do the closed/ZY community numbers look reasonable?
2. **Verify reading counts**: Does the non-billing reading count seem accurate?
3. **Validate cutoff IDs**: Are the cutoff IDs in the expected range?

### Manual Verification Queries (Optional)
```bash
# Connect to database for manual verification
mysql -h YOUR_DB_HOST -u YOUR_DB_USER -p YOUR_DATABASE_NAME

# Run these queries to verify the counts:
```

```sql
-- Check closed communities
SELECT COUNT(*) FROM contact c 
JOIN contact_type ct ON c.contact_type_id = ct.contact_type_id 
WHERE ct.contact_type = 'Closed' 
AND c.last_modified < DATE_SUB(NOW(), INTERVAL 7 YEAR);

-- Check ZY communities  
SELECT COUNT(*) FROM contact 
WHERE LEFT(contact_name, 2) = 'ZY'
AND last_modified < DATE_SUB(NOW(), INTERVAL 7 YEAR);

-- Check non-billing readings
SELECT COUNT(*) FROM reading r
LEFT JOIN sm_usage su ON r.reading_id = su.reading_id
WHERE su.reading_id IS NULL
AND r.reading_date < DATE_SUB(NOW(), INTERVAL 2 YEAR);
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Permission Denied Errors
```bash
# If you get permission errors:
sudo chmod +x scripts/*.py scripts/*.sh

# Or run with python3 explicitly:
python3 scripts/cutoff_identifier.py --help
```

#### 2. MySQL Connection Errors
```bash
# Test basic connectivity:
mysql -h YOUR_DB_HOST -u YOUR_DB_USER -p

# Check if the database name is correct:
mysql -h YOUR_DB_HOST -u YOUR_DB_USER -p -e "SHOW DATABASES;"
```

#### 3. Python Module Not Found
```bash
# Reinstall the MySQL connector:
pip3 install --upgrade mysql-connector-python

# Or try with sudo:
sudo pip3 install mysql-connector-python
```

#### 4. Script Not Found
```bash
# Make sure you're in the right directory:
pwd
ls -la scripts/

# If scripts are missing, re-clone the repository:
git pull origin main
```

## Security Notes

### Database Credentials
- Never hardcode passwords in scripts
- Use environment variables for sensitive data
- Consider using a dedicated read-only database user for analysis

### File Permissions
```bash
# Secure the directory
chmod 750 /opt/nes-cleanup/nes-data-cleanup

# Secure sensitive files
chmod 600 cutoff_report_*.json
```

## Next Steps

After successful cutoff identification:

1. **Review the results** with your team
2. **Validate the numbers** against your expectations  
3. **Plan the pilot execution** starting with community cleanup
4. **Prepare for production testing** on a database copy

The cutoff identification is completely safe and read-only. It provides the foundation for planning the actual cleanup execution.

