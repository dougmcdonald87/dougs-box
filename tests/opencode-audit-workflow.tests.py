"""Attack: an audit dispatch must not start, queue or terminate a DevBox.

Static GitHub workflow graph checks; live Tailscale identity only real dispatch can test.
"""
import pathlib
import unittest
import yaml

BASE = pathlib.Path(__file__).resolve().parents[1]
workflow = yaml.safe_load((BASE / ".github/workflows/devbox.yml").read_text("utf-8"))
trigger = workflow.get("on", workflow.get(True))
jobs = workflow["jobs"]


class WorkflowIsolationTests(unittest.TestCase):
    def test_default_is_existing_start_mode(self):
        self.assertEqual("start", trigger["workflow_dispatch"]["inputs"]["operation"]["default"])
        self.assertEqual(["start", "inspect"], trigger["workflow_dispatch"]["inputs"]["operation"]["options"])

    def test_only_manual_dispatch(self):
        self.assertEqual(["workflow_dispatch"], list(trigger))

    def test_audit_skips_entire_desktop_dependency_chain(self):
        for name in ("preflight", "devbox"):
            self.assertIn("inputs.operation != 'inspect'", jobs[name]["if"])
        self.assertIn("inputs.operation == 'inspect'", jobs["audit"]["if"])

    def test_audit_uses_exact_authorized_workflow_ref_and_environment(self):
        self.assertEqual("devbox", jobs["audit"]["environment"])
        self.assertEqual("devbox", jobs["devbox"]["environment"])
        steps = jobs["audit"]["steps"]
        self.assertTrue(any("check-tailscale-oidc.ps1" in s.get("run", "") for s in steps))
        ts = [s for s in steps if "tailscale/github-action@" in s.get("uses", "")]
        self.assertEqual(1, len(ts))
        self.assertEqual("tag:github-devbox", ts[0]["with"]["tags"])
        self.assertEqual("latest", ts[0]["with"]["version"])
        self.assertEqual("id-token: write", "id-token: write" if workflow["permissions"].get("id-token") == "write" else "missing")

    def test_audit_has_no_desktop_or_cancel_or_backup_write(self):
        steps = "\n".join(str(s.get("name", "")) + str(s.get("run", "")) for s in jobs["audit"]["steps"]).lower()
        for bad in ("configure-rdp.ps1", "save-state.ps1", "restore-state.ps1",
                    "session-manager.ps1", "cancel", "restic forget", "restic prune"):
            self.assertNotIn(bad, steps)
        self.assertNotIn("concurrency", jobs["audit"])
        self.assertIn("cancel-in-progress", jobs["devbox"]["concurrency"])
        self.assertIs(False, jobs["devbox"]["concurrency"]["cancel-in-progress"])

    def test_guard_excludes_only_diagnostic_run(self):
        self.assertIn("DevBox Archive Audit (Read Only)", workflow["run-name"])
        self.assertIn("inputs.operation == 'inspect'", workflow["run-name"])
        src = (BASE / "scripts/guard-one-session.py").read_text("utf-8")
        self.assertIn("prior.get(\"display_title\") == AUDIT_RUN_TITLE", src)


if __name__ == "__main__":
    unittest.main(verbosity=2)
