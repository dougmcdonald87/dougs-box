"""Controlled boundary attacks; never dispatch a live workflow or stop Windows."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('lifecycle', Path(__file__).resolve().parents[1] / 'scripts/devbox_lifecycle.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class LifecycleTests(unittest.TestCase):
    def test_active_run_blocks_dispatch(self):
        with patch.object(m, 'request', return_value=(200, {'total_count': 1, 'workflow_runs': [{'id': 17, 'status': 'waiting'}]})) as api:
            with self.assertRaises(m.DevBoxError): m.start('test-only')
            self.assertEqual(api.call_count, 1)
            self.assertNotIn('/dispatches', api.call_args.args[0])

    def test_unknown_status_blocks_dispatch(self):
        with patch.object(m, 'request', return_value=(200, {'total_count': 1, 'workflow_runs': [{'id': 17, 'status': 'unrecognized'}]})) as api:
            with self.assertRaises(m.DevBoxError): m.start('test-only')
            self.assertEqual(api.call_count, 1)

    def test_incomplete_inventory_blocks_dispatch(self):
        with patch.object(m, 'request', return_value=(200, {'total_count': 1, 'workflow_runs': []})):
            with self.assertRaises(m.DevBoxError): m.start('test-only')

    def test_modern_acceptance_is_not_ready(self):
        with patch.object(m, 'request', side_effect=[(200, {'total_count': 0, 'workflow_runs': []}), (200, {'workflow_run_id': 99})]) as api:
            result = m.start('test-only')
            self.assertEqual(result['run_id'], 99)
            self.assertFalse(result['ready'])
            self.assertEqual(api.call_args.args[2], {'ref': 'main', 'inputs': {'operation': 'start'}})
            self.assertEqual(api.call_count, 2)

    def test_legacy_acceptance_is_not_ready(self):
        with patch.object(m, 'request', side_effect=[(200, {'total_count': 0, 'workflow_runs': []}), (204, None)]):
            self.assertFalse(m.start('test-only')['ready'])

    def test_uncertain_dispatch_never_retries(self):
        with patch.object(m, 'request', side_effect=[(200, {'total_count': 0, 'workflow_runs': []}), m.DevBoxError('delivery unknown')]) as api:
            with self.assertRaises(m.DevBoxError): m.start('test-only')
            self.assertEqual(api.call_count, 2)

    def test_missing_iphone_token_is_not_invented(self):
        with patch.dict(os.environ, {}, clear=True), contextlib.redirect_stderr(io.StringIO()) as errors, patch.object(m, 'request') as api:
            self.assertEqual(m.main(['start']), 2)
            api.assert_not_called()
            self.assertIn('Keychain', errors.getvalue())

    def test_wrong_current_run_cannot_save_or_stop(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            (state / 'manifest.json').write_text(json.dumps({'version': 1, 'runId': '17'}))
            with patch.object(m.subprocess, 'run') as runner:
                with self.assertRaises(m.DevBoxError): m.safe_control('stop', 18, state)
                runner.assert_not_called()

    def test_failed_backup_is_not_success_or_cancel(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            (state / 'manifest.json').write_text(json.dumps({'version': 1, 'runId': '17'}))
            with patch.object(m.shutil, 'which', return_value='/usr/local/bin/devbox'), patch.object(m.subprocess, 'run', return_value=m.subprocess.CompletedProcess([], 2)) as runner:
                with self.assertRaises(m.DevBoxError): m.safe_control('stop', 17, state)
                argv = runner.call_args.args[0]
                self.assertIn('request-control.ps1', argv[-1])
                self.assertIn('NONINTERACTIVE', argv[-1])
                self.assertIn('-Action stop', argv[-1])
                self.assertEqual(runner.call_count, 1)

    def test_redirect_cannot_forward_bearer(self):
        self.assertIsNone(m.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://other.example'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
