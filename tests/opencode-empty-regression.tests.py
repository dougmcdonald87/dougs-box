"""An empty active profile must not replace the last populated history copy."""
import importlib.util
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('snapshot', Path(__file__).resolve().parents[1] / 'scripts/snapshot-opencode-db.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

def make_db(path, table, populated):
    with closing(sqlite3.connect(path)) as db:
        db.execute('CREATE TABLE "' + table + '" (id TEXT)')
        if populated:
            db.execute('INSERT INTO "' + table + '" VALUES (?)', ('saved-history',))
        db.commit()

class EmptyRegressionTests(unittest.TestCase):
    def test_empty_profile_cannot_replace_populated_backup(self):
        for table in ('session_v2', 'session', 'sessions'):
            with self.subTest(table=table), tempfile.TemporaryDirectory() as folder:
                source, dest = Path(folder) / 'active.db', Path(folder) / 'backup.db'
                make_db(source, table, False)
                make_db(dest, table, True)
                baseline = dest.read_bytes()
                with self.assertRaises(RuntimeError):
                    helper.snapshot(source, dest)
                self.assertEqual(baseline, dest.read_bytes())

    def test_missing_session_schema_cannot_replace_history(self):
        with tempfile.TemporaryDirectory() as folder:
            source, dest = Path(folder) / 'active.db', Path(folder) / 'backup.db'
            make_db(source, 'unrelated', True)
            make_db(dest, 'session', True)
            baseline = dest.read_bytes()
            with self.assertRaises(RuntimeError):
                helper.snapshot(source, dest)
            self.assertEqual(baseline, dest.read_bytes())

    def test_first_empty_database_is_allowed_and_reported_zero(self):
        with tempfile.TemporaryDirectory() as folder:
            source, dest = Path(folder) / 'active.db', Path(folder) / 'backup.db'
            make_db(source, 'session', False)
            helper.snapshot(source, dest)
            self.assertEqual(0, helper.session_count(dest))

    def test_v2_rows_are_counted(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'active.db'
            make_db(source, 'session_v2', True)
            self.assertEqual(1, helper.session_count(source))

    def test_v2_takes_precedence_over_retained_legacy_table(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'active.db'
            make_db(source, 'session', True)
            make_db(source, 'session_v2', False)
            self.assertEqual(0, helper.session_count(source))

if __name__ == '__main__':
    unittest.main(verbosity=2)
