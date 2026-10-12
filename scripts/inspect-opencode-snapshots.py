#!/usr/bin/env python3
"""Metadata-only Restic inventory. No secret values or restored file contents."""
import argparse
import datetime as dt
import json
import os
import subprocess
import tempfile
from pathlib import Path
import importlib.util
from collections import Counter

REPO = "rest:http://100.70.202.110:8000/devbox/"

def session_rows(exe, snapshot_id, lines):
    """Read one bounded DB into private temporary storage; emit only a count."""
    candidates = []
    for line in lines.splitlines():
        if not line.strip():
            continue
        item = json.loads(line)
        path = str(item.get('path', ''))
        normalized = path.replace('\\', '/').lower()
        if item.get('type') == 'file' and normalized.endswith('/opencode.db'):
            if '/persistentdata/opencodehistory/' in normalized or '/.local/share/opencode/' in normalized:
                candidates.append(item)
    staged = [x for x in candidates if '/persistentdata/opencodehistory/' in str(x['path']).replace('\\', '/').lower()]
    selected = staged or candidates
    if not selected:
        return 'absent'
    if len(selected) != 1:
        return 'ambiguous'
    size = selected[0].get('size')
    if not isinstance(size, int) or size < 0 or size > 256 * 1024 * 1024:
        return 'size-limit-or-unknown'
    spec = importlib.util.spec_from_file_location('history_counts', Path(__file__).resolve().with_name('snapshot-opencode-db.py'))
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    with tempfile.TemporaryDirectory(prefix='devbox-history-count-') as folder:
        db_path = Path(folder) / 'history.db'
        with db_path.open('wb') as target:
            proc = subprocess.run([exe, '--repo', REPO, '--no-lock', 'dump', str(snapshot_id), str(selected[0]['path'])],
                                  stdout=target, stderr=subprocess.PIPE, check=False, timeout=180)
        if proc.returncode or db_path.stat().st_size != size:
            return 'dump-failed'
        try:
            count = helper.session_count(db_path)
            return str(count) if count is not None else 'unknown-schema'
        except Exception:
            return 'unreadable'

def parse_time(x):
    return dt.datetime.fromisoformat(str(x).replace("Z", "+00:00"))

def restic(exe, args):
    proc = subprocess.run([exe, "--repo", REPO, "--no-lock", *args], capture_output=True,
                          text=True, check=False, timeout=180)
    if proc.returncode:
        raise RuntimeError("Read-only Restic query failed (exit {})".format(proc.returncode))
    return proc.stdout

def classify(lines):
    out = Counter()
    for line in lines.splitlines():
        if not line.strip():
            continue
        o = json.loads(line)
        p = str(o.get("path", "")).replace("\\", "/").lower()
        file = o.get("type") == "file"
        if "/.config/opencode/" in p:
            out["config_entries"] += 1
            if file:
                out["config_files"] += 1
            if p.endswith("/opencode.json") or p.endswith("/opencode.jsonc"):
                out["opencode_json"] += 1
            if p.endswith("/package.json"):
                out["package_json"] += 1
        if file and p.endswith("/opencode.db"):
            if "/persistentdata/opencodehistory/" in p:
                out["staged_db"] += 1
            elif "/.local/share/opencode/" in p:
                out["old_user_db"] += 1
            else:
                out["other_db"] += 1
        if file and "/.local/share/opencode/project/" in p:
            out["legacy_session"] += 1
    return out

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--restic-exe", required=True)
    p.add_argument("--cutoff", default="2026-10-11T22:27:07Z")
    p.add_argument("--max-prior", type=int, default=18)
    p.add_argument('--session-counts', action='store_true', help='Count rows in up to three newest selected DB copies; repository stays read-only')
    a = p.parse_args()
    if not 1 <= a.max_prior <= 30:
        p.error("max-prior must be 1..30")
    if not os.environ.get("RESTIC_PASSWORD") or not os.environ.get("RESTIC_REST_PASSWORD"):
        raise RuntimeError("Missing encrypted repository credentials; nothing queried")
    snapshots = json.loads(restic(a.restic_exe, ["snapshots", "--json"]))
    if not isinstance(snapshots, list):
        raise RuntimeError("Malformed snapshot listing")
    snapshots = [s for s in snapshots if 'devbox-verified-receipt-v1' not in s.get('tags', [])]
    cutoff = parse_time(a.cutoff)
    prior = sorted((s for s in snapshots if parse_time(s["time"]) < cutoff), key=lambda s: parse_time(s["time"]))
    after = sorted((s for s in snapshots if parse_time(s["time"]) >= cutoff), key=lambda s: parse_time(s["time"]))
    chosen = [("OLDER", s) for s in prior[-a.max_prior:]]
    if after:
        chosen.append(("LATEST", after[-1]))
    print("INVENTORY older={} newer={} examined={}".format(len(prior),len(after),len(chosen)))
    remaining_counts = 3 if a.session_counts else 0
    for tag, s in reversed(chosen):
        lines = restic(a.restic_exe, ["ls", "--json", str(s["id"])])
        c = classify(lines)
        rows = 'not-inspected'
        if remaining_counts and (c['staged_db'] or c['old_user_db']):
            rows = session_rows(a.restic_exe, s['id'], lines)
            remaining_counts -= 1
        elif not c['staged_db'] and not c['old_user_db']:
            rows = 'absent'
        paths = [str(x).replace("\\","/").lower() for x in s.get("paths", [])]
        listed = any("/.config/opencode" in x for x in paths)
        print("{} snapshot={} date={} config_manifest={} config_files={} config_entries={} opencode_json={} package_json={} legacy_files={} staged_db={} old_user_db={} other_db={} session_rows={}".format(
            tag, str(s["id"])[:12], s["time"], listed, c["config_files"],
            c["config_entries"], c["opencode_json"], c["package_json"],
            c["legacy_session"], c["staged_db"], c["old_user_db"], c["other_db"], rows))
    print("AUDIT COMPLETE: no repository writes; temporary count copies deleted; no conversation contents printed.")

if __name__ == "__main__":
    main()

