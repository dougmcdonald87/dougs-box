#!/usr/bin/env python3
"""Metadata-only Restic inventory. No secret values or restored file contents."""
import argparse
import datetime as dt
import json
import os
import subprocess
from collections import Counter

REPO = "rest:http://100.70.202.110:8000/devbox/"

def parse_time(x):
    return dt.datetime.fromisoformat(str(x).replace("Z", "+00:00"))

def restic(exe, args):
    proc = subprocess.run([exe, "--repo", REPO, *args], capture_output=True,
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
    a = p.parse_args()
    if not 1 <= a.max_prior <= 30:
        p.error("max-prior must be 1..30")
    if not os.environ.get("RESTIC_PASSWORD") or not os.environ.get("RESTIC_REST_PASSWORD"):
        raise RuntimeError("Missing encrypted repository credentials; nothing queried")
    snapshots = json.loads(restic(a.restic_exe, ["snapshots", "--json"]))
    if not isinstance(snapshots, list):
        raise RuntimeError("Malformed snapshot listing")
    cutoff = parse_time(a.cutoff)
    prior = sorted((s for s in snapshots if parse_time(s["time"]) < cutoff), key=lambda s: parse_time(s["time"]))
    after = sorted((s for s in snapshots if parse_time(s["time"]) >= cutoff), key=lambda s: parse_time(s["time"]))
    chosen = [("OLDER", s) for s in prior[-a.max_prior:]]
    if after:
        chosen.append(("LATEST", after[-1]))
    print("INVENTORY older={} newer={} examined={}".format(len(prior),len(after),len(chosen)))
    for tag, s in chosen:
        c = classify(restic(a.restic_exe, ["ls", "--json", str(s["id"])]))
        paths = [str(x).replace("\\","/").lower() for x in s.get("paths", [])]
        listed = any("/.config/opencode" in x for x in paths)
        print("{} snapshot={} date={} config_manifest={} config_files={} config_entries={} opencode_json={} package_json={} legacy_files={} staged_db={} old_user_db={} other_db={}".format(
            tag, str(s["id"])[:12], s["time"], listed, c["config_files"],
            c["config_entries"], c["opencode_json"], c["package_json"],
            c["legacy_session"], c["staged_db"], c["old_user_db"], c["other_db"]))
    print("AUDIT COMPLETE: no files restored, no repository writes, no file contents printed.")

if __name__ == "__main__":
    main()
