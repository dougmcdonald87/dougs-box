"""Boundary checks for restore readiness and transient status outages."""
import importlib.util
import io
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
import urllib.error
import zipfile

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'scripts'))
spec = importlib.util.spec_from_file_location('relay', root / 'scripts' / 'terminal-relay.py')
relay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(relay)


class RelayBoundaryTests(unittest.TestCase):
    def test_invalid_artifact_is_rejected_without_retry(self):
        artifact = {'id':7, 'name':'devbox-terminal-123-1','expired':False}
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, 'w') as z:
            z.writestr('unexpected.txt', 'must not be used')
        response = io.BytesIO(archive.getvalue())
        with patch.dict(os.environ, {'GITHUB_REPOSITORY':'owner/repo','GITHUB_TOKEN':'test-only'}), patch.object(relay, 'windows_job', return_value={'status':'in_progress'}), patch.object(relay, 'api', return_value={'artifacts':[artifact]}), patch.object(relay.urllib.request, 'build_opener') as opener, patch.object(relay.time, 'sleep', side_effect=AssertionError('Invalid artifact was retried')):
            opener.return_value.open.return_value = response
            with self.assertRaisesRegex(ValueError, 'Unexpected artifact files'):
                relay.wait_for_manifest('123','1')

    def test_artifact_transport_error_can_recover(self):
        artifact = {'id':7, 'name':'devbox-terminal-123-1','expired':False}
        error = urllib.error.HTTPError('https://api.github.com/test', 503, 'temporary', {}, None)
        with patch.object(relay, 'windows_job', return_value={'status':'in_progress'}), patch.object(relay, 'api', return_value={'artifacts':[artifact]}), patch.object(relay, 'artifact_manifest', side_effect=[error, {'ready':True}]), patch.object(relay.time, 'sleep') as pause:
            self.assertEqual(relay.wait_for_manifest('123','1'), {'ready':True})
            pause.assert_called_once_with(5)

    def test_artifact_access_denial_is_not_retried(self):
        artifact = {'id':7, 'name':'devbox-terminal-123-1','expired':False}
        error = urllib.error.HTTPError('https://api.github.com/test', 403, 'denied', {}, None)
        with patch.object(relay, 'windows_job', return_value={'status':'in_progress'}), patch.object(relay, 'api', return_value={'artifacts':[artifact]}), patch.object(relay, 'artifact_manifest', side_effect=error), patch.object(relay.time, 'sleep') as pause:
            with self.assertRaises(urllib.error.HTTPError):
                relay.wait_for_manifest('123','1')
            pause.assert_not_called()

    def test_restore_over_twenty_minutes_remains_eligible(self):
        artifact = {'id': 7, 'name': 'devbox-terminal-123-1', 'expired': False}
        responses = [{'artifacts': []}] * 100 + [{'artifacts': [artifact]}]
        with patch.object(relay, 'windows_job', return_value={'status': 'in_progress'}), patch.object(relay, 'api', side_effect=responses), patch.object(relay, 'artifact_manifest', return_value={'ready': True}), patch.object(relay.time, 'sleep') as pause:
            self.assertEqual(relay.wait_for_manifest('123','1'), {'ready': True})
            self.assertEqual(sum(c.args[0] for c in pause.call_args_list), 1500)

    def test_startup_api_errors_recover_before_manifest(self):
        artifact = {'id': 7, 'name': 'devbox-terminal-123-1', 'expired': False}
        with patch.object(relay, 'windows_job', side_effect=[urllib.error.URLError('temporary'), {'status':'in_progress'}, {'status':'in_progress'}, {'status':'in_progress'}]), patch.object(relay, 'api', side_effect=[{}, TimeoutError(), {'artifacts':[artifact]}]), patch.object(relay, 'artifact_manifest', return_value={'ready':True}), patch.object(relay.time, 'sleep') as pause:
            self.assertEqual(relay.wait_for_manifest('123','1'), {'ready':True})
            self.assertEqual([c.args[0] for c in pause.call_args_list], [5,10,20])

    def test_completed_windows_job_never_enables_relay(self):
        with patch.object(relay, 'windows_job', return_value={'status':'completed'}), patch.object(relay, 'artifact_manifest') as download:
            with self.assertRaises(RuntimeError):
                relay.wait_for_manifest('123','1')
            download.assert_not_called()

    def test_duplicate_artifacts_are_not_arbitrarily_selected(self):
        artifact = {'id':7, 'name':'devbox-terminal-123-1','expired':False}
        with patch.object(relay, 'windows_job', return_value={'status':'in_progress'}), patch.object(relay, 'api', return_value={'artifacts':[artifact,artifact]}):
            with self.assertRaises(RuntimeError):
                relay.wait_for_manifest('123','1')

    def test_transient_failure_does_not_become_completion(self):
        active = {'status': 'in_progress'}
        with patch.object(relay, 'windows_job', side_effect=[urllib.error.URLError('temporary'), active]) as fetch, patch.object(relay.time, 'sleep') as pause:
            self.assertEqual(relay.resilient_job_status(), active)
            self.assertEqual(fetch.call_count, 2)
            pause.assert_called_once_with(5)

    def test_repeated_outage_backoff_is_bounded_and_recovers(self):
        ended = {'status': 'completed'}
        with patch.object(relay, 'windows_job', side_effect=[TimeoutError()] * 7 + [ended]), patch.object(relay.time, 'sleep') as pause:
            self.assertEqual(relay.resilient_job_status(), ended)
            self.assertEqual([c.args[0] for c in pause.call_args_list], [5,10,20,40,60,60,60])

    def test_restore_failure_cannot_publish_readiness_manifest(self):
        import yaml
        workflow = yaml.safe_load((root / '.github/workflows/devbox.yml').read_text())
        steps = workflow['jobs']['devbox']['steps']
        names = [s['name'] for s in steps]
        publish = names.index("Publish this run's public terminal host key")
        self.assertGreater(publish, names.index('Restore state (HOT first, Git canonical, small overlay)'))
        self.assertGreater(publish, names.index('First canary + backup proof'))
        self.assertEqual(steps[publish]['if'], "${{ success() && steps.terminal.outcome == 'success' }}")
        self.assertNotIn('Advertise Tailscale SSH', [s['name'] for s in workflow['jobs']['terminal-relay']['steps']])


if __name__ == '__main__':
    unittest.main()
