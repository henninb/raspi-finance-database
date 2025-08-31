#!/bin/sh

# Backup Validation Dry-Run Script
# This script validates database backups without making permanent changes

# Global variables
date=$(date '+%Y-%m-%d')
port=5432
version=v17-6
username=henninb
script_name="$(basename "$0")"
log_file="backup-validation-${date}.log"
exit_code=0
temp_db="finance_backup_validation_temp"
start_time=$(date +%s)
run_marker="RUN_$(date '+%Y%m%d_%H%M%S')_$$"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log_msg() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$run_marker] $1" | tee -a "$log_file"
}

# Success logging function
log_success() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "${GREEN}[$timestamp] [$run_marker] ✅ SUCCESS: $1${NC}\n" | tee -a "$log_file"
}

# Error logging function
log_error() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "${RED}[$timestamp] [$run_marker] ❌ ERROR: $1${NC}\n" | tee -a "$log_file" >&2
    exit_code=1
}

# Warning logging function
log_warning() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "${YELLOW}[$timestamp] [$run_marker] ⚠️  WARNING: $1${NC}\n" | tee -a "$log_file"
}

# Info logging function
log_info() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "${BLUE}[$timestamp] [$run_marker] ℹ️  INFO: $1${NC}\n" | tee -a "$log_file"
}

# Execute command with error handling
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local allow_warnings="${3:-false}"

    log_info "Starting: $description"
    log_msg "Command: $cmd"

    local output
    local cmd_exit_code

    if [ "$allow_warnings" = "true" ]; then
        output=$(eval "$cmd" 2>&1)
        cmd_exit_code=$?

        if echo "$output" | grep -q "WARNING\|NOTICE"; then
            log_warning "Non-fatal warnings/notices in: $description"
        fi

        if [ $cmd_exit_code -eq 0 ]; then
            log_success "$description completed"
            return 0
        else
            log_error "$description failed with exit code $cmd_exit_code"
            log_error "Output: $output"
            return $cmd_exit_code
        fi
    else
        if eval "$cmd"; then
            log_success "$description completed"
            return 0
        else
            cmd_exit_code=$?
            log_error "$description failed with exit code $cmd_exit_code"
            return $cmd_exit_code
        fi
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary validation database..."
    psql -h localhost -p "$port" -U "$username" postgres -c "DROP DATABASE IF EXISTS $temp_db;" >/dev/null 2>&1 || true
    log_success "Cleanup completed"
}

# Test database connectivity
test_db_connection() {
    local test_server="$1"
    local test_port="$2"
    local test_user="$3"

    log_info "Testing database connectivity to ${test_server}:${test_port}"

    if ! psql -h "$test_server" -p "$test_port" -U "$test_user" -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
        log_error "Cannot connect to database at ${test_server}:${test_port} with user ${test_user}"
        log_error "Please check: 1) Server is running 2) Network connectivity 3) Credentials in ~/.pgpass"
        return 1
    else
        log_success "Database connectivity test successful"
        return 0
    fi
}

log_info "Starting backup validation script: $script_name"
log_info "Log file: $log_file"
log_info "Temporary database name: $temp_db"

# Check command line arguments
if [ $# -lt 1 ] || [ $# -gt 4 ]; then
    log_error "Invalid number of arguments"
    echo "Usage: $0 <backup-file> [server] [port] [version]"
    echo "Example: $0 finance_db-v17-6-2025-01-26.tar localhost 5432 v17-6"
    exit 1
fi

backup_file="$1"

if [ "$OS" = "Darwin" ]; then
    server=$(ipconfig getifaddr en0)
else
    server=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
fi

# Process optional arguments
if [ -n "$2" ]; then
    server=$2
    log_info "Server set from argument: $server"
fi

if [ -n "$3" ]; then
    port=$3
    log_info "Port set from argument: $port"
fi

if [ -n "$4" ]; then
    version=$4
    log_info "Version set from argument: $version"
fi

log_info "Configuration - Server: '$server', Port: '$port', Version: '$version', User: '$username'"

# Check if backup file exists
if [ ! -f "$backup_file" ]; then
    log_error "Backup file not found: $backup_file"
    exit 1
fi

log_success "Backup file found: $backup_file"

# Check backup file size - cross-platform compatible
if command -v stat >/dev/null 2>&1; then
    # Try BSD/macOS format first, then GNU/Linux format
    file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null || echo "0")
else
    # Fallback using ls if stat is not available
    file_size=$(ls -l "$backup_file" 2>/dev/null | awk '{print $5}' || echo "0")
fi
if [ "$file_size" -lt 1024 ]; then
    log_error "Backup file appears to be too small (${file_size} bytes)"
    exit 1
fi

log_success "Backup file size check passed: $(echo "$file_size" | awk '{printf "%.2f MB", $1/1024/1024}')"

# Check dependencies
log_info "Checking for required dependencies"
if [ ! -x "$(command -v psql)" ]; then
    log_error "psql command not found - please install PostgreSQL client tools"
    exit 2
fi

if [ ! -x "$(command -v pg_restore)" ]; then
    log_error "pg_restore command not found - please install PostgreSQL client tools"
    exit 2
fi

log_success "All required dependencies found"

# Check pgpass file
log_info "Checking for ~/.pgpass file"
if [ ! -f "$HOME/.pgpass" ]; then
    log_error "~/.pgpass file not found. Please create it with the format:"
    echo "${server}:${port}:*:${username}:your_password"
    echo "Then run: chmod 600 ~/.pgpass"
    exit 1
fi

# Check pgpass permissions - cross-platform compatible
if command -v stat >/dev/null 2>&1; then
    # Try GNU/Linux format first, then BSD/macOS format
    pgpass_perms=$(stat -c "%a" "$HOME/.pgpass" 2>/dev/null || stat -f "%OLp" "$HOME/.pgpass" 2>/dev/null || echo "000")
else
    # Fallback using ls if stat is not available
    pgpass_perms=$(ls -l "$HOME/.pgpass" 2>/dev/null | cut -c2-10 | sed 's/rwx/7/g; s/rw-/6/g; s/r-x/5/g; s/r--/4/g; s/-wx/3/g; s/-w-/2/g; s/--x/1/g; s/---/0/g' | sed 's/\(.*\)\(.*\)\(.*\)/\1\2\3/' | head -c3 || echo "000")
fi

# Normalize permission format for comparison
case "$pgpass_perms" in
    600|rw-------) pgpass_perms="600" ;;
    *) ;; # Keep as is for error reporting
esac
if [ "$pgpass_perms" != "600" ]; then
    log_error "~/.pgpass file has incorrect permissions ($pgpass_perms). Run: chmod 600 ~/.pgpass"
    exit 1
fi

log_success "pgpass file found with correct permissions"
export PGPASSFILE="$HOME/.pgpass"

# Test database connectivity
if ! test_db_connection "$server" "$port" "$username"; then
    exit 3
fi

# Trap to ensure cleanup on exit
trap cleanup EXIT

log_info "Starting backup validation process..."

# Step 1: Create temporary database for validation
log_info "Creating temporary validation database: $temp_db"
if ! execute_cmd "psql -h '$server' -p '$port' -U '$username' postgres -c 'DROP DATABASE IF EXISTS $temp_db;'" "Drop existing temp database" "true"; then
    exit 4
fi

if ! execute_cmd "psql -h '$server' -p '$port' -U '$username' postgres -c 'CREATE DATABASE $temp_db;'" "Create temp database" "true"; then
    exit 4
fi

# Step 2: Restore backup to temporary database
log_info "Restoring backup to temporary database for validation..."
if ! execute_cmd "pg_restore -h '$server' -p '$port' -U '$username' -F t -d '$temp_db' --no-owner --no-privileges '$backup_file'" "Restore backup to temp database" "true"; then
    log_error "Failed to restore backup file to temporary database"
    exit 5
fi

log_success "Backup successfully restored to temporary database"

# Step 3: Verify backup file integrity and contents
log_info "Performing backup file integrity checks..."

# Check if backup file is a valid PostgreSQL dump
log_info "Validating backup file format..."
if ! pg_restore --list "$backup_file" >/dev/null 2>&1; then
    log_error "Backup file is not a valid PostgreSQL dump format"
    exit 6
fi

log_success "Backup file format validation passed"

# Get backup file statistics
backup_list=$(pg_restore --list "$backup_file")
table_count=$(echo "$backup_list" | grep -c "TABLE DATA" || echo "0")
index_count=$(echo "$backup_list" | grep -c "INDEX" || echo "0")
constraint_count=$(echo "$backup_list" | grep -c "CONSTRAINT" || echo "0")

log_info "Backup contents: $table_count tables, $index_count indexes, $constraint_count constraints"

# Verify expected tables exist in backup
expected_tables="t_account t_category t_description t_parameter t_transaction t_validation_amount t_payment t_transfer t_receipt_image t_pending_transaction t_transaction_categories"
missing_tables=""

for table in $expected_tables; do
    if ! echo "$backup_list" | grep -q "TABLE DATA.*$table"; then
        missing_tables="$missing_tables $table"
    fi
done

if [ -n "$missing_tables" ]; then
    log_warning "Missing expected tables in backup:$missing_tables"
else
    log_success "All expected core tables found in backup"
fi

# Check for new medical tables (optional)
medical_tables="t_medical_provider t_family_member"
found_medical_tables=""
for table in $medical_tables; do
    if echo "$backup_list" | grep -q "TABLE DATA.*$table"; then
        found_medical_tables="$found_medical_tables $table"
    fi
done

if [ -n "$found_medical_tables" ]; then
    log_success "Medical expense tables found in backup:$found_medical_tables"
else
    log_info "No medical expense tables found in backup (may be expected for older backups)"
fi

# Step 4: Validate restored data integrity
log_info "Performing data integrity validation..."

# Check that tables exist and are accessible
log_info "Verifying table accessibility in restored database..."
accessible_tables=0
total_expected_tables=0

for table in $expected_tables; do
    total_expected_tables=$((total_expected_tables + 1))
    if psql -h "$server" -p "$port" -U "$username" -d "$temp_db" -c "SELECT 1 FROM $table LIMIT 1;" >/dev/null 2>&1; then
        accessible_tables=$((accessible_tables + 1))
        log_success "Table $table is accessible"
    else
        log_error "Table $table is not accessible or empty"
    fi
done

log_info "Table accessibility: $accessible_tables/$total_expected_tables tables accessible"

# Get row counts for validation
log_info "Collecting table row counts for validation..."
row_counts_query="
SELECT
    'Transactions' as table_name, COUNT(*) as row_count FROM t_transaction
UNION ALL
SELECT 'Accounts', COUNT(*) FROM t_account
UNION ALL
SELECT 'Categories', COUNT(*) FROM t_category
UNION ALL
SELECT 'Descriptions', COUNT(*) FROM t_description
UNION ALL
SELECT 'Parameters', COUNT(*) FROM t_parameter
UNION ALL
SELECT 'Validation_Amounts', COUNT(*) FROM t_validation_amount
UNION ALL
SELECT 'Payments', COUNT(*) FROM t_payment
UNION ALL
SELECT 'Transfers', COUNT(*) FROM t_transfer
UNION ALL
SELECT 'Receipt_Images', COUNT(*) FROM t_receipt_image
UNION ALL
SELECT 'Pending_Transactions', COUNT(*) FROM t_pending_transaction
UNION ALL
SELECT 'Transaction_Categories', COUNT(*) FROM t_transaction_categories
ORDER BY table_name;
"

log_info "Row count summary from restored backup:"
if ! psql -h "$server" -p "$port" -U "$username" -d "$temp_db" -c "$row_counts_query" | tee -a "$log_file"; then
    log_error "Failed to get row counts from restored database"
else
    log_success "Row counts retrieved successfully"
fi

# Check for basic data consistency
log_info "Performing basic data consistency checks..."

# Check for orphaned transaction categories
log_info "Checking for orphaned transaction categories..."
orphaned_categories=$(psql -h "$server" -p "$port" -U "$username" -d "$temp_db" -t -c "
    SELECT COUNT(*) FROM t_transaction_categories tc
    LEFT JOIN t_transaction t ON tc.transaction_id = t.transaction_id
    WHERE t.transaction_id IS NULL;
" 2>/dev/null | tr -d ' ')

if [ "$orphaned_categories" = "0" ]; then
    log_success "No orphaned transaction categories found"
else
    log_warning "$orphaned_categories orphaned transaction categories found"
fi

# Check for orphaned receipt images
log_info "Checking for orphaned receipt images..."
orphaned_receipts=$(psql -h "$server" -p "$port" -U "$username" -d "$temp_db" -t -c "
    SELECT COUNT(*) FROM t_receipt_image r
    LEFT JOIN t_transaction t ON r.transaction_id = t.transaction_id
    WHERE t.transaction_id IS NULL;
" 2>/dev/null | tr -d ' ')

if [ "$orphaned_receipts" = "0" ]; then
    log_success "No orphaned receipt images found"
else
    log_warning "$orphaned_receipts orphaned receipt images found"
fi

# Check date ranges to ensure data makes sense
log_info "Checking transaction date ranges..."
date_range_result=$(psql -h "$server" -p "$port" -U "$username" -d "$temp_db" -t -c "
    SELECT
        MIN(transaction_date) as earliest_date,
        MAX(transaction_date) as latest_date,
        COUNT(*) as total_transactions
    FROM t_transaction;
" 2>/dev/null)

if [ -n "$date_range_result" ]; then
    log_info "Transaction date range: $date_range_result"
    log_success "Date range validation completed"
else
    log_error "Failed to retrieve transaction date ranges"
fi

# Check for account balance consistency (if validation amounts exist)
validation_count=$(psql -h "$server" -p "$port" -U "$username" -d "$temp_db" -t -c "SELECT COUNT(*) FROM t_validation_amount;" 2>/dev/null | tr -d ' ')
if [ "$validation_count" != "0" ]; then
    log_info "Found $validation_count validation records - backup includes account validation data"
    log_success "Account validation data preserved in backup"
else
    log_info "No validation records found (may be expected)"
fi

# Step 5: Generate validation summary report
log_info "Generating validation summary report..."

# Final validation summary
log_info "========================================="
log_info "BACKUP VALIDATION SUMMARY REPORT"
log_info "========================================="
log_info "Backup File: $backup_file"
log_info "File Size: $(echo "$file_size" | awk '{printf "%.2f MB", $1/1024/1024}')"
log_info "Validation Database: $temp_db"
log_info "Server: $server:$port"
log_info "User: $username"
log_info "Validation Date: $(date '+%Y-%m-%d %H:%M:%S')"
log_info "========================================="

# Count errors and warnings from current run only
error_count=$(grep "\[$run_marker\].*ERROR:" "$log_file" 2>/dev/null | grep -v "VALIDATION RESULT:" | grep -v "DO NOT use this backup" | grep -v "Create a new backup" | grep -v "Review errors in the log file" | wc -l | tr -d '\n' || echo "0")
warning_count=$(grep "\[$run_marker\].*WARNING:" "$log_file" 2>/dev/null | grep -v "VALIDATION RESULT:" | wc -l | tr -d '\n' || echo "0")
success_count=$(grep "\[$run_marker\].*SUCCESS:" "$log_file" 2>/dev/null | wc -l | tr -d '\n' || echo "0")

log_info "Validation Results:"
log_info "  - Successes: $success_count"
if [ "$warning_count" -gt 0 ]; then
    log_info "  - Warnings: $warning_count"
fi
if [ "$error_count" -gt 0 ]; then
    log_info "  - Errors: $error_count"
fi

log_info "Backup Contents:"
log_info "  - Tables: $table_count"
log_info "  - Indexes: $index_count"
log_info "  - Constraints: $constraint_count"
log_info "  - Accessible Tables: $accessible_tables/$total_expected_tables"

# Reset exit code for final validation result (ignore any earlier non-critical warnings)
exit_code=0

# Overall validation result
if [ $exit_code -eq 0 ] && [ "$error_count" -eq 0 ]; then
    if [ "$warning_count" -gt 0 ]; then
        log_warning "VALIDATION RESULT: PASSED WITH WARNINGS"
        log_info "The backup appears to be valid but has some minor issues. Review warnings above."
    else
        log_success "VALIDATION RESULT: PASSED"
        log_info "The backup has been successfully validated and appears to be in good condition."
    fi
else
    log_error "VALIDATION RESULT: FAILED"
    log_error "The backup validation failed. Review errors above before using this backup."
    exit_code=1
fi

log_info "========================================="
log_info "Detailed log saved to: $log_file"
log_info "Temporary database will be cleaned up automatically"

# Provide usage recommendations
if [ $exit_code -eq 0 ]; then
    log_info ""
    log_info "RECOMMENDATIONS:"
    log_info "✅ This backup can be used for restoration"
    log_info "✅ To restore: ./run-restore.sh $backup_file"
    if [ "$warning_count" -gt 0 ]; then
        log_info "⚠️  Review warnings to understand any data inconsistencies"
    fi
else
    log_info ""
    log_info "RECOMMENDATIONS:"
    log_error "❌ DO NOT use this backup for restoration"
    log_error "❌ Create a new backup or investigate the source database"
    log_error "❌ Review errors in the log file: $log_file"
fi

end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
log_info "Validation completed in $elapsed_time seconds"

exit $exit_code
