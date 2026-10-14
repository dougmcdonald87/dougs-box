#!/usr/bin/env python3
"""Portable DevBox lifecycle client. No iOS modules or embedded credentials.

Start uses an existing DEVBOX_GITHUB_TOKEN, GH_TOKEN or GITHUB_TOKEN supplied
by the execution environment. Save/stop run on the authenticated Codex relay
through its installed, host-key-pinned `devbox` command. No GitHub cancellation.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

REPO = 'dougmcdonald87/dougs-box'
WORKFLOW = 'devbox.yml'
ROOT = f'https://api.github.com/repos/{REPO}/actions/workflows/{WORKFLOW}'
KNOWN_STATES = {'queued', 'in_progress', 'completed', 'waiting', 'requested', 'pending'}


class DevBoxError(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def existing_token(required=False):
    for name in ('DEVBOX_GITHUB_TOKEN', 'GH_TOKEN', 'GITHUB_TOKEN'):
        token = os.environ.get(name, '').strip()
        if token:
            return token
    if required:
        raise DevBoxError('No existing GitHub Actions-write credential is available here. Nothing started. The iPhone Keychain token is not included in the uploaded script.')
    return None


def request(url, token=None, payload=None):
    headers = {'Accept': 'application/vnd.github+json',
               'X-GitHub-Api-Version': '2026-03-10',
               'User-Agent': 'DevBox-Lifecycle'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    data = None if payload is None else json.dumps(payload).encode('utf-8')
    if data is not None:
        headers['Content-Type'] = 'application/json'
    req = urllib.request.Request(url, data=data, headers=headers,
                                 method='GET' if payload is None else 'POST')
    try:
        with urllib.request.build_opener(NoRedirect).open(req, timeout=30) as response:
            code, raw = response.status, response.read()
        return code, json.loads(raw.decode('utf-8')) if raw else None
    except urllib.error.HTTPError as exc:
        raise DevBoxError(f'GitHub HTTP {exc.code}. No automatic retry or cancellation.') from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise DevBoxError('Network failure. If a start request was sent, its outcome is UNKNOWN; check Actions before trying again.') from None
    except (ValueError, UnicodeError):
        raise DevBoxError('Malformed GitHub response. No automatic retry; check Actions before another start.') from None


def current_runs(token=None):
    runs = []
    for page in range(1, 11):
        code, data = request(ROOT + f'/runs?per_page=100&page={page}', token)
        if (code != 200 or not isinstance(data, dict) or
                not isinstance(data.get('workflow_runs'), list) or
                type(data.get('total_count')) is not int or data['total_count'] < 0):
            raise DevBoxError('Invalid workflow inventory. Refusing to start.')
        batch = data['workflow_runs']
        for run in batch:
            if (not isinstance(run, dict) or type(run.get('id')) is not int or
                    run['id'] <= 0 or run.get('status') not in KNOWN_STATES):
                raise DevBoxError('Invalid run record. Refusing to start.')
        runs.extend(batch)
        if len(runs) >= data['total_count']:
            return runs
        if not batch:
            raise DevBoxError('Incomplete workflow inventory. Refusing to start.')
    raise DevBoxError('Inventory exceeds safe pagination limit. Nothing started.')


def status(token=None):
    runs = current_runs(token)
    active = [r for r in runs if r['status'] != 'completed']
    return {'repository': REPO, 'active_runs': [
        {'id': r['id'], 'status': r['status'], 'url': r.get('html_url')}
        for r in active], 'latest': ({'id': runs[0]['id'], 'status': runs[0]['status'],
                                    'conclusion': runs[0].get('conclusion')} if runs else None)}


def start(token, backend='home'):
    if backend not in ('home','github-release','migrate-to-github'):
        raise DevBoxError('Unsupported persistence backend. Nothing started.')
    if not token:
        raise DevBoxError('GitHub write credential missing. Nothing started.')
    active = [r for r in current_runs(token) if r['status'] != 'completed']
    if active:
        raise DevBoxError(f'Existing workflow run {active[0]["id"]} is {active[0]["status"]}. Nothing started.')
    # Exactly one POST; uncertain delivery is never retried automatically.
    # Server preflight + Windows serialization remain the cross-device guard.
    inputs = {'operation':'start'}
    if backend != 'home':
        inputs['persistence_backend'] = backend
    code, result = request(ROOT + '/dispatches', token,
                           {'ref': 'main', 'inputs': inputs})
    if code == 200:
        if not isinstance(result, dict) or type(result.get('workflow_run_id')) is not int or result['workflow_run_id'] <= 0:
            raise DevBoxError('Start response lacks a valid run ID. Delivery uncertain; check Actions before another request.')
        return {'accepted': True, 'ready': False, 'run_id': result['workflow_run_id'],
                'detail': 'Request accepted; restore and first verified backup still need to finish.'}
    if code == 204:
        return {'accepted': True, 'ready': False, 'run_id': None,
                'detail': 'Legacy empty acceptance response; inspect Actions to identify the run.'}
    raise DevBoxError(f'Unexpected dispatch HTTP {code}. No retry; check Actions before another request.')


def control_command(action):
    if action not in ('save', 'stop'):
        raise DevBoxError('Unsupported control action.')
    return ('$ErrorActionPreference="Stop"; '
            '$env:DEVBOX_CONTROL_NONINTERACTIVE="1"; '
            '$client=Join-Path $env:DEVBOX_WSROOT "Tools\\DevBoxControls\\request-control.ps1"; '
            'if (!(Test-Path -LiteralPath $client -PathType Leaf)) { throw "Installed control client missing" }; '
            f'& $client -Action {action}')


def safe_control(action, expected_run_id, state=Path('/run/devbox-control')):
    if not expected_run_id or not str(expected_run_id).isdigit():
        raise DevBoxError('An explicit positive current --run-id is required.')
    try:
        manifest = json.loads((Path(state) / 'manifest.json').read_text(encoding='utf-8-sig'))
    except (OSError, ValueError, UnicodeError):
        raise DevBoxError('Current relay manifest unavailable. Nothing requested.') from None
    if (not isinstance(manifest, dict) or manifest.get('version') != 1 or
            manifest.get('runId') != str(expected_run_id)):
        raise DevBoxError('Relay is paired with a different run. Nothing requested.')
    executable = shutil.which('devbox')
    if executable is None:
        raise DevBoxError('Run save/stop inside the authenticated Codex relay terminal. No local devbox client is installed here.')
    try:
        result = subprocess.run([executable, '--state', str(state), '--timeout', '0',
                                 control_command(action)], timeout=None, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise DevBoxError('Control result UNKNOWN. Inspect the run and backup receipt; no automatic retry or cancellation.') from None
    if result.returncode != 0:
        raise DevBoxError('Verified control success was not confirmed. Inspect the run and backup receipt; never substitute GitHub Cancel.')
    return {'action': action, 'run_id': int(expected_run_id),
            'detail': 'Installed Windows control client returned success after checking a fresh verified snapshot. For stop, independently confirm the Windows job ends.'}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('status', 'start', 'save', 'stop'))
    parser.add_argument('--run-id', type=int)
    parser.add_argument('--backend', choices=('home','github-release','migrate-to-github'), default='home',
                        help='Persistence selection for manual start; normal default remains home.')
    parser.add_argument('--state', type=Path, default=Path('/run/devbox-control'))
    args = parser.parse_args(argv)
    try:
        if args.command == 'status':
            result = status(existing_token())
        elif args.command == 'start':
            result = start(existing_token(required=True), args.backend)
        else:
            if args.run_id is None or args.run_id <= 0:
                raise DevBoxError('Use --run-id with the exact current Windows workflow run.')
            result = safe_control(args.command, args.run_id, args.state)
        print(json.dumps(result, indent=2))
        return 0
    except DevBoxError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print('Interrupted; any already-sent request may still be running. No retry.', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
