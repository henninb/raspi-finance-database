#!/usr/bin/env python3
"""Finance database backup script.

Dumps finance_db from a source server, rebuilds finance_fresh_db on localhost
from the canonical schema + exported CSV data, then copies the archive to raspi.
"""

import argparse
import logging
import os
import platform
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
DEFAULT_PORT = 5432
DEFAULT_VERSION = "v17-1"
USERNAME = "henninb"
DATE = datetime.now().strftime("%Y-%m-%d")

# (table_name, select_columns, order_by_column)
STANDARD_TABLES: list[tuple[str, str, str]] = [
    (
        "t_description",
        "description_id, description_name, owner, active_status, date_updated, date_added",
        "description_id",
    ),
    (
        "t_account",
        (
            "account_id, account_name_owner, account_name, account_owner, account_type, active_status, "
            "payment_required, moniker, future, outstanding, cleared, date_closed, validation_date, owner, "
            "date_updated, date_added, billing_statement_close_day, billing_grace_period_days, "
            "billing_due_day_same_month, billing_due_day_next_month, billing_cycle_weekend_shift"
        ),
        "account_id",
    ),
    (
        "t_category",
        "category_id, category_name, owner, active_status, date_updated, date_added",
        "category_id",
    ),
    (
        "t_validation_amount",
        "validation_id, account_id, validation_date, transaction_state, amount, owner, active_status, date_updated, date_added",
        "validation_id",
    ),
    (
        "t_parameter",
        "parameter_id, parameter_name, parameter_value, owner, active_status, date_updated, date_added",
        "parameter_id",
    ),
    (
        "t_transaction",
        (
            "transaction_id, account_id, account_type, transaction_type, account_name_owner, guid, "
            "transaction_date, due_date, description, category, amount, transaction_state, reoccurring_type, "
            "active_status, notes, receipt_image_id, owner, date_updated, date_added"
        ),
        "transaction_id",
    ),
    (
        "t_pending_transaction",
        "pending_transaction_id, account_name_owner, transaction_date, description, amount, review_status, owner, date_added",
        "pending_transaction_id",
    ),
    (
        "t_transaction_categories",
        "category_id, transaction_id, owner, date_updated, date_added",
        "transaction_id",
    ),
    (
        "t_payment",
        "payment_id, source_account, destination_account, transaction_date, amount, guid_source, guid_destination, owner, active_status, date_updated, date_added",
        "payment_id",
    ),
    (
        "t_transfer",
        "transfer_id, source_account, destination_account, transaction_date, amount, guid_source, guid_destination, owner, active_status, date_updated, date_added",
        "transfer_id",
    ),
    (
        "t_receipt_image",
        "receipt_image_id, transaction_id, image, thumbnail, image_format_type, owner, active_status, date_updated, date_added",
        "receipt_image_id",
    ),
]

# (table_name, select_columns, order_by_column, csv_header, truncate_before_import)
OPTIONAL_TABLES: list[tuple[str, str, str, str, bool]] = [
    (
        "t_medical_provider",
        (
            "provider_id, provider_name, provider_type, specialty, npi, tax_id, address_line1, address_line2, "
            "city, state, zip_code, country, phone, fax, email, website, network_status, billing_name, notes, "
            "active_status, date_added, date_updated"
        ),
        "provider_id",
        (
            "provider_id,provider_name,provider_type,specialty,npi,tax_id,address_line1,address_line2,"
            "city,state,zip_code,country,phone,fax,email,website,network_status,billing_name,notes,"
            "active_status,date_added,date_updated"
        ),
        True,
    ),
    (
        "t_family_member",
        (
            "family_member_id, owner, member_name, relationship, date_of_birth, insurance_member_id, "
            "ssn_last_four, medical_record_number, active_status, date_added, date_updated"
        ),
        "family_member_id",
        (
            "family_member_id,owner,member_name,relationship,date_of_birth,insurance_member_id,"
            "ssn_last_four,medical_record_number,active_status,date_added,date_updated"
        ),
        True,
    ),
    (
        "t_medical_expense",
        (
            "medical_expense_id, transaction_id, provider_id, family_member_id, service_date, service_description, "
            "procedure_code, diagnosis_code, billed_amount, insurance_discount, insurance_paid, patient_responsibility, "
            "paid_date, is_out_of_network, claim_number, claim_status, active_status, date_added, date_updated, paid_amount, owner"
        ),
        "medical_expense_id",
        (
            "medical_expense_id,transaction_id,provider_id,family_member_id,service_date,service_description,"
            "procedure_code,diagnosis_code,billed_amount,insurance_discount,insurance_paid,patient_responsibility,"
            "paid_date,is_out_of_network,claim_number,claim_status,active_status,date_added,date_updated,paid_amount,owner"
        ),
        False,
    ),
    (
        "t_token_blacklist",
        "token_blacklist_id, token_hash, expires_at",
        "token_blacklist_id",
        "token_blacklist_id,token_hash,expires_at",
        False,
    ),
]

V11_MIGRATION = """
BEGIN;
ALTER TABLE public.t_medical_expense ALTER COLUMN transaction_id DROP NOT NULL;
ALTER TABLE public.t_medical_expense ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(12,2) DEFAULT 0.00 NOT NULL;
DO $$ BEGIN
    ALTER TABLE public.t_medical_expense ADD CONSTRAINT ck_paid_amount_non_negative CHECK (paid_amount >= 0);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
UPDATE public.t_medical_expense SET paid_amount = patient_responsibility WHERE transaction_id IS NOT NULL;
COMMIT;
""".strip()

V21_MIGRATION = """
BEGIN;
ALTER TABLE public.t_account
    ADD COLUMN IF NOT EXISTS billing_statement_close_day SMALLINT NULL,
    ADD COLUMN IF NOT EXISTS billing_grace_period_days   SMALLINT NULL,
    ADD COLUMN IF NOT EXISTS billing_due_day_same_month  SMALLINT NULL,
    ADD COLUMN IF NOT EXISTS billing_due_day_next_month  SMALLINT NULL,
    ADD COLUMN IF NOT EXISTS billing_cycle_weekend_shift TEXT     NULL;
DO $$ BEGIN
    ALTER TABLE public.t_account ADD CONSTRAINT ck_billing_statement_close_day
        CHECK (billing_statement_close_day BETWEEN 1 AND 31);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    ALTER TABLE public.t_account ADD CONSTRAINT ck_billing_grace_period_days
        CHECK (billing_grace_period_days BETWEEN 1 AND 60);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    ALTER TABLE public.t_account ADD CONSTRAINT ck_billing_due_day_same_month
        CHECK (billing_due_day_same_month BETWEEN 1 AND 31);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    ALTER TABLE public.t_account ADD CONSTRAINT ck_billing_due_day_next_month
        CHECK (billing_due_day_next_month BETWEEN 1 AND 31);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    ALTER TABLE public.t_account ADD CONSTRAINT ck_billing_cycle_weekend_shift
        CHECK (billing_cycle_weekend_shift IN ('back', 'forward', 'back_sat_only'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    ALTER TABLE public.t_account ADD CONSTRAINT ck_billing_due_method_exclusive CHECK (
        (CASE WHEN billing_grace_period_days IS NOT NULL THEN 1 ELSE 0 END +
         CASE WHEN billing_due_day_same_month IS NOT NULL THEN 1 ELSE 0 END +
         CASE WHEN billing_due_day_next_month IS NOT NULL THEN 1 ELSE 0 END) <= 1
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
COMMIT;
""".strip()

RESET_SEQUENCES_SQL = """
SELECT setval('public.t_receipt_image_receipt_image_id_seq',         COALESCE((SELECT MAX(receipt_image_id)         FROM public.t_receipt_image), 1));
SELECT setval('public.t_transaction_transaction_id_seq',              COALESCE((SELECT MAX(transaction_id)           FROM public.t_transaction), 1));
SELECT setval('public.t_payment_payment_id_seq',                      COALESCE((SELECT MAX(payment_id)               FROM public.t_payment), 1));
SELECT setval('public.t_account_account_id_seq',                      COALESCE((SELECT MAX(account_id)               FROM public.t_account), 1));
SELECT setval('public.t_category_category_id_seq',                    COALESCE((SELECT MAX(category_id)              FROM public.t_category), 1));
SELECT setval('public.t_description_description_id_seq',              COALESCE((SELECT MAX(description_id)           FROM public.t_description), 1));
SELECT setval('public.t_parameter_parameter_id_seq',                  COALESCE((SELECT MAX(parameter_id)             FROM public.t_parameter), 1));
SELECT setval('public.t_validation_amount_validation_id_seq',         COALESCE((SELECT MAX(validation_id)            FROM public.t_validation_amount), 1));
SELECT setval('public.t_transfer_transfer_id_seq',                    COALESCE((SELECT MAX(transfer_id)              FROM public.t_transfer), 1));
SELECT setval('public.t_pending_transaction_pending_transaction_id_seq', COALESCE((SELECT MAX(pending_transaction_id) FROM public.t_pending_transaction), 1));
SELECT setval('public.t_medical_provider_provider_id_seq',            COALESCE((SELECT MAX(provider_id)              FROM public.t_medical_provider), 1));
SELECT setval('public.t_family_member_family_member_id_seq',          COALESCE((SELECT MAX(family_member_id)         FROM public.t_family_member), 1));
SELECT setval('public.t_medical_expense_medical_expense_id_seq',      COALESCE((SELECT MAX(medical_expense_id)       FROM public.t_medical_expense), 1));
SELECT setval('public.t_token_blacklist_token_blacklist_id_seq',      COALESCE((SELECT MAX(token_blacklist_id)       FROM public.t_token_blacklist), 1));
commit;
""".strip()


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
def setup_logging(log_file: str) -> logging.Logger:
    logger = logging.getLogger("backup")
    logger.setLevel(logging.DEBUG)
    fmt = logging.Formatter("[%(asctime)s] %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
    for handler in (logging.FileHandler(log_file), logging.StreamHandler(sys.stdout)):
        handler.setFormatter(fmt)
        logger.addHandler(handler)
    return logger


# ---------------------------------------------------------------------------
# Low-level runners
# ---------------------------------------------------------------------------
def _handle_result(
    result: subprocess.CompletedProcess,
    description: str,
    logger: logging.Logger,
    allow_warnings: bool,
    extra_output: str = "",
) -> bool:
    combined = "\n".join(filter(None, [result.stdout or "", result.stderr or "", extra_output])).strip()

    if allow_warnings:
        for line in combined.splitlines():
            if "WARNING" in line or "NOTICE" in line:
                logger.info(f"Non-fatal: {line}")

    if result.returncode == 0:
        logger.info(f"SUCCESS: {description} completed")
        return True

    logger.error(f"{description} failed (exit {result.returncode})")
    if combined:
        logger.error(f"Output: {combined}")
    return False


def run_psql(
    host: str,
    port: int,
    user: str,
    db: str,
    sql: str,
    description: str,
    logger: logging.Logger,
    allow_warnings: bool = False,
) -> bool:
    """Execute SQL via psql stdin — avoids all shell quoting complexity."""
    cmd = ["psql", "-h", host, "-p", str(port), "-U", user, db]
    logger.info(f"Starting: {description}")
    logger.info(f"Command: {' '.join(cmd)}")
    result = subprocess.run(cmd, input=sql, capture_output=True, text=True)
    return _handle_result(result, description, logger, allow_warnings)


def run_psql_file(
    host: str,
    port: int,
    user: str,
    db: str,
    sql_file: Path,
    description: str,
    logger: logging.Logger,
    allow_warnings: bool = False,
) -> bool:
    cmd = ["psql", "-h", host, "-p", str(port), "-U", user, db]
    logger.info(f"Starting: {description}")
    logger.info(f"Command: {' '.join(cmd)} < {sql_file}")
    with sql_file.open() as fh:
        result = subprocess.run(cmd, stdin=fh, capture_output=True, text=True)
    return _handle_result(result, description, logger, allow_warnings)


def run_pg_dump(
    host: str,
    port: int,
    user: str,
    db: str,
    output: Path,
    description: str,
    logger: logging.Logger,
) -> bool:
    cmd = ["pg_dump", "-h", host, "-p", str(port), "-U", user, "-F", "t", "-d", db]
    logger.info(f"Starting: {description}")
    logger.info(f"Command: {' '.join(cmd)} > {output}")
    with output.open("wb") as fh:
        result = subprocess.run(cmd, stdout=fh, stderr=subprocess.PIPE)
    stderr = result.stderr.decode()
    if result.returncode == 0:
        logger.info(f"SUCCESS: {description} completed")
        return True
    logger.error(f"{description} failed (exit {result.returncode}): {stderr}")
    return False


def run_scp(source: Path, dest: str, description: str, logger: logging.Logger) -> bool:
    cmd = ["scp", "-p", str(source), dest]
    logger.info(f"Starting: {description}")
    logger.info(f"Command: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    return _handle_result(result, description, logger, allow_warnings=False)


# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
def check_dependencies(logger: logging.Logger) -> bool:
    logger.info("Checking for required dependencies")
    ok = True
    for tool in ("psql", "pg_dump"):
        if not shutil.which(tool):
            logger.error(f"{tool} not found — please install PostgreSQL client tools")
            ok = False
    if ok:
        logger.info("All required dependencies found")
    return ok


def check_pgpass(server: str, port: int, logger: logging.Logger) -> bool:
    pgpass = Path.home() / ".pgpass"
    if not pgpass.exists():
        logger.error("~/.pgpass not found. Create it with:")
        print(f"  {server}:{port}:finance_db:{USERNAME}:your_password")
        print(f"  {server}:{port}:finance_fresh_db:{USERNAME}:your_password")
        print("Then: chmod 600 ~/.pgpass")
        return False
    mode = oct(pgpass.stat().st_mode)[-3:]
    if mode != "600":
        logger.error(f"~/.pgpass has wrong permissions ({mode}). Run: chmod 600 ~/.pgpass")
        return False
    logger.info("pgpass file found with correct permissions")
    os.environ["PGPASSFILE"] = str(pgpass)
    return True


def test_db_connection(host: str, port: int, user: str, logger: logging.Logger) -> bool:
    logger.info(f"Testing database connectivity to {host}:{port}")
    result = subprocess.run(
        ["psql", "-h", host, "-p", str(port), "-U", user, "-d", "finance_db", "-c", "SELECT 1;"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        logger.error(f"Cannot connect to {host}:{port} as {user}")
        logger.error("Check: 1) server is running  2) network  3) ~/.pgpass credentials")
        return False
    logger.info("Database connectivity test successful")
    return True


def table_exists(host: str, port: int, user: str, db: str, table: str) -> bool:
    result = subprocess.run(
        ["psql", "-h", host, "-p", str(port), "-U", user, "-d", db,
         "-c", f"SELECT 1 FROM {table} LIMIT 1;"],
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


# ---------------------------------------------------------------------------
# File helpers
# ---------------------------------------------------------------------------
def generate_unique_filename(base: str, ext: str, logger: logging.Logger) -> str | None:
    filename = f"{base}.{ext}"
    for counter in range(1, 101):
        if not Path(filename).exists():
            return filename
        filename = f"{base}-{counter}.{ext}"
    logger.error("100+ backup files exist — please clean up old backups")
    return None


def check_file(filepath: str, logger: logging.Logger) -> bool:
    path = Path(filepath)
    if not path.exists():
        logger.error(f"File not found: {filepath}")
        return False
    if path.stat().st_size == 0:
        logger.error(f"File is empty: {filepath}")
        return False
    size = path.stat().st_size
    if path.suffix in (".tar", ".dump", ".gz", ".bz2"):
        logger.info(f"File verified: {filepath} ({size:,} bytes)")
    else:
        lines = sum(1 for _ in path.open(encoding="utf-8"))
        logger.info(f"File verified: {filepath} ({lines} lines)")
    return True


def cleanup_on_failure(
    finance_db_file: str | None,
    finance_fresh_db_file: str | None,
    logger: logging.Logger,
) -> None:
    logger.info("Cleaning up partial backup files due to failure...")
    for f in filter(None, [finance_db_file, finance_fresh_db_file]):
        p = Path(f)
        if p.exists():
            p.unlink()
            logger.info(f"Removed: {f}")
    for csv in Path(".").glob("t_*.csv"):
        csv.unlink()
    logger.info("Cleanup completed (all t_*.csv files removed)")


# ---------------------------------------------------------------------------
# Server detection
# ---------------------------------------------------------------------------
def detect_local_server() -> str:
    if platform.system() == "Darwin":
        result = subprocess.run(["ipconfig", "getifaddr", "en0"], capture_output=True, text=True)
        return result.stdout.strip()
    result = subprocess.run(
        "ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/'",
        shell=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


# ---------------------------------------------------------------------------
# Table export/import
# ---------------------------------------------------------------------------
def export_import_table(
    server: str,
    port: int,
    table: str,
    columns: str,
    order_by: str,
    csv_file: str,
    logger: logging.Logger,
    finance_db_file: str | None,
    finance_fresh_db_file: str | None,
    truncate_first: bool = False,
) -> bool:
    export_sql = rf"\copy (SELECT {columns} FROM {table} ORDER BY {order_by}) TO '{csv_file}' CSV HEADER"
    if not run_psql(server, port, USERNAME, "finance_db", export_sql, f"Export {table}", logger):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger)
        return False

    if not check_file(csv_file, logger):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger)
        return False

    if truncate_first:
        if not run_psql(
            "localhost", port, USERNAME, "finance_fresh_db",
            f"TRUNCATE TABLE {table} CASCADE; commit",
            f"Truncate {table}",
            logger,
        ):
            cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger)
            return False

    import_sql = rf"\copy {table} FROM '{csv_file}' CSV HEADER; commit"
    if not run_psql(
        "localhost", port, USERNAME, "finance_fresh_db",
        import_sql, f"Import {table}", logger
    ):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger)
        return False

    return True


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Finance database backup script",
        epilog="Example: %(prog)s 192.168.10.25 5432 v18-1",
    )
    parser.add_argument("server", nargs="?", help="Source database server (default: auto-detect)")
    parser.add_argument("port", nargs="?", type=int, default=DEFAULT_PORT, help=f"Port (default: {DEFAULT_PORT})")
    parser.add_argument("version", nargs="?", default=DEFAULT_VERSION, help=f"Version label (default: {DEFAULT_VERSION})")
    return parser.parse_args()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    args = parse_args()

    log_file = f"finance-db-backup-{DATE}.log"
    logger = setup_logging(log_file)
    logger.info(f"Starting backup script: {Path(sys.argv[0]).name}")
    logger.info(f"Log file: {log_file}")

    server = args.server or detect_local_server()
    port: int = args.port
    version: str = args.version

    if not check_dependencies(logger):
        return 2

    logger.info(f"Configuration — server: {server}, port: {port}, version: {version}, user: {USERNAME}")
    logger.info("Reminder: use matching pg_dump/psql binaries for the target PostgreSQL version")

    if not check_pgpass(server, port, logger):
        return 1

    if not test_db_connection(server, port, USERNAME, logger):
        return 3

    if server not in ("localhost", "127.0.0.1"):
        if not test_db_connection("localhost", port, USERNAME, logger):
            return 3

    # --- Unique backup filenames ---
    logger.info("Generating unique backup filenames...")
    finance_db_file = generate_unique_filename(f"finance_db-{version}-{DATE}", "tar", logger)
    finance_fresh_db_file = generate_unique_filename(f"finance_fresh_db-{version}-{DATE}", "tar", logger)
    if not finance_db_file or not finance_fresh_db_file:
        return 4

    logger.info(f"  Main DB:   {finance_db_file}")
    logger.info(f"  Fresh DB:  {finance_fresh_db_file}")

    # --- Dump source finance_db ---
    if not run_pg_dump(server, port, USERNAME, "finance_db", Path(finance_db_file), "Create finance_db dump", logger):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger)
        return 4

    if not check_file(finance_db_file, logger):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger)
        return 4

    # --- Rebuild finance_fresh_db from schema ---
    logger.info("Rebuilding finance_fresh_db with latest schema...")

    if not run_psql(
        "localhost", port, USERNAME, "postgres",
        "DROP DATABASE IF EXISTS finance_fresh_db;",
        "Drop existing finance_fresh_db",
        logger, allow_warnings=True,
    ):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger)
        return 5

    schema_file = Path("finance_fresh_db-create.sql")
    if not run_psql_file(
        "localhost", port, USERNAME, "postgres",
        schema_file,
        "Create finance_fresh_db from schema",
        logger, allow_warnings=True,
    ):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger)
        return 5

    if not run_psql(
        "localhost", port, USERNAME, "finance_fresh_db",
        "SELECT 1;",
        "Verify finance_fresh_db creation",
        logger, allow_warnings=True,
    ):
        logger.error("finance_fresh_db was not created successfully")
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger)
        return 5

    # --- Apply migrations ---
    logger.info("Applying V11 migration...")
    if not run_psql(
        "localhost", port, USERNAME, "finance_fresh_db",
        V11_MIGRATION, "Apply V11 migration", logger, allow_warnings=True,
    ):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger)
        return 5

    logger.info("Applying V21 migration...")
    if not run_psql(
        "localhost", port, USERNAME, "finance_fresh_db",
        V21_MIGRATION, "Apply V21 migration", logger, allow_warnings=True,
    ):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger)
        return 5

    # --- Verify medical tables (informational, non-fatal) ---
    logger.info("Listing all tables in finance_fresh_db:")
    run_psql(
        "localhost", port, USERNAME, "finance_fresh_db",
        r"\dt public.t_*",
        "List tables in finance_fresh_db",
        logger, allow_warnings=True,
    )
    for tbl in ("t_medical_provider", "t_family_member", "t_medical_expense"):
        if table_exists("localhost", port, USERNAME, "finance_fresh_db", tbl):
            logger.info(f"{tbl} exists and is accessible")
        else:
            logger.info(f"{tbl} not accessible (will be handled during export phase)")

    # --- Export/import data ---
    logger.info("Starting table data export and import process")

    if not run_psql(
        "localhost", port, USERNAME, "finance_fresh_db",
        "ALTER TABLE t_transaction DROP CONSTRAINT IF EXISTS fk_receipt_image; commit",
        "Drop fk_receipt_image constraint",
        logger,
    ):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger)
        return 6

    for table, columns, order_by in STANDARD_TABLES:
        if not export_import_table(
            server, port, table, columns, order_by,
            f"{table}.csv", logger, finance_db_file, finance_fresh_db_file,
        ):
            return 6

    for table, columns, order_by, csv_header, truncate_first in OPTIONAL_TABLES:
        logger.info(f"Checking if {table} exists in source database...")
        if table_exists(server, port, USERNAME, "finance_db", table):
            logger.info(f"{table} found — exporting...")
            if not export_import_table(
                server, port, table, columns, order_by,
                f"{table}.csv", logger, finance_db_file, finance_fresh_db_file,
                truncate_first=truncate_first,
            ):
                return 6
        else:
            logger.info(f"{table} not found — writing empty CSV placeholder")
            Path(f"{table}.csv").write_text(csv_header + "\n")

    # --- Restore FK constraint ---
    if not run_psql(
        "localhost", port, USERNAME, "finance_fresh_db",
        (
            "ALTER TABLE t_transaction ADD CONSTRAINT fk_receipt_image "
            "FOREIGN KEY (receipt_image_id) REFERENCES t_receipt_image (receipt_image_id) "
            "ON DELETE CASCADE; commit"
        ),
        "Restore fk_receipt_image constraint",
        logger,
    ):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger)
        return 6

    # --- Reset sequences ---
    logger.info("Resetting database sequences...")
    if not run_psql(
        "localhost", port, USERNAME, "finance_fresh_db",
        RESET_SEQUENCES_SQL,
        "Reset all sequences",
        logger, allow_warnings=True,
    ):
        logger.warning("Sequence reset had warnings (non-fatal)")

    # --- Dump fresh database ---
    if not run_pg_dump(
        "localhost", port, USERNAME, "finance_fresh_db",
        Path(finance_fresh_db_file), "Create finance_fresh_db dump", logger,
    ):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger)
        return 7

    if not check_file(finance_fresh_db_file, logger):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger)
        return 7

    # --- Copy to remote ---
    exit_code = 0
    logger.info("Copying backup to remote server raspi")
    if not run_scp(
        Path(finance_db_file),
        "raspi:/home/pi/downloads/finance-db-bkp/",
        "Copy backup to raspi",
        logger,
    ):
        logger.error("Remote copy failed — backup files are still available locally")
        exit_code = 1

    # --- Summary ---
    logger.info("Backup process completed")
    logger.info("Files created:")
    for f in (finance_db_file, finance_fresh_db_file):
        size = Path(f).stat().st_size
        logger.info(f"  {f}  ({size:,} bytes)")
    csv_count = len(list(Path(".").glob("t_*.csv")))
    logger.info(f"CSV files exported: {csv_count}")

    if exit_code == 0:
        logger.info("SUCCESS: All backup operations completed successfully")
    else:
        logger.error("PARTIAL SUCCESS: Some operations failed — check log for details")

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
