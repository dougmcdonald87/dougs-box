#!/usr/bin/env python3
"""Portable, offline-first DevBox handoff ledger. Never launches a workflow."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
EVENTS = ROOT / "state" / "LOCAL_EVENTS.ndjson"
PILOT = "pilot/windows-home-connection-20261015"
REQUIRED = [
    "AGENTS.md",
    "state/CURRENT.json",
    "references/MACHINE_REGISTRY.md",
    "references/ACCEPTANCE.md",
    ".opencode/skills/devbox-continuity/SKILL.md",
]

def git_branch(cwd=ROOT):
    try:
        proc = subprocess.run(
            ["git", "branch", "--show-current"], cwd=cwd,
            capture_output=True, text=True, timeout=5, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return proc.stdout.strip() if proc.returncode == 0 else None

def git_remote(cwd=ROOT):
    try:
        proc = subprocess.run(
            ["git", "config", "--get", "remote.origin.url"], cwd=cwd,
            capture_output=True, text=True, timeout=5, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return proc.stdout.strip() if proc.returncode == 0 else None

def pilot_checkout(branch, remote):
    allowed = {
        "https://github.com/dougmcdonald87/dougs-box",
        "https://github.com/dougmcdonald87/dougs-box.git",
        "git@github.com:dougmcdonald87/dougs-box.git",
        "ssh://git@github.com/dougmcdonald87/dougs-box.git",
    }
    return branch == PILOT and remote in allowed

def evidence_ok(value):
    if not isinstance(value, str) or len(value) > 1500:
        return False
    return value.startswith("https://github.com/") or bool(re.fullmatch(r"[0-9a-f]{40}", value))

def validate(root=ROOT):
    missing = [p for p in REQUIRED if not (root / p).is_file()]
    try:
        data = json.loads((root / "state" / "CURRENT.json").read_text(encoding="utf-8"))
        if data.get("schema_version") != 2 or data.get("kind") != "historical-observation-not-live":
            missing.append("invalid CURRENT.json contract")
    except (OSError, ValueError):
        missing.append("unreadable CURRENT.json")
    return missing

def record(root, target, summary, evidence, next_action, offline=False, branch=None, remote=None):
    if target != "pilot":
        raise ValueError("original and personal targets are not writable by this ledger")
    if not summary.strip() or not next_action.strip():
        raise ValueError("summary and next action must be nonempty")
    if len(summary) > 1000 or len(next_action) > 1000:
        raise ValueError("summary/next action too long")
    if not evidence_ok(evidence):
        raise ValueError("evidence must be a GitHub URL or 40-char SHA")
    current = git_branch(root) if branch is None else branch
    origin = git_remote(root) if remote is None else remote
    if not offline and not pilot_checkout(current, origin):
        raise ValueError("live checkpoint requires matching pilot branch AND GitHub origin; use --offline for extracted kit")
    event = {
        "id": str(uuid.uuid4()),
        "utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "target": target,
        "branch_observed": current,
        "origin_observed": origin,
        "offline_unverified": bool(offline),
        "summary": summary.strip(),
        "evidence": evidence,
        "next_action": next_action.strip(),
    }
    dest = root / "state" / "LOCAL_EVENTS.ndjson"
    dest.parent.mkdir(parents=True, exist_ok=True)
    data = (json.dumps(event, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")
    fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, data)
        os.fsync(fd)
    finally:
        os.close(fd)
    return event

def last(root=ROOT):
    if not (root / "state" / "LOCAL_EVENTS.ndjson").exists():
        return None
    lines = (root / "state" / "LOCAL_EVENTS.ndjson").read_text(encoding="utf-8").splitlines()
    return json.loads(lines[-1]) if lines else None

def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("doctor")
    sub.add_parser("last")
    c = sub.add_parser("checkpoint")
    c.add_argument("--target", required=True, choices=["pilot", "original", "personal"])
    c.add_argument("--summary", required=True)
    c.add_argument("--evidence", required=True)
    c.add_argument("--next", required=True, dest="next_action")
    c.add_argument("--offline", action="store_true")
    a = p.parse_args(argv)
    if a.cmd == "doctor":
        missing = validate()
        print(json.dumps({
            "missing_or_invalid": missing,
            "git_branch": git_branch(),
            "historical_snapshot_only": True,
            "pilot_checkout_name_and_remote_match": pilot_checkout(git_branch(), git_remote()),
            "git_origin": git_remote(),
            "remote_connectivity_checked": False,
        }, indent=2))
        return 1 if missing else 0
    if a.cmd == "last":
        print(json.dumps(last(), indent=2))
        return 0
    try:
        print(json.dumps(record(ROOT, a.target, a.summary, a.evidence, a.next_action, a.offline), indent=2))
    except ValueError as e:
        print(f"BLOCKED: {e}", file=sys.stderr)
        return 2
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
