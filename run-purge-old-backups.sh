#!/bin/sh

# POSIX-compliant purge script with logging and error handling
# Removes finance_db*.tar backups older than the retention period in current dir

# Strict mode (avoid unset vars and stop on errors in simple commands)
set -eu

# Configuration
RETENTION_DAYS=${RETENTION_DAYS:-60}
PATTERN=${PATTERN:-'finance_db*.tar'}

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

# Ensure we always clean up temp file if created
TMP_LIST=._purge_list_$$.txt
cleanup() {
    # Best-effort cleanup
    [ -f "$TMP_LIST" ] && rm -f "$TMP_LIST" || :
}
trap cleanup EXIT HUP INT TERM

log_msg "Starting purge script: $script_name"
log_msg "Retention: ${RETENTION_DAYS} days; Pattern: ${PATTERN}"

# Find candidate files (limit to current directory; avoid -maxdepth for POSIX)
# Using -prune to stay within '.' only
if ! find . -type d ! -name . -prune -o -type f -name "$PATTERN" -mtime "+${RETENTION_DAYS}" -print > "$TMP_LIST" 2>/dev/null; then
    log_error "find command failed while searching for old backups"
    exit "$exit_code"
fi

# Count and report
COUNT=0
if [ -s "$TMP_LIST" ]; then
    COUNT=$(wc -l < "$TMP_LIST")
    log_msg "Found $COUNT old backup(s) eligible for deletion:"
    # List files for visibility
    while IFS= read -r f; do
        # Trim leading ./ for readability
        case "$f" in
            ./*) log_msg "  - ${f#./}" ;;
            *)   log_msg "  - $f" ;;
        esac
    done < "$TMP_LIST"
else
    log_msg "No backups older than ${RETENTION_DAYS} days found; nothing to delete."
    exit 0
fi

# Delete files one by one to capture individual failures
DEL_ERRORS=0
while IFS= read -r f; do
    if [ -f "$f" ]; then
        if rm "$f" 2>/dev/null; then
            log_msg "Deleted: ${f#./}"
        else
            log_error "Failed to delete: ${f#./}"
            DEL_ERRORS=1
        fi
    else
        # File disappeared between find and delete; log and continue
        log_error "Skipped (not found): ${f#./}"
        DEL_ERRORS=1
    fi
done < "$TMP_LIST"

if [ "$DEL_ERRORS" -eq 0 ]; then
    log_msg "Purge completed successfully (deleted $COUNT file(s))."
    exit 0
else
    log_error "Purge completed with some errors (see above)."
    exit 1
fi
