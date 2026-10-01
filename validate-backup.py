#!/usr/bin/env python3
"""Validate a pg_dump tar backup without restoring it.

Reads the archive with pg_restore only, so it needs no database, no password and
no temporary database. Checks:

  1. integrity   - the whole archive can be read back without error
  2. schema      - the schema inside the archive matches the repo's schema file
  3. row counts  - every table has a data section; empty tables are flagged
  4. regression  - row counts are compared with the previous backup
  5. live        - optionally compare row counts with the running database

Exit status: 0 = passed (warnings allowed), 1 = validation failed, 2 = usage or
environment problem.
"""

import argparse
import logging
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import threading
from collections import Counter
from datetime import date, datetime, timedelta
from pathlib import Path

DEFAULT_USER = "henninb"
DEFAULT_PORT = 5432
DEFAULT_MAX_DROP = 0.10
DEFAULT_MIN_ROWS = 100
DEFAULT_TIMEOUT = 600  # seconds per pg_restore call; it can spin forever on damaged archives

TIMEOUT = DEFAULT_TIMEOUT

NAME_RE = re.compile(
    r"^(?P<db>[a-z_]+_db)-(?P<version>v[0-9][0-9.\-]*)-(?P<date>\d{4}-\d{2}-\d{2})(?:-(?P<seq>\d+))?\.tar$"
)
TOC_DATA_RE = re.compile(r"^\d+; \d+ \d+ TABLE DATA (?P<schema>\S+) (?P<table>\S+) ")
COPY_RE = re.compile(rb"^COPY (?P<name>\S+) ")
TIMESTAMP_RE = re.compile(r"'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?)([+-]\d{2})(?::?(\d{2}))?'")
DOLLAR_TAG_RE = re.compile(r"\$[A-Za-z_]*\$")

# Statements that describe where/how a schema is installed, not what it is.
IGNORED_STATEMENT_RE = re.compile(
    r"^(SET |RESET |SELECT PG_CATALOG\.SET_CONFIG|BEGIN\b|COMMIT\b|START TRANSACTION|"
    r"DROP DATABASE|CREATE DATABASE|GRANT |REVOKE |INSERT INTO |ALTER DEFAULT PRIVILEGES)"
)
OWNER_RE = re.compile(r"^ALTER .* OWNER TO ")


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
def setup_logging() -> logging.Logger:
    logger = logging.getLogger("validate")
    logger.setLevel(logging.INFO)
    fmt = logging.Formatter("[%(asctime)s] %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
    log_file = f"backup-validation-{date.today():%Y-%m-%d}.log"
    for handler in (logging.FileHandler(log_file), logging.StreamHandler(sys.stdout)):
        handler.setFormatter(fmt)
        logger.addHandler(handler)
    return logger


class Report:
    def __init__(self, logger: logging.Logger) -> None:
        self.logger = logger
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def ok(self, msg: str) -> None:
        self.logger.info(f"PASS  {msg}")

    def info(self, msg: str) -> None:
        self.logger.info(f"      {msg}")

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)
        self.logger.info(f"WARN  {msg}")

    def error(self, msg: str) -> None:
        self.errors.append(msg)
        self.logger.info(f"FAIL  {msg}")


# ---------------------------------------------------------------------------
# Reading the archive
# ---------------------------------------------------------------------------
def check_tar(path: Path) -> int:
    """Read every member of the tar; a truncated or damaged file raises. Returns the member count."""
    members = 0
    try:
        with tarfile.open(path, "r:") as tf:
            for member in tf:
                fh = tf.extractfile(member)
                if fh is not None:
                    while fh.read(1 << 20):
                        pass
                members += 1
    except (tarfile.TarError, EOFError, OSError) as exc:
        raise RuntimeError(f"not a complete tar archive: {exc}") from exc
    if members == 0:
        raise RuntimeError("tar archive contains no files")
    return members


def run_pg_restore(args: list[str]) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(["pg_restore", *args], capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"pg_restore did not finish within {TIMEOUT}s (damaged archive?)") from exc


def read_toc(path: Path) -> tuple[list[tuple[str, str]], dict[str, str]]:
    """Return ([(schema, table)] with a data section, header facts)."""
    result = run_pg_restore(["-l", str(path)])
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "pg_restore -l failed")
    tables: list[tuple[str, str]] = []
    header: dict[str, str] = {}
    for line in result.stdout.splitlines():
        if line.startswith(";"):
            key, _, value = line[1:].partition(":")
            if value:
                header[key.strip()] = value.strip()
            continue
        m = TOC_DATA_RE.match(line)
        if m:
            tables.append((m["schema"], m["table"]))
    return tables, header


def count_rows(path: Path) -> dict[str, int]:
    """Stream the data sections and count rows per table (schema-qualified)."""
    counts: dict[str, int] = {}
    with tempfile.TemporaryFile() as err:
        proc = subprocess.Popen(["pg_restore", "-a", "-f", "-", str(path)], stdout=subprocess.PIPE, stderr=err)
        timed_out = threading.Event()

        def kill() -> None:
            timed_out.set()
            proc.kill()

        watchdog = threading.Timer(TIMEOUT, kill)
        watchdog.start()
        current: str | None = None
        assert proc.stdout is not None
        for line in proc.stdout:
            if current is None:
                m = COPY_RE.match(line)
                if m:
                    current = m["name"].decode().replace('"', "")
                    counts[current] = 0
            elif line.rstrip(b"\r\n") == b"\\.":
                current = None
            else:
                counts[current] += 1
        code = proc.wait()
        watchdog.cancel()
        if timed_out.is_set():
            raise RuntimeError(f"pg_restore did not finish within {TIMEOUT}s (damaged archive?)")
        err.seek(0)
        stderr = err.read().decode(errors="replace").strip()
    if code != 0:
        raise RuntimeError(stderr or f"pg_restore exited {code}")
    if current is not None:
        raise RuntimeError(f"data section for {current} is not terminated (archive truncated?)")
    return counts


def read_schema(path: Path) -> str:
    result = run_pg_restore(["-s", "-f", "-", str(path)])
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "pg_restore -s failed")
    return result.stdout


# ---------------------------------------------------------------------------
# Schema normalisation
# ---------------------------------------------------------------------------
def split_statements(sql: str) -> list[str]:
    """Split SQL on top-level semicolons, honouring comments, quotes and $$ bodies."""
    out: list[str] = []
    buf: list[str] = []
    i, n = 0, len(sql)

    def flush() -> None:
        text = "".join(buf).strip()
        if text:
            out.append(text)
        buf.clear()

    while i < n:
        c = sql[i]
        if c == "\\" and not "".join(buf).strip():  # psql meta-command (\connect, \restrict ...)
            j = sql.find("\n", i)
            i = n if j == -1 else j
        elif c == "-" and sql.startswith("--", i):
            j = sql.find("\n", i)
            i = n if j == -1 else j
        elif c == "/" and sql.startswith("/*", i):
            j = sql.find("*/", i + 2)
            i = n if j == -1 else j + 2
        elif c in ("'", '"'):
            j = i + 1
            while j < n:
                if sql[j] == c:
                    if j + 1 < n and sql[j + 1] == c:
                        j += 2
                        continue
                    break
                j += 1
            buf.append(sql[i : j + 1])
            i = j + 1
        elif c == "$" and (m := DOLLAR_TAG_RE.match(sql, i)):
            tag = m.group(0)
            j = sql.find(tag, m.end())
            j = n if j == -1 else j + len(tag)
            buf.append(sql[i:j])
            i = j
        elif c == ";":
            flush()
            i += 1
        else:
            buf.append(c)
            i += 1
    flush()
    return out


def _to_utc(m: re.Match) -> str:
    base = datetime.fromisoformat(m.group(1))
    hours = int(m.group(2))
    minutes = int(m.group(3) or 0)
    delta = timedelta(hours=abs(hours), minutes=minutes) * (-1 if m.group(2).startswith("-") else 1)
    return "'" + (base - delta).strftime("%Y-%m-%d %H:%M:%S") + "+00'"


def normalise_schema(sql: str) -> Counter:
    result: Counter = Counter()
    for stmt in split_statements(sql):
        text = " ".join(stmt.split())
        if IGNORED_STATEMENT_RE.match(text.upper()) or OWNER_RE.match(text):
            continue
        # Timestamp defaults are rendered in the dumping session's time zone; compare instants.
        result[TIMESTAMP_RE.sub(_to_utc, text)] += 1
    return result


# ---------------------------------------------------------------------------
# Locating related files
# ---------------------------------------------------------------------------
def schema_file_for(db: str, search_dirs: list[Path]) -> Path | None:
    stem = db[: -len("_db")]
    name = f"{db}-create.sql" if stem.endswith("_fresh") else f"{stem}_fresh_db-create.sql"
    for d in search_dirs:
        if (d / name).is_file():
            return d / name
    return None


def sort_key(path: Path) -> tuple[str, int, float]:
    m = NAME_RE.match(path.name)
    assert m
    return (m["date"], int(m["seq"] or 0), path.stat().st_mtime)


def find_previous(path: Path) -> Path | None:
    m = NAME_RE.match(path.name)
    if not m:
        return None
    mine = sort_key(path)
    older = [
        p for p in path.parent.glob(f"{m['db']}-*.tar")
        if p != path and (pm := NAME_RE.match(p.name)) and pm["db"] == m["db"] and sort_key(p) < mine
    ]
    return max(older, key=sort_key) if older else None


# ---------------------------------------------------------------------------
# Live database
# ---------------------------------------------------------------------------
def live_counts(server: str, port: int, user: str, db: str, tables: list[str]) -> dict[str, int]:
    env = dict(os.environ)
    pgpass = Path.home() / ".pgpass"
    if pgpass.exists():
        env["PGPASSFILE"] = str(pgpass)
    sql = " UNION ALL ".join(
        f"SELECT '{t}', count(*) FROM public.\"{t}\"" for t in sorted(tables)
    )
    result = subprocess.run(
        ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-h", server, "-p", str(port), "-U", user, "-d", db,
         "-tA", "-F", "|", "-c", sql],
        capture_output=True, text=True, env=env,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return {name: int(n) for name, n in (line.split("|") for line in result.stdout.splitlines() if line)}


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
def check_schema(report: Report, archive_sql: str, schema_path: Path) -> None:
    in_backup = normalise_schema(archive_sql)
    in_file = normalise_schema(schema_path.read_text())
    only_backup = in_backup - in_file
    only_file = in_file - in_backup
    if not only_backup and not only_file:
        report.ok(f"schema matches {schema_path.name} ({sum(in_backup.values())} statements)")
        return
    report.error(
        f"schema differs from {schema_path.name}: {sum(only_backup.values())} statement(s) only in the backup, "
        f"{sum(only_file.values())} only in the file"
    )
    for label, diff in (("only in backup", only_backup), ("only in schema file", only_file)):
        for stmt in list(diff)[:10]:
            report.info(f"{label}: {stmt[:200]}{'...' if len(stmt) > 200 else ''}")
        if len(diff) > 10:
            report.info(f"{label}: ... and {len(diff) - 10} more")


def check_rows(
    report: Report,
    counts: dict[str, int],
    previous: dict[str, int] | None,
    max_drop: float,
    min_rows: int,
) -> None:
    width = max(len(t) for t in counts) if counts else 10
    report.info(f"{'table':<{width}} {'rows':>9} {'previous':>9}  status")
    for table in sorted(counts):
        rows = counts[table]
        prev = previous.get(table) if previous is not None else None
        status = "ok"
        if previous is None:
            if rows == 0:
                status = "EMPTY (no previous backup to compare)"
                report.warn(f"{table} is empty and there is no previous backup to say whether that is expected")
        elif prev is None:
            status = "new table"
        elif prev > 0 and rows == 0:
            status = "EMPTIED"
            report.error(f"{table} has 0 rows; the previous backup had {prev}")
        elif prev >= min_rows and rows < prev * (1 - max_drop):
            status = f"DROPPED {100 * (prev - rows) / prev:.0f}%"
            report.error(f"{table} dropped from {prev} to {rows} rows (limit {max_drop:.0%})")
        elif rows < prev:
            status = "smaller"
        shown = "-" if prev is None else str(prev)
        report.info(f"{table:<{width}} {rows:>9} {shown:>9}  {status}")
    if previous is not None:
        for table in sorted(set(previous) - set(counts)):
            report.error(f"{table} is in the previous backup but missing from this one")
    total = sum(counts.values())
    if total == 0:
        report.error("backup contains no rows at all")
    else:
        report.ok(f"{len(counts)} tables, {total:,} rows")


def check_live(
    report: Report, counts: dict[str, int], live: dict[str, int], max_drop: float
) -> None:
    differences = 0
    for table in sorted(set(counts) | set(live)):
        b, l = counts.get(table), live.get(table)
        if b is None:
            report.error(f"{table} exists in the live database but not in the backup")
        elif l is None:
            report.warn(f"{table} is in the backup but no longer in the live database")
        elif b == l:
            continue
        elif l > 0 and b < l * (1 - max_drop):
            report.error(f"{table}: backup has {b} rows, live has {l} (backup is more than {max_drop:.0%} behind)")
        else:
            report.warn(f"{table}: backup has {b} rows, live has {l} (changed since the backup was taken)")
        differences += 1
    if not differences:
        report.ok("row counts match the live database")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Validate a pg_dump tar backup without restoring it.")
    p.add_argument("backup", type=Path, help="backup .tar file, e.g. calendar_db-v18.4-2026-09-20.tar")
    p.add_argument("--previous", help="previous backup to compare against, or 'none' (default: newest older backup alongside)")
    p.add_argument("--schema", type=Path, help="schema file to compare against (default: found from the backup name)")
    p.add_argument("--live", metavar="SERVER", help="also compare row counts with this running server")
    p.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"port for --live (default {DEFAULT_PORT})")
    p.add_argument("--user", default=DEFAULT_USER, help=f"user for --live (default {DEFAULT_USER})")
    p.add_argument("--max-drop", type=float, default=DEFAULT_MAX_DROP,
                   help=f"largest allowed row-count drop as a fraction (default {DEFAULT_MAX_DROP})")
    p.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT,
                   help=f"seconds allowed for each pg_restore call (default {DEFAULT_TIMEOUT})")
    p.add_argument("--min-rows", type=int, default=DEFAULT_MIN_ROWS,
                   help=f"tables smaller than this are only checked for emptying (default {DEFAULT_MIN_ROWS})")
    return p.parse_args()


def main() -> int:
    global TIMEOUT
    args = parse_args()
    TIMEOUT = args.timeout
    logger = setup_logging()
    report = Report(logger)

    missing = [c for c in ("pg_restore", *(["psql"] if args.live else [])) if not shutil.which(c)]
    if missing:
        logger.info(f"Missing required tools: {', '.join(missing)}")
        return 2

    path: Path = args.backup
    logger.info(f"Validating {path}")
    if not path.is_file() or path.stat().st_size == 0:
        report.error(f"{path} is missing or empty")
        return 1
    report.ok(f"file exists ({path.stat().st_size / 1024:.1f} KB)")

    m = NAME_RE.match(path.name)
    if not m:
        report.warn("file name does not follow <db>-v<version>-<date>[-<seq>].tar; schema and previous lookups skipped")

    # 1. integrity + 3. row counts (one pass over the data)
    try:
        members = check_tar(path)
        report.ok(f"tar structure intact ({members} members)")
        tables, header = read_toc(path)
        counts = count_rows(path)
    except RuntimeError as exc:
        report.error(f"archive cannot be read: {exc}")
        return finish(report)
    report.ok(f"archive readable end to end (dumped from PostgreSQL {header.get('Dumped from database version', '?')})")
    toc_names = {f"{s}.{t}" for s, t in tables}
    for name in sorted(toc_names - set(counts)):
        counts[name] = 0  # listed in the archive with an empty data section
    counts = {name.split(".", 1)[-1]: n for name, n in counts.items()}
    if not counts:
        report.error("archive contains no table data")
        return finish(report)

    # 2. schema
    if args.schema:
        schema_path: Path | None = args.schema
    elif m:
        schema_path = schema_file_for(m["db"], [path.resolve().parent, Path(__file__).resolve().parent, Path.cwd()])
    else:
        schema_path = None
    if schema_path is None or not schema_path.is_file():
        report.warn("no schema file found to compare against (use --schema)")
    else:
        try:
            check_schema(report, read_schema(path), schema_path)
        except RuntimeError as exc:
            report.error(f"cannot read schema from archive: {exc}")

    # 4. regression against the previous backup
    previous_counts: dict[str, int] | None = None
    if args.previous and args.previous.lower() == "none":
        prev_path = None
    elif args.previous:
        prev_path = Path(args.previous)
    else:
        prev_path = find_previous(path) if m else None
    if prev_path is not None:
        logger.info(f"Comparing with previous backup {prev_path.name}")
        try:
            prev_toc, _ = read_toc(prev_path)
            previous_counts = count_rows(prev_path)
            for s, t in prev_toc:
                previous_counts.setdefault(f"{s}.{t}", 0)
            previous_counts = {k.split(".", 1)[-1]: v for k, v in previous_counts.items()}
        except RuntimeError as exc:
            report.warn(f"previous backup {prev_path.name} is unreadable, skipping comparison: {exc}")
    else:
        report.info("no previous backup found to compare against")
    check_rows(report, counts, previous_counts, args.max_drop, args.min_rows)

    # 5. live database
    if args.live:
        if not m:
            report.warn("cannot determine database name from the file name; skipping --live")
        else:
            try:
                check_live(report, counts, live_counts(args.live, args.port, args.user, m["db"], list(counts)), args.max_drop)
            except RuntimeError as exc:
                report.error(f"live comparison failed: {exc}")

    return finish(report)


def finish(report: Report) -> int:
    report.logger.info("-" * 60)
    if report.errors:
        report.logger.info(f"FAILED: {len(report.errors)} error(s), {len(report.warnings)} warning(s)")
        return 1
    report.logger.info(f"PASSED: {len(report.warnings)} warning(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
