#!/bin/bash

# =============================================================================
# NES Database Cleanup - Enhanced Orchestration Script
# =============================================================================

set -e  # Exit on any error

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default database configuration
DB_HOST="${DB_HOST:-localhost}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_NAME="${DB_NAME:-nes}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

# Help function
show_help() {
    cat << EOF
NES Database Cleanup Tool - Enhanced Version

Usage: $0 [OPTIONS] COMMAND [ARGS...]

Database Options:
  --host HOST        Database host (default: localhost)
  --user USER        Database user (default: root)  
  --password PASS    Database password (or set DB_PASSWORD env var)
  --database DB      Database name (default: nes)

Commands:
  identify                           Run cutoff identification (read-only)
  dry-run CUTOFF_FILE               Perform dry run with cutoff file
  execute CUTOFF_FILE [TABLE]       Execute deletion (TABLE: contact, community, reading)
  progress                          Show current progress
  help                              Show this help

Examples:
  # Basic cutoff identification
  $0 identify

  # With custom database
  $0 --host 192.168.1.100 --user nes_user --database nes_prod identify

  # Dry run
  $0 dry-run cutoff_report_20240115.json

  # Execute community cleanup only
  $0 execute cutoff_report_20240115.json community

Environment Variables:
  DB_HOST, DB_USER, DB_PASSWORD, DB_NAME - Database connection parameters

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --host)
                DB_HOST="$2"
                shift 2
                ;;
            --user)
                DB_USER="$2"
                shift 2
                ;;
            --password)
                DB_PASSWORD="$2"
                shift 2
                ;;
            --database)
                DB_NAME="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                # This is the command
                COMMAND="$1"
                shift
                ARGS=("$@")
                break
                ;;
        esac
    done
}

# Validate database connection
validate_connection() {
    log "Validating database connection..."
    
    if [ -z "$DB_PASSWORD" ]; then
        error "Database password not set. Use --password or set DB_PASSWORD environment variable"
        exit 1
    fi
    
    # Test connection
    if ! mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT 1;" >/dev/null 2>&1; then
        error "Cannot connect to database. Please check your credentials and network connectivity"
        error "Host: $DB_HOST, User: $DB_USER, Database: $DB_NAME"
        exit 1
    fi
    
    success "Database connection validated"
}

# Phase 1: Identify cutoffs
identify_cutoffs() {
    log "Phase 1: Identifying deletion cutoffs (read-only analysis)"
    
    validate_connection
    
    python3 "$SCRIPT_DIR/cutoff_identifier.py" \
        --host "$DB_HOST" \
        --user "$DB_USER" \
        --password "$DB_PASSWORD" \
        --database "$DB_NAME"
    
    if [ $? -eq 0 ]; then
        success "Cutoff identification completed successfully"
        log "Review the generated cutoff_report_*.json file before proceeding"
    else
        error "Cutoff identification failed"
        exit 1
    fi
}

# Phase 2: Dry run
dry_run() {
    local cutoff_file="$1"
    
    if [ -z "$cutoff_file" ]; then
        error "Cutoff file is required for dry run"
        exit 1
    fi
    
    if [ ! -f "$cutoff_file" ]; then
        error "Cutoff file not found: $cutoff_file"
        exit 1
    fi
    
    log "Phase 2: Performing dry run with cutoff file: $cutoff_file"
    
    validate_connection
    
    python3 "$SCRIPT_DIR/production_batch_deleter.py" \
        --host "$DB_HOST" \
        --user "$DB_USER" \
        --password "$DB_PASSWORD" \
        --database "$DB_NAME" \
        --cutoff-config "$cutoff_file" \
        --dry-run
    
    if [ $? -eq 0 ]; then
        success "Dry run completed successfully"
    else
        error "Dry run failed"
        exit 1
    fi
}

# Phase 3: Execute deletion
execute_deletion() {
    local cutoff_file="$1"
    local table="$2"
    
    if [ -z "$cutoff_file" ]; then
        error "Cutoff file is required for execution"
        exit 1
    fi
    
    if [ ! -f "$cutoff_file" ]; then
        error "Cutoff file not found: $cutoff_file"
        exit 1
    fi
    
    if [ -n "$table" ]; then
        log "Phase 3: Executing deletion for table: $table"
    else
        log "Phase 3: Executing deletion for all tables"
    fi
    
    warning "This will permanently delete data from the database!"
    warning "Database: $DB_HOST/$DB_NAME"
    warning "Cutoff file: $cutoff_file"
    
    if [ -n "$table" ]; then
        warning "Target table: $table"
    else
        warning "Target: ALL TABLES"
    fi
    
    echo ""
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " confirm
    
    if [ "$confirm" != "DELETE" ]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    validate_connection
    
    local table_arg=""
    if [ -n "$table" ]; then
        table_arg="--table $table"
    fi
    
    # Use production batch deleter for actual deletion
    python3 "$SCRIPT_DIR/production_batch_deleter.py" \
        --host "$DB_HOST" \
        --user "$DB_USER" \
        --password "$DB_PASSWORD" \
        --database "$DB_NAME" \
        --cutoff-config "$cutoff_file" \
        $table_arg
    
    if [ $? -eq 0 ]; then
        success "Deletion completed successfully"
        show_progress
    else
        error "Deletion failed"
        exit 1
    fi
}

# Show progress report
show_progress() {
    log "Generating progress report..."
    
    # Get current database size
    local db_size=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "
        SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'DB Size (MB)'
        FROM information_schema.tables 
        WHERE table_schema='$DB_NAME';" -s -N 2>/dev/null || echo "Unknown")
    
    echo ""
    echo "=== DATABASE STATUS ==="
    echo "Host: $DB_HOST"
    echo "Database: $DB_NAME"
    echo "Current Size: ${db_size} MB"
    echo ""
    
    # Show recent cutoff reports
    echo "=== RECENT CUTOFF REPORTS ==="
    ls -la cutoff_report_*.json 2>/dev/null || echo "No cutoff reports found"
    echo ""
}

# Main execution
main() {
    # Parse command line arguments
    parse_args "$@"
    
    # Check if command was provided
    if [ -z "$COMMAND" ]; then
        error "No command provided"
        show_help
        exit 1
    fi
    
    # Execute command
    case "$COMMAND" in
        identify)
            identify_cutoffs
            ;;
        dry-run)
            if [ ${#ARGS[@]} -eq 0 ]; then
                error "Cutoff file required for dry-run"
                exit 1
            fi
            dry_run "${ARGS[0]}"
            ;;
        execute)
            if [ ${#ARGS[@]} -eq 0 ]; then
                error "Cutoff file required for execute"
                exit 1
            fi
            execute_deletion "${ARGS[0]}" "${ARGS[1]}"
            ;;
        progress)
            show_progress
            ;;
        help)
            show_help
            ;;
        *)
            error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"

