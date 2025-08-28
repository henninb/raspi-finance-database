#!/bin/sh

# Global variables
date=$(date '+%Y-%m-%d')
restore_filename=$1
port=5432
username=henninb
script_name="$(basename "$0")"
log_file="finance-db-restore-${date}.log"
exit_code=0

# Logging function
log_msg() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$log_file"
}

# Error logging function
log_error() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $1" | tee -a "$log_file" >&2
    exit_code=1
}

# Execute command with error handling
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local allow_warnings="${3:-false}"

    log_msg "Starting: $description"
    log_msg "Command: $cmd"

    # Capture both stdout and stderr
    local output
    local cmd_exit_code

    if [ "$allow_warnings" = "true" ]; then
        # For database operations, capture output and filter warnings
        output=$(eval "$cmd" 2>&1)
        cmd_exit_code=$?

        # Log warnings but don't treat them as errors
        if echo "$output" | grep -q "WARNING\|NOTICE"; then
            log_msg "Warnings/notices (non-fatal): $(echo "$output" | grep 'WARNING\|NOTICE' | head -3)"
        fi

        # Check for actual errors
        if [ $cmd_exit_code -eq 0 ]; then
            log_msg "SUCCESS: $description completed"
            return 0
        else
            log_error "$description failed with exit code $cmd_exit_code"
            log_error "Output: $output"
            return $cmd_exit_code
        fi
    else
        # Standard execution for non-database commands
        if eval "$cmd"; then
            log_msg "SUCCESS: $description completed"
            return 0
        else
            cmd_exit_code=$?
            log_error "$description failed with exit code $cmd_exit_code"
            return $cmd_exit_code
        fi
    fi
}

log_msg "Starting restore script: $script_name"
log_msg "Log file: $log_file"

if [ "$OS" = "Darwin" ]; then
  server=$(ipconfig getifaddr en0)
else
  server=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
fi

log_msg "Checking command line arguments (received $# arguments)"

if [ $# -ne 1 ] && [ $# -ne 2 ] && [ $# -ne 3 ]; then
  log_error "Invalid number of arguments"
  echo "Usage: $0 <restore-tar-file> [server] [port]"
  echo "Example: $0 finance_db-v17-6-2025-08-27.tar 192.168.10.25 5432"
  exit 1
fi

log_msg "Checking for required dependencies"
if [ ! -x "$(command -v psql)" ]; then
  log_error "psql command not found - please install PostgreSQL client tools"
  exit 2
fi

if [ ! -x "$(command -v pg_restore)" ]; then
  log_error "pg_restore command not found - please install PostgreSQL client tools"
  exit 2
fi

log_msg "All required dependencies found"

log_msg "Processing command line parameters"

if [ ! -f "${restore_filename}" ]; then
  log_error "Restore file not found: ${restore_filename}"
  echo "You may need to copy it from the remote server first:"
  echo "scp pi@raspi:/home/pi/downloads/finance-db-bkp/finance_db-v17-6-${date}.tar ."
  exit 1
fi

log_msg "Restore file found: ${restore_filename} ($(ls -lh "${restore_filename}" | awk '{print $5}'))"

if [ -n "$2" ]; then
  server=$2
  log_msg "Server set from argument 2: $server"
fi

if [ -n "$3" ]; then
  port=$3
  log_msg "Port set from argument 3: $port"
fi

log_msg "Final configuration - Server: '$server', Port: '$port', User: '$username'"

log_msg "Checking for ~/.pgpass file"
if [ ! -f "$HOME/.pgpass" ]; then
  log_error "~/.pgpass file not found. Please create it with the format:"
  echo "${server}:${port}:finance_db:${username}:your_password"
  echo "${server}:${port}:finance_test_db:${username}:your_password"
  echo "${server}:${port}:postgres:${username}:your_password"
  echo "Then run: chmod 600 ~/.pgpass"
  exit 1
fi

# Check pgpass file permissions
pgpass_perms=$(stat -c "%a" "$HOME/.pgpass" 2>/dev/null || stat -f "%A" "$HOME/.pgpass" 2>/dev/null)
if [ "$pgpass_perms" != "600" ]; then
    log_error "~/.pgpass file has incorrect permissions ($pgpass_perms). Run: chmod 600 ~/.pgpass"
    exit 1
fi

log_msg "pgpass file found with correct permissions"
export PGPASSFILE="$HOME/.pgpass"

# Test database connectivity before proceeding
log_msg "Testing database connectivity to ${server}:${port}"
if ! psql -h "$server" -p "$port" -U "$username" -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
    log_error "Cannot connect to database at ${server}:${port} with user ${username}"
    log_error "Please check: 1) Server is running 2) Network connectivity 3) Credentials in ~/.pgpass"
    exit 3
else
    log_msg "Database connectivity test successful"
fi

log_msg "WARNING: This will completely DROP and recreate finance_db and finance_test_db databases"
log_msg "All existing data in these databases will be LOST"
log_msg "Database will restore from '${restore_filename}'"
log_msg "Server: '$server', Port: '$port'"
echo ""
echo "Press ENTER to continue or Ctrl+C to cancel"
read -r confirmation
log_msg "User confirmed restore operation"

log_msg "Starting database restoration process"

# Drop and recreate finance_db
if ! execute_cmd "psql -h '${server}' -p '${port}' -d postgres -U '${username}' -c 'DROP DATABASE IF EXISTS finance_db;'" "Drop finance_db database" "true"; then
    log_error "Failed to drop finance_db database"
    exit 4
fi

if ! execute_cmd "psql -h '${server}' -p '${port}' -d postgres -U '${username}' -c 'CREATE DATABASE finance_db;'" "Create finance_db database" "true"; then
    log_error "Failed to create finance_db database"
    exit 4
fi

# Drop and recreate finance_test_db
if ! execute_cmd "psql -h '${server}' -p '${port}' -d postgres -U '${username}' -c 'DROP DATABASE IF EXISTS finance_test_db;'" "Drop finance_test_db database" "true"; then
    log_error "Failed to drop finance_test_db database"
    exit 4
fi

if ! execute_cmd "psql -h '${server}' -p '${port}' -d postgres -U '${username}' -c 'CREATE DATABASE finance_test_db;'" "Create finance_test_db database" "true"; then
    log_error "Failed to create finance_test_db database"
    exit 4
fi

# Restore to finance_db
log_msg "Restoring data to finance_db database..."
if ! execute_cmd "pg_restore -h '${server}' -p '${port}' -U '${username}' -F t -d finance_db --verbose '${restore_filename}'" "Restore to finance_db" "true"; then
    log_error "Failed to restore to finance_db"
    exit 5
fi

# Restore to finance_test_db
log_msg "Restoring data to finance_test_db database..."
if ! execute_cmd "pg_restore -h '${server}' -p '${port}' -U '${username}' -F t -d finance_test_db --verbose '${restore_filename}'" "Restore to finance_test_db" "true"; then
    log_error "Failed to restore to finance_test_db"
    exit 5
fi

# Verify restoration by checking key tables including new medical tables
log_msg "Verifying restoration - checking core tables..."
core_tables="t_account t_transaction t_category t_description"
for table in $core_tables; do
    count=$(psql -h "${server}" -p "${port}" -U "${username}" -d finance_db -t -c "SELECT COUNT(*) FROM ${table};" 2>/dev/null | tr -d ' ')
    if [ -n "$count" ] && [ "$count" -gt 0 ]; then
        log_msg "✅ Table $table: $count rows"
    else
        log_error "❌ Table $table: no data or table missing"
    fi
done

# Check medical tables (these may be empty but should exist)
log_msg "Verifying medical expense tables..."
medical_tables="t_medical_provider t_family_member t_medical_expense"
for table in $medical_tables; do
    if psql -h "${server}" -p "${port}" -U "${username}" -d finance_db -c "SELECT 1 FROM ${table} LIMIT 1;" >/dev/null 2>&1; then
        count=$(psql -h "${server}" -p "${port}" -U "${username}" -d finance_db -t -c "SELECT COUNT(*) FROM ${table};" 2>/dev/null | tr -d ' ')
        log_msg "✅ Table $table exists: $count rows"
    else
        log_msg "ℹ️  Table $table: does not exist (may not be in older backup files)"
    fi
done

# Final status reporting
log_msg "Restore process completed"
log_msg "Databases restored:"
log_msg "  - finance_db: $(psql -h "${server}" -p "${port}" -U "${username}" -d finance_db -t -c "SELECT COUNT(*) FROM t_transaction;" 2>/dev/null | tr -d ' ') transactions"
log_msg "  - finance_test_db: $(psql -h "${server}" -p "${port}" -U "${username}" -d finance_test_db -t -c "SELECT COUNT(*) FROM t_transaction;" 2>/dev/null | tr -d ' ') transactions"

if [ $exit_code -eq 0 ]; then
    log_msg "SUCCESS: All restore operations completed successfully"
else
    log_error "PARTIAL SUCCESS: Some operations failed (check log for details)"
fi

exit $exit_code
