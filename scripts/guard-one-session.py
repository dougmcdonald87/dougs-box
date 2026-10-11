#!/usr/bin/env python3
"""Fail-closed GitHub Actions single-DevBox admission guard.

Runs twice: at workflow preflight, and again after Windows job concurrency.
The second check rejects jobs queued while an earlier session was alive.
Never dispatches, cancels, or mutates another workflow or device.
"""
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.request

WORKFLOW = "devbox.yml"
AUDIT_RUN_TITLE = "DevBox Archive Audit (Read Only)"
PAGE_SIZE = 100
MAX_PAGES = 10


class GuardError(RuntimeError):
    pass


def parse_time(value):
    if not value:
        raise GuardError("Missing run timestamp")
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def is_prior_conflict(prior, this_id, this_created):
    """Reject a prior run still active OR completed after current was created.

    Prior runs that overlap the current workflow's creation are duplicates,
    even when they finished while this Windows job was waiting in the queue.
    """
    # A read-only audit uses the same OIDC-authorized workflow path but\n    # has NO interactive DevBox. Never mistake it for a duplicate session.\n    if prior.get("display_title") == AUDIT_RUN_TITLE:\n        return False\n    identifier = int(prior["id"])
    if identifier >= this_id:
        return False
    status = prior.get("status")
    if status != "completed":
        return True
    updated = parse_time(prior.get("updated_at"))
    return updated >= this_created


def check_runs(runs, this_id, this_created):
    conflicts = []
    for prior in runs:
        if is_prior_conflict(prior, this_id, this_created):
            conflicts.append((prior["id"], prior.get("status")))
    return conflicts


def fetch_runs(repo, token):
    base = "https://api.github.com/repos/{}/actions/workflows/{}/runs".format(repo, WORKFLOW)
    collected = []
    for page in range(1, MAX_PAGES + 1):
        url = base + "?per_page={}&page={}".format(PAGE_SIZE, page)
        request = urllib.request.Request(url, headers={
            "Accept": "application/vnd.github+json",
            "Authorization": "Bearer " + token,
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "devbox-single-session-guard",
        })
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                if response.status != 200:
                    raise GuardError("Unverified GitHub runs HTTP {}".format(response.status))
                payload = json.load(response)
        except (OSError, ValueError, urllib.error.HTTPError) as exc:
            raise GuardError("Cannot verify prior runs: {}".format(type(exc).__name__)) from None
        if not isinstance(payload, dict) or not isinstance(payload.get("workflow_runs"), list):
            raise GuardError("Malformed GitHub runs response")
        collected.extend(payload["workflow_runs"])
        if len(collected) >= payload.get("total_count", 0):
            return collected
        if not payload["workflow_runs"]:
            raise GuardError("Incomplete GitHub runs list")
    raise GuardError("Run history exceeded safe check limit; launch refused")


def main():
    repo = os.environ["GITHUB_REPOSITORY"]
    run_id = int(os.environ["GITHUB_RUN_ID"])
    token = os.environ["GITHUB_TOKEN"]
    runs = fetch_runs(repo, token)
    matching = [r for r in runs if int(r.get("id", 0)) == run_id]
    if len(matching) != 1:
        raise GuardError("Current run absent or duplicated in API response")
    created = parse_time(matching[0].get("created_at"))
    conflicts = check_runs(runs, run_id, created)
    if conflicts:
        ids = ", ".join("{}({})".format(i, s) for i, s in conflicts[:5])
        raise GuardError("Refusing duplicate DevBox: older run overlapped this request: " + ids)
    print("DEVBOX SINGLE-SESSION GUARD PASS: no older overlapping workflow run")


if __name__ == "__main__":
    try:
        main()
    except (GuardError, KeyError, ValueError) as error:
        print("DEVBOX START BLOCKED: {}".format(error), file=sys.stderr)
        sys.exit(2)
