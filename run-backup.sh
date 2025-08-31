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
    log_msg "Cleanup completed (includes all CSV files: description, account, category, validation_amount, parameter, transaction, pending_transaction, transaction_categories, payment, transfer, receipt_image, medical_provider, family_member, medical_expense)"
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

    if ! psql -h "$test_server" -p "$test_port" -U "$test_user" -d finance_db -c "SELECT 1;" >/dev/null 2>&1; then
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

# Drop and recreate fresh database on localhost to ensure clean schema (warnings are non-fatal)
log_msg "Ensuring clean finance_fresh_db database with latest schema..."
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' postgres -c 'DROP DATABASE IF EXISTS finance_fresh_db;'" "Drop existing finance_fresh_db" "true"; then
    cleanup_on_failure
    exit 5
fi

# Create fresh database with complete schema from finance_fresh_db-create.sql (warnings are non-fatal)
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' postgres < finance_fresh_db-create.sql" "Create finance_fresh_db with complete schema" "true"; then
    cleanup_on_failure
    exit 5
fi

# Verify that the fresh database was created successfully
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' -d finance_fresh_db -c 'SELECT 1;'" "Verify finance_fresh_db creation" "true"; then
    log_error "finance_fresh_db was not created successfully"
    cleanup_on_failure
    exit 5
fi

# Apply V11 migration to ensure schema is up to date
log_msg "Applying V11 migration to ensure fresh database has current schema..."
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' -d finance_fresh_db -c \"
BEGIN;
ALTER TABLE public.t_medical_expense ALTER COLUMN transaction_id DROP NOT NULL;
ALTER TABLE public.t_medical_expense ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(12,2) DEFAULT 0.00 NOT NULL;
DO \\\$\\\$ BEGIN
    ALTER TABLE public.t_medical_expense ADD CONSTRAINT ck_paid_amount_non_negative CHECK (paid_amount >= 0);
EXCEPTION
    WHEN duplicate_object THEN
        -- Constraint already exists, ignore
        NULL;
END \\\$\\\$;
UPDATE public.t_medical_expense SET paid_amount = patient_responsibility WHERE transaction_id IS NOT NULL;
COMMIT;\"" "Apply V11 migration to fresh database" "true"; then
    log_error "Failed to apply V11 migration to fresh database"
    cleanup_on_failure
    exit 5
fi

# Verify new tables exist in fresh database (non-fatal verification)
log_msg "Verifying new medical expense tables exist in fresh database..."

# First check what tables exist in the database
log_msg "Listing all tables in finance_fresh_db database:"
execute_cmd "psql -h localhost -p '${port}' -U '${username}' -d finance_fresh_db -c \"\\dt public.t_*\"" "List all tables in finance_fresh_db" "true"

# Check specifically for medical tables (non-fatal - just for information)
log_msg "Checking for t_medical_provider table..."
if psql -h localhost -p "${port}" -U "${username}" -d finance_fresh_db -c "SELECT 1 FROM t_medical_provider LIMIT 1;" >/dev/null 2>&1; then
    log_msg "✅ t_medical_provider table exists and accessible"
else
    log_msg "ℹ️  t_medical_provider table verification failed (will be handled during export phase)"
fi

log_msg "Checking for t_family_member table..."
if psql -h localhost -p "${port}" -U "${username}" -d finance_fresh_db -c "SELECT 1 FROM t_family_member LIMIT 1;" >/dev/null 2>&1; then
    log_msg "✅ t_family_member table exists and accessible"
else
    log_msg "ℹ️  t_family_member table verification failed (will be handled during export phase)"
fi

log_msg "Checking for t_medical_expense table..."
if psql -h localhost -p "${port}" -U "${username}" -d finance_fresh_db -c "SELECT 1 FROM t_medical_expense LIMIT 1;" >/dev/null 2>&1; then
    log_msg "✅ t_medical_expense table exists and accessible"
else
    log_msg "ℹ️  t_medical_expense table verification failed (will be handled during export phase)"
fi

# Informational check - does not fail the backup
if psql -h localhost -p "${port}" -U "${username}" -d finance_fresh_db -c "SELECT 1 FROM t_medical_provider LIMIT 1; SELECT 1 FROM t_family_member LIMIT 1; SELECT 1 FROM t_medical_expense LIMIT 1;" >/dev/null 2>&1; then
    log_msg "✅ All medical expense tables verified successfully in fresh database"
else
    log_msg "ℹ️  Some medical expense tables may not exist in fresh database - will create empty CSV files as needed"

    # Check if finance_fresh_db-create.sql file exists and is readable
    if [ ! -f "finance_fresh_db-create.sql" ]; then
        log_msg "finance_fresh_db-create.sql file not found in current directory"
    else
        log_msg "finance_fresh_db-create.sql file exists ($(wc -l < finance_fresh_db-create.sql) lines)"

        # Show if medical table definitions exist in schema file
        log_msg "Checking for medical table definitions in schema file..."
        if grep -q "t_medical_provider\|t_family_member\|t_medical_expense" finance_fresh_db-create.sql; then
            log_msg "✅ Medical table definitions found in schema file"
        else
            log_msg "ℹ️  Medical table definitions NOT found in schema file"
        fi
    fi
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

# Export and import medical_provider table (Phase 1 - Medical Provider Entity)
# Check if source table exists before attempting export
log_msg "Checking if t_medical_provider table exists in source database..."
if psql -h "${server}" -p "${port}" -U "${username}" finance_db -c "SELECT 1 FROM t_medical_provider LIMIT 1;" >/dev/null 2>&1; then
    log_msg "t_medical_provider table found in source database, proceeding with export..."
    if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' finance_db -c \"\\copy (SELECT provider_id, provider_name, provider_type, specialty, npi, tax_id, address_line1, address_line2, city, state, zip_code, country, phone, fax, email, website, network_status, billing_name, notes, active_status, date_added, date_updated from t_medical_provider ORDER BY provider_id) TO 't_medical_provider.csv' CSV HEADER\"" "Export t_medical_provider table"; then
        cleanup_on_failure
        exit 6
    fi
    if ! check_file "t_medical_provider.csv"; then cleanup_on_failure; exit 6; fi
    # Truncate medical provider table to avoid primary key conflicts with seed data
    if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"TRUNCATE TABLE t_medical_provider CASCADE; commit\"" "Truncate t_medical_provider table"; then
        cleanup_on_failure
        exit 6
    fi
    if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"\\copy t_medical_provider FROM 't_medical_provider.csv' CSV HEADER; commit\"" "Import t_medical_provider table"; then
        cleanup_on_failure
        exit 6
    fi
else
    log_msg "t_medical_provider table not found in source database - creating empty CSV file..."
    echo "provider_id,provider_name,provider_type,specialty,npi,tax_id,address_line1,address_line2,city,state,zip_code,country,phone,fax,email,website,network_status,billing_name,notes,active_status,date_added,date_updated" > t_medical_provider.csv
    log_msg "Empty t_medical_provider.csv created (table will use default seed data from schema)"
fi

# Export and import family_member table (Phase 1.5 - Family Member Entity)
# Check if source table exists before attempting export
log_msg "Checking if t_family_member table exists in source database..."
if psql -h "${server}" -p "${port}" -U "${username}" finance_db -c "SELECT 1 FROM t_family_member LIMIT 1;" >/dev/null 2>&1; then
    log_msg "t_family_member table found in source database, proceeding with export..."
    if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' finance_db -c \"\\copy (SELECT family_member_id, owner, member_name, relationship, date_of_birth, insurance_member_id, ssn_last_four, medical_record_number, active_status, date_added, date_updated from t_family_member ORDER BY family_member_id) TO 't_family_member.csv' CSV HEADER\"" "Export t_family_member table"; then
        cleanup_on_failure
        exit 6
    fi
    if ! check_file "t_family_member.csv"; then cleanup_on_failure; exit 6; fi
    # Truncate family member table to avoid primary key conflicts with seed data
    if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"TRUNCATE TABLE t_family_member CASCADE; commit\"" "Truncate t_family_member table"; then
        cleanup_on_failure
        exit 6
    fi
    if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"\\copy t_family_member FROM 't_family_member.csv' CSV HEADER; commit\"" "Import t_family_member table"; then
        cleanup_on_failure
        exit 6
    fi
else
    log_msg "t_family_member table not found in source database - creating empty CSV file..."
    echo "family_member_id,owner,member_name,relationship,date_of_birth,insurance_member_id,ssn_last_four,medical_record_number,active_status,date_added,date_updated" > t_family_member.csv
    log_msg "Empty t_family_member.csv created (table will use default seed data from schema)"
fi

# Export and import medical_expense table (Phase 2 - Medical Expense Entity)
# Check if source table exists before attempting export
log_msg "Checking if t_medical_expense table exists in source database..."
if psql -h "${server}" -p "${port}" -U "${username}" finance_db -c "SELECT 1 FROM t_medical_expense LIMIT 1;" >/dev/null 2>&1; then
    log_msg "t_medical_expense table found in source database, proceeding with export..."
    if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' finance_db -c \"\\copy (SELECT medical_expense_id, transaction_id, provider_id, family_member_id, service_date, service_description, procedure_code, diagnosis_code, billed_amount, insurance_discount, insurance_paid, patient_responsibility, paid_date, is_out_of_network, claim_number, claim_status, active_status, date_added, date_updated, paid_amount from t_medical_expense ORDER BY medical_expense_id) TO 't_medical_expense.csv' CSV HEADER\"" "Export t_medical_expense table"; then
        cleanup_on_failure
        exit 6
    fi
    if ! check_file "t_medical_expense.csv"; then cleanup_on_failure; exit 6; fi
    if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"\\copy t_medical_expense FROM 't_medical_expense.csv' CSV HEADER; commit\"" "Import t_medical_expense table"; then
        cleanup_on_failure
        exit 6
    fi
else
    log_msg "t_medical_expense table not found in source database - creating empty CSV file..."
    echo "medical_expense_id,transaction_id,provider_id,family_member_id,service_date,service_description,procedure_code,diagnosis_code,billed_amount,insurance_discount,insurance_paid,patient_responsibility,paid_date,is_out_of_network,claim_number,claim_status,active_status,date_added,date_updated,paid_amount" > t_medical_expense.csv
    log_msg "Empty t_medical_expense.csv created (table will use default data from schema)"
fi

# Add foreign key constraint back
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"alter table t_transaction add CONSTRAINT fk_receipt_image FOREIGN KEY (receipt_image_id) REFERENCES t_receipt_image (receipt_image_id) ON DELETE CASCADE; commit\"" "Add fk_receipt_image constraint"; then
    cleanup_on_failure
    exit 6
fi

# Reset sequences for all tables including new medical expense tables
log_msg "Resetting database sequences to match imported data..."
if ! execute_cmd "psql -h localhost -p '${port}' -U '${username}' finance_fresh_db -c \"
SELECT setval('public.t_receipt_image_receipt_image_id_seq', COALESCE((SELECT MAX(receipt_image_id) FROM public.t_receipt_image), 1));
SELECT setval('public.t_transaction_transaction_id_seq', COALESCE((SELECT MAX(transaction_id) FROM public.t_transaction), 1));
SELECT setval('public.t_payment_payment_id_seq', COALESCE((SELECT MAX(payment_id) FROM public.t_payment), 1));
SELECT setval('public.t_account_account_id_seq', COALESCE((SELECT MAX(account_id) FROM public.t_account), 1));
SELECT setval('public.t_category_category_id_seq', COALESCE((SELECT MAX(category_id) FROM public.t_category), 1));
SELECT setval('public.t_description_description_id_seq', COALESCE((SELECT MAX(description_id) FROM public.t_description), 1));
SELECT setval('public.t_parameter_parameter_id_seq', COALESCE((SELECT MAX(parameter_id) FROM public.t_parameter), 1));
SELECT setval('public.t_validation_amount_validation_id_seq', COALESCE((SELECT MAX(validation_id) FROM public.t_validation_amount), 1));
SELECT setval('public.t_transfer_transfer_id_seq', COALESCE((SELECT MAX(transfer_id) FROM public.t_transfer), 1));
SELECT setval('public.t_pending_transaction_pending_transaction_id_seq', COALESCE((SELECT MAX(pending_transaction_id) FROM public.t_pending_transaction), 1));
SELECT setval('public.t_medical_provider_provider_id_seq', COALESCE((SELECT MAX(provider_id) FROM public.t_medical_provider), 1));
SELECT setval('public.t_family_member_family_member_id_seq', COALESCE((SELECT MAX(family_member_id) FROM public.t_family_member), 1));
SELECT setval('public.t_medical_expense_medical_expense_id_seq', COALESCE((SELECT MAX(medical_expense_id) FROM public.t_medical_expense), 1));
commit;\"" "Reset all database sequences" "true"; then
    log_msg "Warning: Sequence reset completed with warnings (non-fatal)"
else
    log_msg "Successfully reset all database sequences"
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
log_msg "CSV files exported: $(ls -1 t_*.csv 2>/dev/null | wc -l) files (includes new medical_provider, family_member, and medical_expense tables)"

if [ $exit_code -eq 0 ]; then
    log_msg "SUCCESS: All backup operations completed successfully"
else
    log_error "PARTIAL SUCCESS: Some operations failed (check log for details)"
fi

exit $exit_code
