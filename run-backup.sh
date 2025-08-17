#!/bin/sh

# Global variables
date=$(date '+%Y-%m-%d')
port=5432
version=v17-1
username=henninb
script_name="$(basename "$0")"
log_file="finance-db-backup-${date}.log"
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

# Cleanup function for failed backups
cleanup_on_failure() {
    log_msg "Cleaning up partial backup files due to failure..."
    rm -f "finance_db-${version}-${date}.tar" 2>/dev/null
    rm -f "finance_fresh_db-${version}-${date}.tar" 2>/dev/null
    rm -f t_*.csv 2>/dev/null
    log_msg "Cleanup completed"
}

# Check if file exists and has content
check_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        log_error "File not found: $file"
        return 1
    elif [ ! -s "$file" ]; then
        log_error "File is empty: $file"
        return 1
    else
        log_msg "File verified: $file ($(wc -l < "$file") lines)"
        return 0
    fi
}

log_msg "Starting backup script: $script_name"
log_msg "Log file: $log_file"

# Test database connectivity
test_db_connection() {
    local test_server="$1"
    local test_port="$2"
    local test_user="$3"
    
    log_msg "Testing database connectivity to ${test_server}:${test_port}"
    
    if ! psql -h "$test_server" -p "$test_port" -U "$test_user" -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
        log_error "Cannot connect to database at ${test_server}:${test_port} with user ${test_user}"
        log_error "Please check: 1) Server is running 2) Network connectivity 3) Credentials in ~/.pgpass"
        return 1
    else
        log_msg "Database connectivity test successful"
        return 0
    fi
}

if [ "$OS" = "Darwin" ]; then
  server=$(ipconfig getifaddr en0)
else
  # server=$(hostname -i | awk '{print $1}')
  server=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
fi

log_msg "Checking command line arguments (received $# arguments)"

if [ $# -ne 1 ] && [ $# -ne 2 ] && [ $# -ne 3 ]; then
  log_error "Invalid number of arguments"
  echo "Usage: $0 [server] [port] [version]"
  echo "$0 192.168.10.25 5432 v16-1"
  exit 1
fi

log_msg "Checking for required dependencies"
if [ ! -x "$(command -v psql)" ]; then
  log_error "psql command not found - please install PostgreSQL client tools"
  exit 2
fi

if [ ! -x "$(command -v pg_dump)" ]; then
  log_error "pg_dump command not found - please install PostgreSQL client tools"
  exit 2
fi

log_msg "All required dependencies found"

log_msg "Processing command line parameters"

if [ -n "$1" ]; then
  server=$1
  log_msg "Server set from argument 1: $server"
fi

if [ -n "$2" ]; then
  port=$2
  log_msg "Port set from argument 2: $port"
fi

if [ -n "$3" ]; then
  version=$3
  log_msg "Version set from argument 3: $version"
fi

log_msg "Final configuration - Server: '$server', Port: '$port', Version: '$version', User: '$username'"

log_msg "Reminder: both dump and restore should be performed using the latest binaries"
log_msg "Example: migrate from version 17.3 to 17.5 - use pg_dump binary for 17.5 to connect to 17.3"

log_msg "Checking for ~/.pgpass file"
if [ ! -f "$HOME/.pgpass" ]; then
  log_error "~/.pgpass file not found. Please create it with the format:"
  echo "${server}:${port}:finance_db:${username}:your_password"
  echo "${server}:${port}:finance_fresh_db:${username}:your_password"
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

# Test connectivity to source database
if ! test_db_connection "$server" "$port" "$username"; then
    log_error "Failed to connect to source database"
    exit 3
fi

# Test connectivity to localhost if different from source
if [ "$server" != "localhost" ] && [ "$server" != "127.0.0.1" ]; then
    if ! test_db_connection "localhost" "$port" "$username"; then
        log_error "Failed to connect to localhost database"
        exit 3
    fi
fi

log_msg "Starting main backup process"

# Create main database dump
if ! execute_cmd "pg_dump -h '${server}' -p '${port}' -U '${username}' -F t -d finance_db > 'finance_db-${version}-${date}.tar'" "Create finance_db dump"; then
    cleanup_on_failure
    exit 4
fi

# Verify dump file was created and has content
if ! check_file "finance_db-${version}-${date}.tar"; then
    cleanup_on_failure
    exit 4
fi

# Create fresh database on localhost (warnings are non-fatal)
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' postgres < finance_fresh_db-create.sql" "Create finance_fresh_db on localhost" "true"; then
    cleanup_on_failure
    exit 5
fi

# Verify that the fresh database was created successfully
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' -d finance_fresh_db -c 'SELECT 1;'" "Verify finance_fresh_db creation" "true"; then
    log_error "finance_fresh_db was not created successfully"
    cleanup_on_failure
    exit 5
fi

log_msg "Starting table data export and import process"

# Export and import description table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' finance_db -c \"\\copy (SELECT description_id, description_name, owner, active_status, date_updated, date_added from t_description ORDER BY description_id) TO 't_description.csv' CSV HEADER\"" "Export t_description table"; then
    cleanup_on_failure
    exit 6
fi

if ! check_file "t_description.csv"; then
    cleanup_on_failure
    exit 6
fi

if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"ALTER TABLE t_transaction DROP CONSTRAINT IF EXISTS fk_receipt_image; commit\"" "Drop fk_receipt_image constraint"; then
    cleanup_on_failure
    exit 6
fi

if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"\\copy t_description FROM 't_description.csv' CSV HEADER; commit\"" "Import t_description table"; then
    cleanup_on_failure
    exit 6
fi

# Export and import account table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' finance_db -c \"\\copy (SELECT account_id, account_name_owner, account_name, account_owner, account_type, active_status, payment_required, moniker, future, outstanding, cleared, date_closed, validation_date, owner, date_updated, date_added from t_account ORDER BY account_id) TO 't_account.csv' CSV HEADER\"" "Export t_account table"; then
    cleanup_on_failure
    exit 6
fi
if ! check_file "t_account.csv"; then cleanup_on_failure; exit 6; fi
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"\\copy t_account FROM 't_account.csv' CSV HEADER; commit\"" "Import t_account table"; then
    cleanup_on_failure
    exit 6
fi

# Export and import category table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' finance_db -c \"\\copy (SELECT category_id, category_name, owner, active_status, date_updated, date_added from t_category ORDER BY category_id) TO 't_category.csv' CSV HEADER\"" "Export t_category table"; then
    cleanup_on_failure
    exit 6
fi
if ! check_file "t_category.csv"; then cleanup_on_failure; exit 6; fi
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"\\copy t_category FROM 't_category.csv' CSV HEADER; commit\"" "Import t_category table"; then
    cleanup_on_failure
    exit 6
fi

# Export and import validation_amount table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' finance_db -c \"\\copy (SELECT validation_id, account_id, validation_date, transaction_state, amount, owner, active_status, date_updated, date_added FROM t_validation_amount ORDER BY validation_id) TO 't_validation_amount.csv' CSV HEADER\"" "Export t_validation_amount table"; then
    cleanup_on_failure
    exit 6
fi
if ! check_file "t_validation_amount.csv"; then cleanup_on_failure; exit 6; fi
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"\\copy t_validation_amount FROM 't_validation_amount.csv' CSV HEADER; commit\"" "Import t_validation_amount table"; then
    cleanup_on_failure
    exit 6
fi

# Export and import parameter table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' finance_db -c \"\\copy (SELECT parameter_id, parameter_name, parameter_value, owner, active_status, date_updated, date_added from t_parameter ORDER BY parameter_id) TO 't_parameter.csv' CSV HEADER\"" "Export t_parameter table"; then
    cleanup_on_failure
    exit 6
fi
if ! check_file "t_parameter.csv"; then cleanup_on_failure; exit 6; fi
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"\\copy t_parameter FROM 't_parameter.csv' CSV HEADER; commit\"" "Import t_parameter table"; then
    cleanup_on_failure
    exit 6
fi

# Export and import transaction table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' finance_db -c \"\\copy (SELECT transaction_id, account_id, account_type, transaction_type, account_name_owner, guid, transaction_date, due_date, description, category, amount, transaction_state, reoccurring_type, active_status, notes, receipt_image_id, owner, date_updated, date_added from t_transaction ORDER BY transaction_id) TO 't_transaction.csv' CSV HEADER\"" "Export t_transaction table"; then
    cleanup_on_failure
    exit 6
fi
if ! check_file "t_transaction.csv"; then cleanup_on_failure; exit 6; fi
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"\\copy t_transaction FROM 't_transaction.csv' CSV HEADER; commit\"" "Import t_transaction table"; then
    cleanup_on_failure
    exit 6
fi

# Export and import pending_transaction table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' finance_db -c \"\\copy (SELECT pending_transaction_id, account_name_owner, transaction_date, description, amount, review_status, owner, date_added FROM t_pending_transaction ORDER BY pending_transaction_id) TO 't_pending_transaction.csv' CSV HEADER\"" "Export t_pending_transaction table"; then
    cleanup_on_failure
    exit 6
fi
if ! check_file "t_pending_transaction.csv"; then cleanup_on_failure; exit 6; fi
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"\\copy t_pending_transaction FROM 't_pending_transaction.csv' CSV HEADER; commit\"" "Import t_pending_transaction table"; then
    cleanup_on_failure
    exit 6
fi

# Export and import transaction_categories table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' finance_db -c \"\\copy (SELECT category_id, transaction_id, owner, date_updated, date_added from t_transaction_categories ORDER BY transaction_id) TO 't_transaction_categories.csv' CSV HEADER\"" "Export t_transaction_categories table"; then
    cleanup_on_failure
    exit 6
fi
if ! check_file "t_transaction_categories.csv"; then cleanup_on_failure; exit 6; fi
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"\\copy t_transaction_categories FROM 't_transaction_categories.csv' CSV HEADER; commit\"" "Import t_transaction_categories table"; then
    cleanup_on_failure
    exit 6
fi

# Export and import payment table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' finance_db -c \"\\copy (SELECT payment_id, source_account, destination_account, transaction_date, amount, guid_source, guid_destination, owner, active_status, date_updated, date_added from t_payment ORDER BY payment_id) TO 't_payment.csv' CSV HEADER\"" "Export t_payment table"; then
    cleanup_on_failure
    exit 6
fi
if ! check_file "t_payment.csv"; then cleanup_on_failure; exit 6; fi
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"\\copy t_payment FROM 't_payment.csv' CSV HEADER; commit\"" "Import t_payment table"; then
    cleanup_on_failure
    exit 6
fi

# Export and import transfer table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' finance_db -c \"\\copy (SELECT transfer_id, source_account, destination_account, transaction_date, amount, guid_source, guid_destination, owner, active_status, date_updated, date_added from t_transfer ORDER BY transfer_id) TO 't_transfer.csv' CSV HEADER\"" "Export t_transfer table"; then
    cleanup_on_failure
    exit 6
fi
if ! check_file "t_transfer.csv"; then cleanup_on_failure; exit 6; fi
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"\\copy t_transfer FROM 't_transfer.csv' CSV HEADER; commit\"" "Import t_transfer table"; then
    cleanup_on_failure
    exit 6
fi

# Export and import receipt_image table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' finance_db -c \"\\copy (SELECT receipt_image_id, transaction_id, image, thumbnail, image_format_type, owner, active_status, date_updated, date_added from t_receipt_image ORDER BY receipt_image_id) TO 't_receipt_image.csv' CSV HEADER\"" "Export t_receipt_image table"; then
    cleanup_on_failure
    exit 6
fi
if ! check_file "t_receipt_image.csv"; then cleanup_on_failure; exit 6; fi
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"\\copy t_receipt_image FROM 't_receipt_image.csv' CSV HEADER; commit\"" "Import t_receipt_image table"; then
    cleanup_on_failure
    exit 6
fi

# Add foreign key constraint back
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"alter table t_transaction add CONSTRAINT fk_receipt_image FOREIGN KEY (receipt_image_id) REFERENCES t_receipt_image (receipt_image_id) ON DELETE CASCADE; commit\"" "Add fk_receipt_image constraint"; then
    cleanup_on_failure
    exit 6
fi

# Create final dump of fresh database
if ! execute_cmd "pg_dump -h localhost -p '${port}' -U '${username}' -F t -d finance_fresh_db > 'finance_fresh_db-${version}-${date}.tar'" "Create finance_fresh_db dump"; then
    cleanup_on_failure
    exit 7
fi

# Verify final dump file was created and has content
if ! check_file "finance_fresh_db-${version}-${date}.tar"; then
    cleanup_on_failure
    exit 7
fi

# Copy backup to remote server
log_msg "Copying backup to remote server raspi"
if ! execute_cmd "scp -p 'finance_db-${version}-${date}.tar' raspi:/home/pi/downloads/finance-db-bkp/" "Copy backup to raspi server"; then
    log_error "Failed to copy backup to remote server, but backup files are available locally"
    exit_code=1
fi

# Final status reporting
log_msg "Backup process completed"
log_msg "Files created:"
log_msg "  - finance_db-${version}-${date}.tar ($(ls -lh "finance_db-${version}-${date}.tar" | awk '{print $5}'))"
log_msg "  - finance_fresh_db-${version}-${date}.tar ($(ls -lh "finance_fresh_db-${version}-${date}.tar" | awk '{print $5}'))"
log_msg "CSV files exported: $(ls -1 t_*.csv | wc -l) files"

if [ $exit_code -eq 0 ]; then
    log_msg "SUCCESS: All backup operations completed successfully"
else
    log_error "PARTIAL SUCCESS: Some operations failed (check log for details)"
fi

exit $exit_code
