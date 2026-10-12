#!/usr/bin/env python3
"""Consistent SQLite snapshot for the temporary DevBox's OpenCode session DB.

Only saves this runner's DB to a local staging file included in encrypted Restic.
Never reads or exports auth.json, keys, cookies, or another computer's database.
"""
from contextlib import closing
import os
from pathlib import Path
import sqlite3
import sys
import uuid


def session_count(path: Path):
    """Return only a count, never conversation content; None means unknown schema."""
    with closing(sqlite3.connect(Path(path).resolve().as_uri() + "?mode=ro", uri=True, timeout=15)) as db:
        tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        counts = [db.execute('SELECT COUNT(*) FROM "' + name + '"').fetchone()[0]
                  for name in ('session', 'sessions') if name in tables]
        return sum(counts) if counts else None


def snapshot(source: Path, destination: Path) -> None:
    source = Path(source)
    destination = Path(destination)
    if not source.is_file():
        raise FileNotFoundError("OpenCode DB missing; refusing to create a blank one")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        # Read-only URI prevents silently creating a new DB if source disappears.
        # sqlite3.Connection context managers do NOT close the OS file handle.
        # Windows refuses os.replace() on an open SQLite file.
        with closing(sqlite3.connect(source.as_uri() + "?mode=ro", uri=True, timeout=15)) as source_db:
            with closing(sqlite3.connect(str(temporary), timeout=15)) as target_db:
                source_db.backup(target_db, pages=100, sleep=0.05)
                result = target_db.execute("PRAGMA integrity_check").fetchone()
                if not result or result[0] != "ok":
                    raise RuntimeError("SQLite snapshot integrity check failed")
        # A new/incorrect user profile can contain a valid but empty DB. Do not
        # replace the last populated staged history with that empty database.
        # Count the transaction-consistent temporary copy, not the changing source.
        if destination.is_file():
            previous_count = session_count(destination)
            incoming_count = session_count(temporary)
            if previous_count and not incoming_count:
                raise RuntimeError("Empty or unrecognized history cannot replace populated history")
        os.replace(temporary, destination)
    finally:
        if temporary.exists():
            temporary.unlink()


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == '--inspect':
        try:
            count = session_count(Path(sys.argv[2]))
            print("OPENCODE SESSION ROWS: " + (str(count) if count is not None else "unknown-schema"))
        except Exception as exc:
            sys.exit("OPENCODE INSPECTION FAILED: " + type(exc).__name__)
        sys.exit(0)
    if len(sys.argv) != 3:
        sys.exit("Usage: snapshot-opencode-db.py SOURCE_DB DESTINATION_DB")
    try:
        snapshot(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
    except Exception as exc:
        sys.exit("DEVBOX OPENCODE HISTORY FAILED: " + type(exc).__name__)
    count = session_count(Path(sys.argv[2]))
    print("OPENCODE HISTORY: SQLite snapshot verified; session rows=" + (str(count) if count is not None else "unknown-schema"))

