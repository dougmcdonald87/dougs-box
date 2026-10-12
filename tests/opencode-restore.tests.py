"""Falsifiers for restoration of an unreadable or Windows-locked OpenCode DB."""
import importlib.util
from contextlib import closing
from unittest import mock
import pathlib
import sqlite3
import sys
import tempfile
import unittest

script = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "restore-opencode-db.py"
spec = importlib.util.spec_from_file_location("restore_history", script)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


def make_db(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    with closing(sqlite3.connect(path)) as db:
        db.execute("CREATE TABLE sessions (id TEXT)")
        db.execute("INSERT INTO sessions VALUES (?)", (text,))
        db.commit()


def rows(path):
    with closing(sqlite3.connect(path)) as db:
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
            actual_replace = helper.module.os.replace
            def lock_only_live_destination(tmp_path, final_path):
                if pathlib.Path(final_path) == dest:
                    raise PermissionError("Windows sharing violation")
                return actual_replace(tmp_path, final_path)
            with mock.patch.object(helper.module.os, "replace", side_effect=lock_only_live_destination):
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


    @unittest.skipUnless(sys.platform == "win32", "Windows locking semantics only")
    def test_real_windows_handle_lock_keeps_old_db_and_preserves_new_history(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            source = root / "saved.db"
            dest = root / "live" / "opencode.db"
            rescue = root / "recovery"
            make_db(source, "staged-new-history")
            make_db(dest, "currently-open-history")
            connection = sqlite3.connect(str(dest))
            try:
                connection.execute("BEGIN IMMEDIATE")
                status = helper.restore(source, dest, rescue)
                self.assertEqual(3, status, "A live Windows SQLite handle should prevent atomic replacement")
                self.assertEqual([("currently-open-history",)], connection.execute("SELECT id FROM sessions").fetchall())
            finally:
                connection.rollback()
                connection.close()
            preserved = list(rescue.glob("opencode-recovery-*.db"))
            self.assertEqual(1, len(preserved))
            self.assertEqual([("staged-new-history",)], rows(preserved[0]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
