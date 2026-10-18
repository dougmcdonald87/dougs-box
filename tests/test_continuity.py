import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "scripts" / "continuity.py"
spec = importlib.util.spec_from_file_location("continuity", SOURCE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class LedgerTests(unittest.TestCase):
    def test_required_kit_files_exist(self):
        self.assertEqual(module.validate(), [])

    def test_evidence_validation(self):
        self.assertTrue(module.evidence_ok("https://github.com/dougmcdonald87/dougs-box/actions/runs/1"))
        self.assertTrue(module.evidence_ok("a" * 40))
        self.assertFalse(module.evidence_ok("no evidence"))
        self.assertFalse(module.evidence_ok("https://other.example/secret"))

    def test_blocks_original(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ValueError):
                module.record(Path(temp), "original", "a", "a" * 40, "b", offline=True)

    def test_blocks_wrong_branch_without_offline(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ValueError):
                module.record(Path(temp), "pilot", "a", "a" * 40, "b", branch="main")

    def test_blocks_same_branch_wrong_repo(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ValueError):
                module.record(Path(temp), "pilot", "a", "a" * 40, "b",
                              branch=module.PILOT, remote="https://github.com/attacker/other.git")

    def test_pilot_identity_predicate(self):
        self.assertTrue(module.pilot_checkout(
            module.PILOT, "https://github.com/dougmcdonald87/dougs-box.git"))
        self.assertFalse(module.pilot_checkout(
            "main", "https://github.com/dougmcdonald87/dougs-box.git"))

    def test_append_only_local_ledger(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            a = module.record(root, "pilot", "first", "a" * 40, "next", offline=True)
            b = module.record(root, "pilot", "second", "b" * 40, "next2", offline=True)
            lines = (root / "state" / "LOCAL_EVENTS.ndjson").read_text().splitlines()
            self.assertEqual(len(lines), 2)
            self.assertEqual(json.loads(lines[0])["id"], a["id"])
            self.assertEqual(module.last(root)["id"], b["id"])
            self.assertTrue(module.last(root)["offline_unverified"])

    def test_empty_summary_blocked(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ValueError):
                module.record(Path(temp), "pilot", " ", "a" * 40, "next", offline=True)

if __name__ == "__main__":
    unittest.main()
