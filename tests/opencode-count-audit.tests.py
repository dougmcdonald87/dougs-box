"""Inspect only bounded DB bytes and never invoke repository write commands."""
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('audit', Path(__file__).resolve().parents[1] / 'scripts/inspect-opencode-snapshots.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

class CountTests(unittest.TestCase):
    def test_real_sqlite_count_without_titles_or_repository_writes(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'source.db'
            db = sqlite3.connect(path)
            db.execute('CREATE TABLE session_v2 (id TEXT, title TEXT)')
            db.execute("INSERT INTO session_v2 VALUES ('1', 'PRIVATE TITLE')")
            db.commit()
            db.close()
            content = path.read_bytes()
            node = {'type': 'file', 'path': '/D/DevBox/PersistentData/OpenCodeHistory/opencode.db', 'size': len(content)}
            def dump(args, **kwargs):
                self.assertEqual(['--no-lock', 'dump', 'snapshot', node['path']], args[3:])
                kwargs['stdout'].write(content)
                return SimpleNamespace(returncode=0)
            with patch.object(audit.subprocess, 'run', side_effect=dump):
                self.assertEqual('1', audit.session_rows('restic', 'snapshot', json.dumps(node)))

    def test_ambiguous_and_oversize_do_not_download(self):
        node = {'type':'file', 'path':'/D/DevBox/PersistentData/OpenCodeHistory/opencode.db', 'size': 300 * 1024 * 1024}
        with patch.object(audit.subprocess, 'run') as run:
            self.assertEqual('size-limit-or-unknown', audit.session_rows('restic', 'id', json.dumps(node)))
            self.assertEqual('ambiguous', audit.session_rows('restic', 'id', '\n'.join([json.dumps(node)] * 2)))
            run.assert_not_called()

if __name__ == '__main__':
    unittest.main(verbosity=2)
