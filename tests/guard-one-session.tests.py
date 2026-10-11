"""Adversarial tests for duplicate-admission against GitHub run states."""
import datetime as dt
import importlib.util
import pathlib
import unittest
from unittest.mock import patch

path = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "guard-one-session.py"
spec = importlib.util.spec_from_file_location("guard_one_session", path)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)
clock = guard.parse_time("2026-10-11T21:00:00Z")


def run(number, state, created="2026-10-11T20:00:00Z", updated="2026-10-11T20:20:00Z"):
    return dict(id=number, status=state, created_at=created, updated_at=updated)


class AdmissionTests(unittest.TestCase):
    def test_running_older_blocks(self):
        self.assertEqual([(10, "in_progress")], guard.check_runs([run(10, "in_progress")], 11, clock))

    def test_queued_older_blocks(self):
        self.assertTrue(guard.check_runs([run(10, "queued")], 11, clock))

    def test_prior_completed_before_request_allows(self):
        self.assertFalse(guard.check_runs([run(10, "completed")], 11, clock))

    def test_prior_completed_during_queued_request_blocks(self):
        # Strongest competitor: a duplicate waits behind the first session.
        # By the time a Windows worker starts, the older run is completed,
        # but its completion was AFTER the duplicate was requested.
        self.assertTrue(guard.check_runs([
            run(10, "completed", updated="2026-10-11T22:00:00Z")
        ], 11, clock))

    def test_audit_run_never_blocks_original_desktop(self):
        a = run(10, "in_progress")
        a["display_title"] = guard.AUDIT_RUN_TITLE
        self.assertFalse(guard.check_runs([a], 11, clock))

    def test_completed_audit_during_launch_does_not_poison_start(self):
        a = run(10, "completed", updated="2026-10-11T22:00:00Z")
        a["display_title"] = guard.AUDIT_RUN_TITLE
        self.assertFalse(guard.check_runs([a], 11, clock))

    def test_regular_run_with_similar_name_still_blocks(self):
        a = run(10, "in_progress")
        a["display_title"] = "DevBox Archive Audit (Read Only) fake"
        self.assertTrue(guard.check_runs([a], 11, clock))

    def test_newer_runs_do_not_cancel_older(self):
        self.assertFalse(guard.check_runs([run(12, "in_progress")], 11, clock))

    def test_missing_timestamp_fails_closed(self):
        with self.assertRaises(guard.GuardError):
            guard.check_runs([dict(id=10, status="completed")], 11, clock)

    def test_api_error_fails_closed(self):
        with patch.object(guard.urllib.request, "urlopen", side_effect=OSError("offline")):
            with self.assertRaises(guard.GuardError):
                guard.fetch_runs("owner/repo", "ci-fake-test-token")

    def test_malformed_page_fails_closed(self):
        class Resp:
            status = 200
            def __enter__(self):
                return self
            def __exit__(self, *a):
                return False
        with patch.object(guard.urllib.request, "urlopen", return_value=Resp()):
            with patch.object(guard.json, "load", return_value={"workflow_runs": "wrong"}):
                with self.assertRaises(guard.GuardError):
                    guard.fetch_runs("owner/repo", "ci-fake-test-token")


if __name__ == "__main__":
    unittest.main(verbosity=2)
