"""Falsifiers for restoration of an unreadable or Windows-locked OpenCode DB."""
import importlib.util
from unittest import mock
import pathlib
import sqlite3
import tempfile
import unittest

script = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "restore-opencode-db.py"
spec = importlib.util.spec_from_file_location("restore_history", script)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


def make_db(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(path) as db:
        db.execute("CREATE TABLE sessions (id TEXT)")
        db.execute("INSERT INTO sessions VALUES (?)", (text,))
        db.commit()


def rows(path):
    with sqlite3.connect(path) as db:
        return db.execute("SELECT id FROM sessions").fetchall()


class RecoverTests(unittest.TestCase):
    def test_unlocked_import_reads_real_rows_and_runs_integrity(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            source, dest, rescue = root / "staged.db", root / "live" / "opencode.db", root / "rescue"
            make_db(source, "important-session")
            self.assertEqual(0, helper.restore(source, dest, rescue))
            self.assertEqual([("important-session",)], rows(dest))
            self.assertFalse(rescue.exists())

    def test_permission_error_preserves_preexisting_good_db_and_a_verified_copy(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            source, dest, rescue = root / "staged.db", root / "live" / "opencode.db", root / "rescue"
            make_db(source, "recovered")
            make_db(dest, "preexisting-live-session")
            # Mimic Windows file handle refusing os.replace (actual last
            # production failure). Only the replacement is fault-injected.
            with mock.patch.object(helper.module.os, "replace", side_effect=PermissionError("Windows sharing violation")):
                self.assertEqual(3, helper.restore(source, dest, rescue))
            self.assertEqual([("preexisting-live-session",)], rows(dest))
            rescued = list(rescue.glob("opencode-recovery-*.db"))
            self.assertEqual(1, len(rescued))
            self.assertEqual([("recovered",)], rows(rescued[0]))
            self.assertEqual(1, len(list(rescue.glob("*.json"))))

    def test_damaged_source_cannot_be_reported_as_restored_or_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            source, dest = root / "corrupt.db", root / "opencode.db"
            source.write_bytes(b"invalid sqlite source")
            make_db(dest, "last-good")
            with self.assertRaises(sqlite3.DatabaseError):
                helper.restore(source, dest, root / "rescue")
            self.assertEqual([("last-good",)], rows(dest))


if __name__ == "__main__":
    unittest.main(verbosity=2)
