#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

FIELD_WIDTH = 32
DEFAULT_DB_PATH = "~/.local/share/smartmon/smartmon.db"
DEFAULT_LOG_FILE = "~/.local/state/smartmon/smartmon.log"

SMARTCTL_ERROR_MSGS = [
    "Bit 0: Command line did not parse.",
    "Bit 1: Device open failed, device did not return an IDENTIFY DEVICE structure, or device is in a low-power mode.",
    "Bit 2: Some SMART or other ATA command to the disk failed, or there was a checksum error in a SMART data structure.",
    "Bit 3: SMART status check returned 'DISK FAILING'.",
    "Bit 4: We found prefail Attributes <= threshold.",
    "Bit 5: SMART status check returned 'DISK OK' but we found that some (usage or prefail) Attributes have been <= threshold at some time in the past.",
    "Bit 6: The device error log contains records of errors.",
    "Bit 7: The device self-test log contains records of errors. [ATA only] Failed self-tests outdated by a newer successful extended self-test are ignored.",
]

DB_SCHEMA = """
CREATE TABLE IF NOT EXISTS smart_info (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    disk_name TEXT NOT NULL,
    disk_path TEXT NOT NULL,
    model_family TEXT,
    model_name TEXT,
    user_capacity_bytes INTEGER,
    user_capacity_gib REAL,
    rotation_rate TEXT,
    interface_speed TEXT,
    power_on_time_hours TEXT,
    power_cycle_count TEXT,
    temperature_celsius TEXT,
    reallocated_sector_ct TEXT,
    ata_smart_error_log_count TEXT,
    self_test_status TEXT,
    raw_json TEXT
);
CREATE INDEX IF NOT EXISTS idx_smart_info_disk_ts
    ON smart_info(disk_path, timestamp);
"""

RED = "\033[31m"
RESET = "\033[0m"


def _stdout_tty() -> bool:
    return sys.stdout.isatty()


def setup_logging(log_file: str | None = None) -> None:
    root = logging.getLogger()
    if root.handlers:
        return
    root.setLevel(logging.DEBUG)

    debug = os.environ.get("DEBUG", "").lower() in ("1", "true", "yes")
    stderr_level = logging.DEBUG if debug else logging.WARNING
    stderr_handler = logging.StreamHandler(sys.stderr)
    stderr_handler.setLevel(stderr_level)
    stderr_handler.setFormatter(logging.Formatter("%(message)s"))
    root.addHandler(stderr_handler)

    if log_file:
        _add_file_handler(root, log_file)


def _add_file_handler(root: logging.Logger, log_file: str) -> None:
    try:
        log_path = Path(os.path.expanduser(log_file))
        log_path.parent.mkdir(parents=True, exist_ok=True)
        fh = logging.FileHandler(str(log_path))
        fh.setLevel(logging.DEBUG)
        fh.setFormatter(
            logging.Formatter(
                "[%(asctime)s][%(levelname)s] %(message)s",
                datefmt="%Y-%m-%dT%H:%M:%SZ",
            )
        )
        root.addHandler(fh)
    except OSError as exc:
        logging.warning("Cannot create log file %s: %s", log_file, exc)


def safe_get(data: dict[str, Any], *keys: str, default: Any = "N/A") -> Any:
    for key in keys:
        if isinstance(data, dict):
            data = data.get(key)
        else:
            return default
    if data is None or data == "" or data == "null":
        return default
    return data


def find_in_table(
    data: dict[str, Any],
    table_keys: tuple[str, ...],
    where_key: str,
    where_value: str,
    extract_keys: tuple[str, ...],
    default: str = "0",
) -> str:
    table = data
    for key in table_keys:
        if isinstance(table, dict):
            table = table.get(key, [])
        else:
            return default
    if not isinstance(table, list):
        return default
    for entry in table:
        if not isinstance(entry, dict):
            continue
        if entry.get(where_key) != where_value:
            continue
        value = entry
        for key in extract_keys:
            if isinstance(value, dict):
                value = value.get(key, default)
            else:
                return default
        if value is None or value == "":
            return default
        return str(value)
    return default


def check_smartctl_error(returncode: int | None) -> None:
    if returncode is None or returncode == 0:
        return
    logging.error("smartctl returned error code: %d", returncode)
    for i in range(8):
        if (returncode >> i) & 1:
            logging.error("  %s", SMARTCTL_ERROR_MSGS[i])


def find_disks(pattern: str) -> list[Path]:
    logging.info("Searching for disk devices matching pattern: %s", pattern)
    by_id = Path("/dev/disk/by-id")
    if not by_id.is_dir():
        logging.error("Directory not found: %s", by_id)
        sys.exit(1)

    try:
        compiled = re.compile(pattern)
    except re.error as exc:
        logging.error("Invalid regex pattern: %s", exc)
        sys.exit(1)
    disks = []
    for entry in sorted(by_id.iterdir()):
        if not entry.is_symlink():
            continue
        name = entry.name
        if not name.startswith("ata-"):
            continue
        if re.search(r"-part\d+$", name):
            continue
        if not compiled.search(name):
            continue
        disks.append(entry)

    if not disks:
        logging.error("No disk devices found matching pattern: %s", pattern)
        sys.exit(1)

    logging.info("Found %d disk(s):", len(disks))
    for d in disks:
        logging.debug("  %s", d)

    return disks


def run_smartctl(disk_path: Path) -> tuple[dict[str, Any], int]:
    try:
        result = subprocess.run(
            ["smartctl", "--all", "--json", str(disk_path)],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except FileNotFoundError:
        logging.error("smartctl not found. Please install smartmontools.")
        sys.exit(1)
    except subprocess.TimeoutExpired:
        logging.error("smartctl timed out for %s", disk_path)
        return {}, -1

    check_smartctl_error(result.returncode)

    try:
        data = json.loads(result.stdout) if result.stdout.strip() else {}
    except json.JSONDecodeError:
        logging.error("Failed to parse smartctl JSON output for %s", disk_path)
        data = {}

    return data, result.returncode


def extract_fields(data: dict[str, Any]) -> dict[str, Any]:
    model_family = str(safe_get(data, "model_family"))
    model_name = str(safe_get(data, "model_name"))

    uc_bytes = safe_get(data, "user_capacity", "bytes", default=0)
    try:
        uc_bytes = int(uc_bytes)
    except (ValueError, TypeError):
        uc_bytes = 0
    uc_gib = round(uc_bytes / (2**30), 2) if uc_bytes > 0 else None

    rotation_rate = str(safe_get(data, "rotation_rate"))
    rr_display = (
        f"{rotation_rate} rpm"
        if rotation_rate not in ("N/A", "0")
        else "SSD (no rotation)"
    )

    interface_speed = str(safe_get(data, "interface_speed", "current", "string"))

    power_on_time = str(safe_get(data, "power_on_time", "hours"))
    power_cycle_count = str(safe_get(data, "power_cycle_count"))
    temperature = str(safe_get(data, "temperature", "current"))

    realloc = find_in_table(
        data,
        ("ata_smart_attributes", "table"),
        "name",
        "Reallocated_Sector_Ct",
        ("raw", "string"),
    )

    error_log = str(
        safe_get(data, "ata_smart_error_log", "summary", "count", default="0")
    )
    self_test = str(safe_get(data, "ata_smart_data", "self_test", "status", "string"))

    return {
        "model_family": model_family,
        "model_name": model_name,
        "user_capacity_bytes": uc_bytes,
        "user_capacity_gib": uc_gib,
        "rotation_rate": rotation_rate,
        "rotation_rate_display": rr_display,
        "interface_speed": interface_speed,
        "power_on_time": power_on_time,
        "power_cycle_count": power_cycle_count,
        "temperature": temperature,
        "reallocated_sector_ct": realloc,
        "ata_smart_error_log": error_log,
        "self_test_status": self_test,
    }


def _print_field(name: str, value: str, color: bool = False) -> None:
    if color:
        print(f"{RED}{name:<{FIELD_WIDTH}} {value}{RESET if _stdout_tty() else ''}")
    else:
        print(f"{name:<{FIELD_WIDTH}} {value}")


def _print_fields(fields: dict[str, Any]) -> None:
    _print_field("model_family", fields["model_family"])
    _print_field("model_name", fields["model_name"])

    uc_gib = fields["user_capacity_gib"]
    _print_field("user_capacity", f"{uc_gib} GiB" if uc_gib is not None else "N/A")
    _print_field("rotation_rate", fields["rotation_rate_display"])
    _print_field("interface_speed", fields["interface_speed"])
    _print_field("power_on_time", f"{fields['power_on_time']} hours")
    _print_field("power_cycle_count", fields["power_cycle_count"])
    _print_field("temperature", f"{fields['temperature']}°C")

    realloc = fields["reallocated_sector_ct"]
    realloc_int = None
    try:
        realloc_int = int(realloc)
    except (ValueError, TypeError):
        pass
    if realloc_int is not None and realloc_int > 0:
        _print_field("reallocated_sector_ct", realloc, color=True)
    else:
        _print_field("reallocated_sector_ct", realloc)

    _print_field("ata_smart_error_log", fields["ata_smart_error_log"])
    _print_field("self_test_status", fields["self_test_status"])


def print_table(disk_name: str, fields: dict[str, Any]) -> None:
    print(f"====== {disk_name} ======")
    _print_fields(fields)
    print()


def row_to_fields(row: sqlite3.Row) -> dict[str, Any]:
    rr = row["rotation_rate"]
    rr_display = f"{rr} rpm" if rr not in ("N/A", "0") else "SSD (no rotation)"

    return {
        "model_family": row["model_family"],
        "model_name": row["model_name"],
        "user_capacity_bytes": row["user_capacity_bytes"],
        "user_capacity_gib": row["user_capacity_gib"],
        "rotation_rate": rr,
        "rotation_rate_display": rr_display,
        "interface_speed": row["interface_speed"],
        "power_on_time": row["power_on_time_hours"],
        "power_cycle_count": row["power_cycle_count"],
        "temperature": row["temperature_celsius"],
        "reallocated_sector_ct": row["reallocated_sector_ct"],
        "ata_smart_error_log": row["ata_smart_error_log_count"],
        "self_test_status": row["self_test_status"],
    }


def print_query_table(row: sqlite3.Row) -> None:
    header = f"--- {row['timestamp']} | {row['disk_name']} ({row['disk_path']}) ---"
    print(header)
    fields = row_to_fields(row)
    _print_fields(fields)
    print()


def print_json_output(
    disk_name: str,
    disk_path: str,
    fields: dict[str, Any],
    raw_data: dict[str, Any] | None,
    timestamp: str | None = None,
) -> None:
    record = {"disk_name": disk_name, "disk_path": disk_path, **fields}
    if timestamp:
        record["timestamp"] = timestamp
    json.dump(record, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    sys.stdout.flush()


def init_db(db_path: str) -> sqlite3.Connection:
    expanded = Path(os.path.expanduser(db_path))
    expanded.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(expanded))
    conn.execute("PRAGMA journal_mode=WAL")
    conn.executescript(DB_SCHEMA)
    return conn


def open_db(db_path: str) -> sqlite3.Connection | None:
    expanded = Path(os.path.expanduser(db_path))
    if not expanded.is_file():
        logging.warning("Database not found: %s", expanded)
        return None
    conn = sqlite3.connect(f"file:{expanded}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def register_regexp(conn: sqlite3.Connection) -> None:
    def _regexp(pattern: str, value: str | None) -> bool:
        if value is None:
            return False
        return bool(re.search(pattern, value))

    conn.create_function("REGEXP", 2, _regexp)


def parse_date(date_str: str) -> datetime:
    try:
        return datetime.strptime(date_str, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    except ValueError:
        logging.error("Invalid date format: %s (expected YYYY-MM-DD)", date_str)
        sys.exit(1)


def query_smart_info(
    conn: sqlite3.Connection,
    pattern: str | None,
    since: datetime | None,
    until: datetime | None,
) -> list[sqlite3.Row]:
    register_regexp(conn)

    conditions = []
    params = []

    if pattern:
        conditions.append("disk_name REGEXP ?")
        params.append(pattern)

    if since:
        conditions.append("timestamp >= ?")
        params.append(since.strftime("%Y-%m-%dT00:00:00Z"))

    if until:
        conditions.append("timestamp <= ?")
        params.append(until.strftime("%Y-%m-%dT23:59:59Z"))

    where = " AND ".join(conditions) if conditions else "1=1"
    sql = f"SELECT * FROM smart_info WHERE {where} ORDER BY disk_path, timestamp"

    logging.debug("Query: %s  params: %s", sql, params)
    return conn.execute(sql, params).fetchall()


def do_collect(args: argparse.Namespace) -> None:
    if os.geteuid() != 0:
        logging.warning(
            "This script typically requires root privileges to access SMART data."
        )

    conn = None
    if not args.no_save:
        try:
            conn = init_db(args.db_path)
        except OSError as exc:
            logging.error("Failed to open database at %s: %s", args.db_path, exc)

    disks = find_disks(args.pattern)

    exit_code = 0
    for symlink in disks:
        disk_name = symlink.name
        disk_path = os.readlink(symlink)

        data, rc = run_smartctl(symlink)
        if rc != 0:
            exit_code = 1

        if not data:
            continue

        fields = extract_fields(data)

        if args.json:
            print_json_output(disk_name, disk_path, fields, data)
        else:
            print_table(disk_name, fields)

        if conn:
            try:
                save_to_db(conn, disk_name, disk_path, fields, data)
            except sqlite3.Error as exc:
                logging.error("Failed to save SMART data for %s: %s", disk_name, exc)

    if conn:
        conn.close()

    sys.exit(exit_code)


def do_query(args: argparse.Namespace) -> None:
    since = parse_date(args.since) if args.since else None
    until = parse_date(args.until) if args.until else None

    conn = open_db(args.db_path)
    if conn is None:
        sys.exit(0)

    try:
        rows = query_smart_info(conn, args.pattern, since, until)
    except sqlite3.OperationalError as exc:
        logging.error("Query failed: %s", exc)
        conn.close()
        sys.exit(1)

    if not rows:
        logging.info("No SMART records found matching the query.")
        conn.close()
        sys.exit(0)

    for row in rows:
        if args.json:
            fields = row_to_fields(row)
            print_json_output(
                row["disk_name"],
                row["disk_path"],
                fields,
                None,
                timestamp=row["timestamp"],
            )
        else:
            print_query_table(row)

    conn.close()


def save_to_db(
    conn: sqlite3.Connection,
    disk_name: str,
    disk_path: str,
    fields: dict[str, Any],
    raw_data: dict[str, Any],
) -> None:
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    conn.execute(
        """INSERT INTO smart_info
           (timestamp, disk_name, disk_path, model_family, model_name,
            user_capacity_bytes, user_capacity_gib, rotation_rate,
            interface_speed, power_on_time_hours, power_cycle_count,
            temperature_celsius, reallocated_sector_ct,
            ata_smart_error_log_count, self_test_status, raw_json)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            timestamp,
            disk_name,
            disk_path,
            fields["model_family"],
            fields["model_name"],
            fields["user_capacity_bytes"],
            fields["user_capacity_gib"],
            fields["rotation_rate"],
            fields["interface_speed"],
            fields["power_on_time"],
            fields["power_cycle_count"],
            fields["temperature"],
            fields["reallocated_sector_ct"],
            fields["ata_smart_error_log"],
            fields["self_test_status"],
            json.dumps(raw_data, ensure_ascii=False),
        ),
    )
    conn.commit()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract and display important SMART information from disk devices.",
        add_help=False,
    )
    parser.add_argument(
        "pattern",
        nargs="?",
        default=".*",
        help="Regex pattern to filter disk devices (collect) or disk_name (query)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output as JSON lines instead of table format",
    )
    parser.add_argument(
        "-h",
        "--help",
        action="help",
        help="Show this help message and exit",
    )

    collect_group = parser.add_argument_group("collect mode (default)")
    collect_group.add_argument(
        "--no-save",
        action="store_true",
        help="Skip saving SMART data to database",
    )

    query_group = parser.add_argument_group("query mode")
    query_group.add_argument(
        "--query",
        action="store_true",
        help="Query historical SMART data from database instead of collecting",
    )
    query_group.add_argument(
        "--since",
        metavar="DATE",
        help="Start date (YYYY-MM-DD) for query",
    )
    query_group.add_argument(
        "--until",
        metavar="DATE",
        help="End date (YYYY-MM-DD) for query",
    )

    db_group = parser.add_argument_group("database")
    db_group.add_argument(
        "--db-path",
        default=DEFAULT_DB_PATH,
        help=f"Database file path (default: {DEFAULT_DB_PATH})",
    )

    log_group = parser.add_argument_group("logging")
    log_group.add_argument(
        "--log-file",
        default=DEFAULT_LOG_FILE,
        help=f"Log file path (default: {DEFAULT_LOG_FILE})",
    )
    log_group.add_argument(
        "--no-log-file",
        action="store_true",
        help="Disable file logging",
    )

    args = parser.parse_args()

    log_file = None if args.no_log_file else args.log_file
    setup_logging(log_file)

    if args.query:
        do_query(args)
    else:
        do_collect(args)


if __name__ == "__main__":
    main()
