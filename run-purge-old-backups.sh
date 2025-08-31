#!/bin/sh

# POSIX-compliant purge script with logging and error handling
# Removes finance_db-*.tar backups older than the retention period in current dir
# Removes ALL finance_fresh_db-*.tar backups regardless of age

# Strict mode (avoid unset vars and stop on errors in simple commands)
set -eu

# Configuration
RETENTION_DAYS=${RETENTION_DAYS:-60}
OLD_DB_PATTERN=${OLD_DB_PATTERN:-'finance_db-*.tar'}
FRESH_DB_PATTERN=${FRESH_DB_PATTERN:-'finance_fresh_db-*.tar'}

# Globals
date=$(date '+%Y-%m-%d')
script_name=$(basename "$0")
log_file="finance-db-backup-${date}.log"
exit_code=0

# Logging helpers (aligned with run-backup.sh)
log_msg() {
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    # shellcheck disable=SC3037
    echo "[$ts] $1" | tee -a "$log_file"
}

log_error() {
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    # shellcheck disable=SC3037
    echo "[$ts] ERROR: $1" | tee -a "$log_file" >&2
    exit_code=1
}

# Ensure we always clean up temp files if created
TMP_OLD_LIST=._purge_old_list_$$.txt
TMP_FRESH_LIST=._purge_fresh_list_$$.txt
cleanup() {
    # Best-effort cleanup
    [ -f "$TMP_OLD_LIST" ] && rm -f "$TMP_OLD_LIST" || :
    [ -f "$TMP_FRESH_LIST" ] && rm -f "$TMP_FRESH_LIST" || :
}
trap cleanup EXIT HUP INT TERM

log_msg "Starting purge script: $script_name"
log_msg "Retention: ${RETENTION_DAYS} days; Old DB pattern: ${OLD_DB_PATTERN}"
log_msg "Fresh DB pattern (all removed): ${FRESH_DB_PATTERN}"

# Find old finance_db-*.tar files (time-based removal)
if ! find . -type d ! -name . -prune -o -type f -name "$OLD_DB_PATTERN" -mtime "+${RETENTION_DAYS}" -print > "$TMP_OLD_LIST" 2>/dev/null; then
    log_error "find command failed while searching for old finance_db backups"
    exit "$exit_code"
fi

# Find ALL finance_fresh_db-*.tar files (remove regardless of age)
if ! find . -type d ! -name . -prune -o -type f -name "$FRESH_DB_PATTERN" -print > "$TMP_FRESH_LIST" 2>/dev/null; then
    log_error "find command failed while searching for finance_fresh_db backups"
    exit "$exit_code"
fi

# Count and report findings
OLD_COUNT=0
FRESH_COUNT=0
TOTAL_COUNT=0

if [ -s "$TMP_OLD_LIST" ]; then
    OLD_COUNT=$(wc -l < "$TMP_OLD_LIST")
    log_msg "Found $OLD_COUNT old finance_db backup(s) eligible for deletion (older than ${RETENTION_DAYS} days):"
    while IFS= read -r f; do
        case "$f" in
            ./*) log_msg "  - ${f#./}" ;;
            *)   log_msg "  - $f" ;;
        esac
    done < "$TMP_OLD_LIST"
fi

if [ -s "$TMP_FRESH_LIST" ]; then
    FRESH_COUNT=$(wc -l < "$TMP_FRESH_LIST")
    log_msg "Found $FRESH_COUNT finance_fresh_db backup(s) to delete (all removed regardless of age):"
    while IFS= read -r f; do
        case "$f" in
            ./*) log_msg "  - ${f#./}" ;;
            *)   log_msg "  - $f" ;;
        esac
    done < "$TMP_FRESH_LIST"
fi

TOTAL_COUNT=$((OLD_COUNT + FRESH_COUNT))

if [ "$TOTAL_COUNT" -eq 0 ]; then
    log_msg "No backups found for deletion; nothing to delete."
    exit 0
fi

# Delete files one by one to capture individual failures
DEL_ERRORS=0
DELETED_COUNT=0

# Function to delete files from a temp file
delete_files_from_list() {
    local temp_file="$1"
    local file_type="$2"
    
    if [ -s "$temp_file" ]; then
        while IFS= read -r f; do
            if [ -f "$f" ]; then
                if rm "$f" 2>/dev/null; then
                    log_msg "Deleted $file_type: ${f#./}"
                    DELETED_COUNT=$((DELETED_COUNT + 1))
                else
                    log_error "Failed to delete $file_type: ${f#./}"
                    DEL_ERRORS=1
                fi
            else
                # File disappeared between find and delete; log and continue
                log_error "Skipped $file_type (not found): ${f#./}"
                DEL_ERRORS=1
            fi
        done < "$temp_file"
    fi
}

# Delete old finance_db files
delete_files_from_list "$TMP_OLD_LIST" "old finance_db backup"

# Delete all finance_fresh_db files
delete_files_from_list "$TMP_FRESH_LIST" "finance_fresh_db backup"

if [ "$DEL_ERRORS" -eq 0 ]; then
    log_msg "Purge completed successfully (deleted $DELETED_COUNT file(s))."
    exit 0
else
    log_error "Purge completed with some errors (see above)."
    exit 1
fi
