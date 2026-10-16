"""Wait for this run's public host-key artifact; hold relay only while Windows runs."""
import io
import ipaddress
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

from devbox_terminal import execute


def resilient_job_status():
    """Transient status failures cannot close a healthy Windows connection."""
    delay = 5
    while True:
        try:
            return windows_job()
        except (urllib.error.URLError, TimeoutError, OSError, ValueError, KeyError):
            print('GitHub status temporarily unavailable; keeping relay alive and retrying.', flush=True)
            time.sleep(delay)
            delay = min(60, delay * 2)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def api(path):
    url = f"https://api.github.com/repos/{os.environ['GITHUB_REPOSITORY']}/{path}"
    request = urllib.request.Request(url, headers={
        'Authorization': 'Bearer ' + os.environ['GITHUB_TOKEN'],
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
    })
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def artifact_manifest(artifact_id):
    url = f"https://api.github.com/repos/{os.environ['GITHUB_REPOSITORY']}/actions/artifacts/{artifact_id}/zip"
    request = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + os.environ['GITHUB_TOKEN']})
    try:
        response = urllib.request.build_opener(NoRedirect).open(request, timeout=30)
    except urllib.error.HTTPError as exc:
        if exc.code != 302:
            raise
        location = exc.headers['Location']
        parsed = urllib.parse.urlparse(location)
        if parsed.scheme != 'https' or not (parsed.hostname.endswith('.blob.core.windows.net') or parsed.hostname.endswith('.githubusercontent.com')):
            raise ValueError('Unexpected artifact storage origin')
        # Never send the GitHub bearer token to the storage redirect.
        response = urllib.request.urlopen(location, timeout=30)
    with response:
        data = response.read(65537)
    if len(data) > 65536:
        raise ValueError('Unexpectedly large public host-key artifact')
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        if archive.namelist() != ['manifest.json'] or archive.getinfo('manifest.json').file_size > 8192:
            raise ValueError('Unexpected artifact files')
        return json.loads(archive.read('manifest.json').decode('utf-8-sig'))


def windows_job():
    run_id = os.environ['GITHUB_RUN_ID']
    jobs = api(f'actions/runs/{run_id}/jobs?filter=latest&per_page=100')['jobs']
    return next((job for job in jobs if job['name'].startswith('DevBox session (')), None)


def wait_for_manifest(run_id, attempt):
    """Wait while Windows is healthy; the enclosing Actions job bounds lifetime."""
    expected = f'devbox-terminal-{run_id}-{attempt}'
    delay = 5
    while True:
        try:
            job = windows_job()
            if job and job['status'] == 'completed':
                raise RuntimeError('Windows session finished before relay startup')
            artifacts = api(f'actions/runs/{run_id}/artifacts?per_page=100')['artifacts']
            candidates = [a for a in artifacts if a['name'] == expected and not a['expired']]
        except (urllib.error.URLError, TimeoutError, OSError, ValueError, KeyError, TypeError):
            print('Startup metadata temporarily unavailable; waiting without enabling SSH.', flush=True)
            time.sleep(delay)
            delay = min(60, delay * 2)
            continue
        if len(candidates) > 1:
            raise RuntimeError('Ambiguous host-key artifact')
        if len(candidates) == 1:
            try:
                return artifact_manifest(candidates[0]['id'])
            except urllib.error.HTTPError as exc:
                if exc.code not in (408, 429) and exc.code < 500:
                    raise
            except (urllib.error.URLError, TimeoutError, OSError):
                pass
            # Only transport failures and retryable HTTP responses reach here.
            # Invalid ZIP/JSON, files, size or origin must terminate startup.
            print('Artifact transport temporarily unavailable; retrying without enabling SSH.', flush=True)
            time.sleep(delay)
            delay = min(60, delay * 2)
            continue
        delay = 5
        time.sleep(15)


def main():
    run_id, attempt = os.environ['GITHUB_RUN_ID'], os.environ['GITHUB_RUN_ATTEMPT']
    manifest = wait_for_manifest(run_id, attempt)
    if (manifest.get('version') != 1 or manifest.get('runId') != run_id or
            manifest.get('runAttempt') != attempt or manifest.get('account') not in ('runneradmin', 'devbox') or
            ipaddress.ip_address(manifest['address']) not in ipaddress.ip_network('100.64.0.0/10')):
        raise ValueError('Manifest does not identify this run and tailnet endpoint')
    state = Path('/run/devbox-control')
    state.mkdir(mode=0o700, exist_ok=True)
    os.chmod(state, 0o700)
    (state / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
    password = os.environ.pop('DEVBOX_RDP_PASSWORD')
    if not password:
        raise ValueError('Existing RDP credential missing')
    password_path = state / 'password'
    password_path.touch(mode=0o600, exist_ok=True)
    os.chmod(password_path, 0o600)
    password_path.write_text(password, encoding='utf-8')
    try:
        result = execute(manifest, password, "Write-Output ('DEVBOX REMOTE COMMAND PASS: ' + $env:COMPUTERNAME); whoami")
        if result != 0:
            raise RuntimeError('Harmless Windows command returned nonzero')
        # The manifest is published only AFTER restore and first verified backup.
        # Do not expose browser root access before that acceptance boundary.
        subprocess.run(['tailscale', 'set', '--ssh'], check=True)
        print('TAILNET WINDOWS COMMAND TEST: SURVIVED. Browser SSH still requires its own acceptance test.', flush=True)
        print('RELAY READY: use the Tailscale SSH console as root, then run devbox.', flush=True)
        while True:
            job = resilient_job_status()
            if job and job['status'] == 'completed':
                print('Windows job ended; relay closing.', flush=True)
                return
            time.sleep(30)
    finally:
        subprocess.run(['tailscale', 'set', '--ssh=false'], check=False)
        password_path.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
