#!/bin/bash

# NES Database Cleanup - Main Execution Script
# This script orchestrates the complete cleanup process

set -e  # Exit on any error

# Configuration
DB_HOST="${DB_HOST:-localhost}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_NAME="${DB_NAME:-nes}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if required parameters are provided
check_requirements() {
    if [ -z "$DB_PASSWORD" ]; then
        error "Database password is required. Set DB_PASSWORD environment variable."
        exit 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is required but not installed."
        exit 1
    fi
    
    if ! python3 -c "import mysql.connector" 2>/dev/null; then
        error "mysql-connector-python is required. Install with: pip3 install mysql-connector-python"
        exit 1
    fi
}

# Phase 1: Identify cutoffs
identify_cutoffs() {
    log "Phase 1: Identifying ID cutoffs..."
    
    local output_file="$PROJECT_DIR/cutoff_report_$(date +%Y%m%d_%H%M%S).json"
    
    python3 "$SCRIPT_DIR/cutoff_identifier.py" \
        --host "$DB_HOST" \
        --user "$DB_USER" \
        --password "$DB_PASSWORD" \
        --database "$DB_NAME" \
        --output "$output_file"
    
    if [ $? -eq 0 ]; then
        success "Cutoff identification completed. Report saved to: $output_file"
        echo "$output_file"
    else
        error "Cutoff identification failed"
        exit 1
    fi
}

# Phase 2: Dry run validation
dry_run_validation() {
    local cutoff_file="$1"
    
    log "Phase 2: Performing dry run validation..."
    
    python3 "$SCRIPT_DIR/batch_deleter.py" \
        --host "$DB_HOST" \
        --user "$DB_USER" \
        --password "$DB_PASSWORD" \
        --database "$DB_NAME" \
        --cutoff-config "$cutoff_file" \
        --dry-run
    
    if [ $? -eq 0 ]; then
        success "Dry run validation completed successfully"
    else
        error "Dry run validation failed"
        exit 1
    fi
}

# Phase 3: Execute deletion
execute_deletion() {
    local cutoff_file="$1"
    local table="$2"
    
    if [ -n "$table" ]; then
        log "Phase 3: Executing deletion for table: $table"
    else
        log "Phase 3: Executing deletion for all tables"
    fi
    
    warning "This will permanently delete data from the database!"
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    local table_arg=""
    if [ -n "$table" ]; then
        table_arg="--table $table"
    fi
    
    python3 "$SCRIPT_DIR/batch_deleter.py" \
        --host "$DB_HOST" \
        --user "$DB_USER" \
        --password "$DB_PASSWORD" \
        --database "$DB_NAME" \
        --cutoff-config "$cutoff_file" \
        $table_arg
    
    if [ $? -eq 0 ]; then
        success "Deletion completed successfully"
    else
        error "Deletion failed"
        exit 1
    fi
}

# Show progress report
show_progress() {
    log "Showing deletion progress report..."
    
    python3 "$SCRIPT_DIR/batch_deleter.py" \
        --host "$DB_HOST" \
        --user "$DB_USER" \
        --password "$DB_PASSWORD" \
        --database "$DB_NAME" \
        --cutoff-config "/dev/null" \
        --progress
}

# Show database size
show_database_size() {
    log "Current database size:"
    
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "
        SELECT 
            table_name,
            ROUND(data_length/1024/1024, 2) AS data_mb,
            ROUND(index_length/1024/1024, 2) AS index_mb,
            ROUND((data_length+index_length)/1024/1024, 2) AS total_mb
        FROM information_schema.tables 
        WHERE table_schema = '$DB_NAME'
        AND table_name IN ('reading', 'contact', 'email', 'email_attachment', 'invoice_detail', 'address')
        ORDER BY (data_length+index_length) DESC;
    "
}

# Main function
main() {
    local action="$1"
    local cutoff_file="$2"
    local table="$3"
    
    check_requirements
    
    case "$action" in
        "identify")
            cutoff_file=$(identify_cutoffs)
            log "Next step: Run '$0 dry-run $cutoff_file' to validate"
            ;;
        "dry-run")
            if [ -z "$cutoff_file" ]; then
                error "Cutoff file is required for dry-run. Usage: $0 dry-run <cutoff_file>"
                exit 1
            fi
            dry_run_validation "$cutoff_file"
            log "Next step: Run '$0 execute $cutoff_file' to perform actual deletion"
            ;;
        "execute")
            if [ -z "$cutoff_file" ]; then
                error "Cutoff file is required for execution. Usage: $0 execute <cutoff_file> [table]"
                exit 1
            fi
            execute_deletion "$cutoff_file" "$table"
            ;;
        "progress")
            show_progress
            ;;
        "size")
            show_database_size
            ;;
        "full")
            # Complete workflow
            log "Starting complete cleanup workflow..."
            cutoff_file=$(identify_cutoffs)
            dry_run_validation "$cutoff_file"
            execute_deletion "$cutoff_file"
            show_database_size
            ;;
        *)
            echo "Usage: $0 {identify|dry-run|execute|progress|size|full} [cutoff_file] [table]"
            echo ""
            echo "Commands:"
            echo "  identify              - Identify ID cutoffs and generate report"
            echo "  dry-run <cutoff_file> - Validate deletion plan without actual deletion"
            echo "  execute <cutoff_file> [table] - Execute deletion (optionally for specific table)"
            echo "  progress              - Show current deletion progress"
            echo "  size                  - Show current database table sizes"
            echo "  full                  - Run complete workflow (identify -> dry-run -> execute)"
            echo ""
            echo "Environment variables:"
            echo "  DB_HOST     - Database host (default: localhost)"
            echo "  DB_USER     - Database user (default: root)"
            echo "  DB_PASSWORD - Database password (required)"
            echo "  DB_NAME     - Database name (default: nes)"
            echo ""
            echo "Examples:"
            echo "  $0 identify"
            echo "  $0 dry-run cutoff_report_20240130_120000.json"
            echo "  $0 execute cutoff_report_20240130_120000.json reading"
            echo "  $0 progress"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"

