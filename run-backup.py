#!/usr/bin/env python3
"""Finance database backup script.

Dumps finance_db from a source server, rebuilds finance_fresh_db on localhost
from the canonical schema + exported CSV data, then copies the archive to raspi.
"""

import argparse
import csv
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
DEFAULT_VERSION = "v18.4"
USERNAME = "henninb"
DATE = datetime.now().strftime("%Y-%m-%d")

# (table_name, order_by_column), in foreign-key dependency order.
# Columns are discovered from the database at run time, so they are not listed here.
STANDARD_TABLES: list[tuple[str, str]] = [
    ("t_role", "role_id"),
    ("t_user", "user_id"),
    ("t_description", "description_id"),
    ("t_account", "account_id"),
    ("t_category", "category_id"),
    ("t_validation_amount", "validation_id"),
    ("t_parameter", "parameter_id"),
    ("t_reward", "reward_id"),
    ("t_transaction", "transaction_id"),
    ("t_transaction_categories", "transaction_id"),
    ("t_payment", "payment_id"),
    ("t_transfer", "transfer_id"),
    ("t_receipt_image", "receipt_image_id"),
]

# (table_name, order_by_column, truncate_before_import)
# Exported only if the table exists in the source; truncate clears schema seed rows.
OPTIONAL_TABLES: list[tuple[str, str, bool]] = [
    ("t_medical_provider", "provider_id", True),
    ("t_family_member", "family_member_id", True),
    ("t_medical_expense", "medical_expense_id", False),
    ("t_token_blacklist", "token_blacklist_id", False),
]

# Source tables deliberately not copied into finance_fresh_db (Flyway bookkeeping).
# Any other source table missing from the lists above is reported.
EXCLUDED_TABLES = {"flyway_schema_history"}

# Sets every serial/identity sequence in public to MAX(column) of its owning table.
RESET_SEQUENCES_SQL = """
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT format('%I.%I', n.nspname, s.relname) AS seq,
               format('%I.%I', n.nspname, t.relname) AS tbl,
               a.attname AS col
        FROM pg_class s
        JOIN pg_namespace n ON n.oid = s.relnamespace
        JOIN pg_depend d ON d.objid = s.oid AND d.deptype IN ('a', 'i')
        JOIN pg_class t ON t.oid = d.refobjid
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
        WHERE s.relkind = 'S' AND n.nspname = 'public'
    LOOP
        EXECUTE format('SELECT setval(%L, COALESCE((SELECT MAX(%I) FROM %s), 1))', r.seq, r.col, r.tbl);
    END LOOP;
END $$;
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
    cmd = ["psql", "-v", "ON_ERROR_STOP=1", "-h", host, "-p", str(port), "-U", user, db]
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
    cmd = ["psql", "-v", "ON_ERROR_STOP=1", "-h", host, "-p", str(port), "-U", user, db]
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


def psql_query(host: str, port: int, user: str, db: str, sql: str) -> list[str]:
    """Run a read-only query and return its rows, raising on any failure."""
    result = subprocess.run(
        ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-h", host, "-p", str(port), "-U", user, "-d", db, "-tA", "-c", sql],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"query on {db}@{host} failed: {result.stderr.strip()}")
    return [line for line in result.stdout.splitlines() if line]


def table_columns(host: str, port: int, user: str, db: str, table: str) -> list[str]:
    return psql_query(
        host, port, user, db,
        "SELECT attname FROM pg_attribute "
        f"WHERE attrelid = 'public.{table}'::regclass AND attnum > 0 AND NOT attisdropped ORDER BY attnum",
    )


def count_rows(host: str, port: int, user: str, db: str, table: str) -> int:
    return int(psql_query(host, port, user, db, f"SELECT count(*) FROM public.{table}")[0])


def csv_data_rows(path: str) -> int:
    csv.field_size_limit(sys.maxsize)
    with open(path, newline="", encoding="utf-8", errors="replace") as fh:
        return sum(1 for _ in csv.reader(fh)) - 1


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
    keep_source: bool = False,
) -> None:
    logger.info("Cleaning up partial backup files due to failure...")
    if keep_source and finance_db_file:
        logger.warning(f"Keeping verified source dump {finance_db_file}; it was NOT copied to raspi")
        finance_db_file = None
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
    order_by: str,
    csv_file: str,
    logger: logging.Logger,
    finance_db_file: str | None,
    finance_fresh_db_file: str | None,
    truncate_first: bool = False,
) -> bool:
    def fail() -> bool:
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger, keep_source=True)
        return False

    try:
        src_cols = table_columns(server, port, USERNAME, "finance_db", table)
        fresh_cols = table_columns("localhost", port, USERNAME, "finance_fresh_db", table)
    except RuntimeError as exc:
        logger.error(f"Cannot read columns of {table}: {exc}")
        return fail()

    if set(src_cols) != set(fresh_cols):
        logger.error(
            f"SCHEMA DRIFT in {table}: only in source {sorted(set(src_cols) - set(fresh_cols))}, "
            f"only in finance_fresh_db {sorted(set(fresh_cols) - set(src_cols))} — "
            "regenerate finance_fresh_db-create.sql from the live schema"
        )
        return fail()

    cols = ", ".join('"' + c.replace('"', '""') + '"' for c in src_cols)
    export_sql = rf"\copy (SELECT {cols} FROM {table} ORDER BY {order_by}) TO '{csv_file}' CSV HEADER"
    if not run_psql(server, port, USERNAME, "finance_db", export_sql, f"Export {table}", logger):
        return fail()

    if not check_file(csv_file, logger):
        return fail()

    if truncate_first:
        if not run_psql(
            "localhost", port, USERNAME, "finance_fresh_db",
            f"TRUNCATE TABLE {table} CASCADE; commit",
            f"Truncate {table}",
            logger,
        ):
            return fail()

    # User triggers (e.g. on t_transaction_categories) rewrite owner and timestamps on
    # insert; disable them so the rows are restored exactly as exported.
    import_sql = (
        f"ALTER TABLE {table} DISABLE TRIGGER USER;\n"
        rf"\copy {table} ({cols}) FROM '{csv_file}' CSV HEADER" "\n"
        f"ALTER TABLE {table} ENABLE TRIGGER USER;\n"
        "commit"
    )
    if not run_psql(
        "localhost", port, USERNAME, "finance_fresh_db",
        import_sql, f"Import {table}", logger
    ):
        return fail()

    expected = csv_data_rows(csv_file)
    try:
        actual = count_rows("localhost", port, USERNAME, "finance_fresh_db", table)
    except RuntimeError as exc:
        logger.error(f"Cannot count rows of {table} in finance_fresh_db: {exc}")
        return fail()
    if actual != expected:
        logger.error(f"ROW COUNT MISMATCH in {table}: exported {expected}, finance_fresh_db has {actual}")
        return fail()
    logger.info(f"Verified {table}: {actual} rows")
    return True


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Finance database backup script",
        epilog="Example: %(prog)s 192.168.10.25 5432 v18.4",
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
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger, keep_source=True)
        return 5

    schema_file = Path("finance_fresh_db-create.sql")
    if not run_psql_file(
        "localhost", port, USERNAME, "postgres",
        schema_file,
        "Create finance_fresh_db from schema",
        logger, allow_warnings=True,
    ):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger, keep_source=True)
        return 5

    if not run_psql(
        "localhost", port, USERNAME, "finance_fresh_db",
        "SELECT 1;",
        "Verify finance_fresh_db creation",
        logger, allow_warnings=True,
    ):
        logger.error("finance_fresh_db was not created successfully")
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger, keep_source=True)
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

    # Restore the constraint exactly as the schema file defined it, not from a copy in this script.
    try:
        fk_rows = psql_query(
            "localhost", port, USERNAME, "finance_fresh_db",
            "SELECT pg_get_constraintdef(oid) FROM pg_constraint "
            "WHERE conname = 'fk_receipt_image' AND conrelid = 'public.t_transaction'::regclass",
        )
    except RuntimeError as exc:
        logger.error(f"Cannot read fk_receipt_image definition: {exc}")
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger, keep_source=True)
        return 6
    if len(fk_rows) != 1:
        logger.error("fk_receipt_image not found in finance_fresh_db — schema file is out of date")
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger, keep_source=True)
        return 6
    fk_definition = fk_rows[0]

    if not run_psql(
        "localhost", port, USERNAME, "finance_fresh_db",
        "ALTER TABLE t_transaction DROP CONSTRAINT IF EXISTS fk_receipt_image; commit",
        "Drop fk_receipt_image constraint",
        logger,
    ):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger, keep_source=True)
        return 6

    try:
        source_tables = set(psql_query(
            server, port, USERNAME, "finance_db",
            "SELECT tablename FROM pg_tables WHERE schemaname = 'public'",
        ))
    except RuntimeError as exc:
        logger.error(f"Cannot list source tables: {exc}")
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger, keep_source=True)
        return 6
    handled = {t for t, _ in STANDARD_TABLES} | {t for t, _, _ in OPTIONAL_TABLES} | EXCLUDED_TABLES
    unhandled = sorted(source_tables - handled)
    if unhandled:
        logger.warning(f"Source tables neither exported nor excluded (add to run-backup.py): {', '.join(unhandled)}")

    for table, order_by in STANDARD_TABLES:
        if not export_import_table(
            server, port, table, order_by,
            f"{table}.csv", logger, finance_db_file, finance_fresh_db_file,
        ):
            return 6

    for table, order_by, truncate_first in OPTIONAL_TABLES:
        logger.info(f"Checking if {table} exists in source database...")
        if table_exists(server, port, USERNAME, "finance_db", table):
            logger.info(f"{table} found — exporting...")
            if not export_import_table(
                server, port, table, order_by,
                f"{table}.csv", logger, finance_db_file, finance_fresh_db_file,
                truncate_first=truncate_first,
            ):
                return 6
        else:
            logger.info(f"{table} not found in source — writing empty CSV placeholder")
            Path(f"{table}.csv").write_text(
                ",".join(table_columns("localhost", port, USERNAME, "finance_fresh_db", table)) + "\n"
            )

    # --- Restore FK constraint ---
    if not run_psql(
        "localhost", port, USERNAME, "finance_fresh_db",
        f"ALTER TABLE t_transaction ADD CONSTRAINT fk_receipt_image {fk_definition}; commit",
        "Restore fk_receipt_image constraint",
        logger,
    ):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger, keep_source=True)
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
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger, keep_source=True)
        return 7

    if not check_file(finance_fresh_db_file, logger):
        cleanup_on_failure(finance_db_file, finance_fresh_db_file, logger, keep_source=True)
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
