#!/usr/bin/env python3
"""Import a staged OpenCode SQLite backup without losing it if Windows locks the live DB.

Exit 0: restored and verified. Exit 3: verified copy saved in the persistent
workspace Recovery directory for later import; live DB was not overwritten.
Exit 2: neither verified import nor verified preservation succeeded.
"""
from contextlib import closing
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import sys
import uuid

here = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("opencode_snapshot", here / "snapshot-opencode-db.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def restore(source: Path, destination: Path, recovery_dir: Path) -> int:
    source, destination, recovery_dir = Path(source), Path(destination), Path(recovery_dir)
    try:
        module.snapshot(source, destination)
        print("OPENCODE HISTORY RESTORED: SQLite integrity verified")
        return 0
    except PermissionError as error:
        # Windows denied replacement of the live DB, commonly because another
        # process holds an open handle. Never close user processes or remove DBs.
        # A UNIQUE recovery file avoids overwriting another preserved snapshot.
        recovery_dir.mkdir(parents=True, exist_ok=True)
        preserved = recovery_dir / ("opencode-recovery-" + uuid.uuid4().hex + ".db")
        module.snapshot(source, preserved)
        with closing(sqlite3.connect(preserved.as_uri() + "?mode=ro", uri=True)) as db:
            row = db.execute("PRAGMA integrity_check").fetchone()
            if row is None or row[0] != "ok":
                raise RuntimeError("Preserved database integrity check failed")
        notice = recovery_dir / (preserved.stem + ".json")
        notice.write_text(json.dumps({
            "status": "pending-import", "filename": preserved.name,
            "reason": type(error).__name__, "live_database_unmodified": True,
        }, indent=2), encoding="utf-8")
        print("OPENCODE HISTORY DEFERRED: live database locked or inaccessible; verified recovery copy preserved in " + str(preserved))
        return 3


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("Usage: restore-opencode-db.py SOURCE_DB DEST_DB PERSISTENT_RECOVERY_DIR")
    try:
        sys.exit(restore(*(Path(x) for x in sys.argv[1:])))
    except Exception as exc:
        print("OPENCODE HISTORY IMPORT FAILED: " + type(exc).__name__ + ": " + str(exc), file=sys.stderr)
        sys.exit(2)
