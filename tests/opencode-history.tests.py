"""Rule 1 tests for consistent OpenCode SQLite history snapshots."""
import importlib.util
import pathlib
import sqlite3
import tempfile
import unittest

path = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "snapshot-opencode-db.py"
spec = importlib.util.spec_from_file_location("snapshot_history", path)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class HistoryTests(unittest.TestCase):
    def test_open_sqlite_connection_and_consistent_commits(self):
        with tempfile.TemporaryDirectory() as folder:
            source = pathlib.Path(folder) / "user" / "opencode.db"
            source.parent.mkdir(parents=True)
            target = pathlib.Path(folder) / "backed-up" / "opencode.db"
            with sqlite3.connect(str(source)) as original:
                original.execute("CREATE TABLE sessions(id TEXT)")
                original.execute("INSERT INTO sessions VALUES('persisted')")
                original.commit()
                original.execute("INSERT INTO sessions VALUES('UNCOMMITTED')")
                # Keep transaction open while backup reads the WAL/DB.
                helper.snapshot(source, target)
                with sqlite3.connect(str(target)) as recovered:
                    rows = recovered.execute("SELECT id FROM sessions").fetchall()
                self.assertEqual([("persisted",)], rows)
                original.rollback()

    def test_missing_source_does_not_destroy_prior_good_backup(self):
        with tempfile.TemporaryDirectory() as folder:
            source = pathlib.Path(folder) / "missing.db"
            target = pathlib.Path(folder) / "current.db"
            target.write_bytes(b"existing snapshot")
            with self.assertRaises(FileNotFoundError):
                helper.snapshot(source, target)
            self.assertEqual(b"existing snapshot", target.read_bytes())

    def test_corrupt_sqlite_refused_without_overwriting_previous_backup(self):
        with tempfile.TemporaryDirectory() as folder:
            source = pathlib.Path(folder) / "corrupt.db"
            source.write_bytes(b"not a SQLite database")
            target = pathlib.Path(folder) / "last-good.db"
            target.write_bytes(b"leave alone")
            with self.assertRaises(sqlite3.DatabaseError):
                helper.snapshot(source, target)
            self.assertEqual(b"leave alone", target.read_bytes())

    def test_new_commits_snapshot_has_new_rows(self):
        with tempfile.TemporaryDirectory() as folder:
            source = pathlib.Path(folder) / "new.db"
            target = pathlib.Path(folder) / "backup.db"
            with sqlite3.connect(str(source)) as writer:
                writer.execute("CREATE TABLE sessions(id INTEGER)")
                writer.execute("INSERT INTO sessions VALUES (1)")
                writer.commit()
                helper.snapshot(source, target)
                writer.execute("INSERT INTO sessions VALUES (2)")
                writer.commit()
                helper.snapshot(source, target)
            with sqlite3.connect(str(target)) as reader:
                self.assertEqual(2, reader.execute("SELECT COUNT(*) FROM sessions").fetchone()[0])


if __name__ == "__main__":
    unittest.main(verbosity=2)
