"""Real loopback Windows SSH: stopped baseline, bad auth/key, two setups and command."""
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys

import paramiko

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from devbox_terminal import connect, execute


def setup(address='127.0.0.1'):
    subprocess.run(['pwsh', '-NoProfile', '-File', 'scripts/configure-terminal.ps1', '-IsolatedTest', '-TestListenAddress', address], check=True)


password = os.environ['TERMINAL_TEST_PASSWORD']
root = Path(os.environ['DEVBOX_CONTROL_PATH'])
# A stopped listener must reject actual connections, not merely fail a health flag.
subprocess.run(['pwsh', '-NoProfile', '-Command', 'Stop-Service sshd -ErrorAction SilentlyContinue'], check=True)
try:
    import socket
    socket.create_connection(('127.0.0.1', 22), timeout=2).close()
except OSError:
    print('STOPPED SSH BASELINE: connection rejected')
else:
    raise AssertionError('Baseline still has an SSH listener')
setup()
manifest = json.loads((root / 'Terminal' / 'manifest.json').read_text(encoding='utf-8-sig'))
try:
    connect(manifest, password + '-wrong')
except paramiko.AuthenticationException:
    print('WRONG PASSWORD: rejected')
else:
    raise AssertionError('Wrong password accepted')
wrong = dict(manifest)
wrong['hostKey'] = 'ssh-ed25519 ' + paramiko.Ed25519Key(data=__import__('base64').b64decode(manifest['hostKey'].split()[1])).get_base64()
key_bytes = bytearray(__import__('base64').b64decode(wrong['hostKey'].split()[1]))
key_bytes[-1] ^= 1
wrong['hostKey'] = 'ssh-ed25519 ' + __import__('base64').b64encode(key_bytes).decode()
try:
    connect(wrong, password)
except paramiko.BadHostKeyException:
    print('WRONG HOST KEY: rejected before authentication')
else:
    raise AssertionError('Unpinned host key accepted')
first_manifest = dict(manifest)
for attempt in range(3):
    if attempt:
        setup('127.0.0.2')
        manifest = json.loads((root / 'Terminal' / 'manifest.json').read_text(encoding='utf-8-sig'))
        assert manifest['address'] == '127.0.0.2'
        if attempt == 1:
            try:
                connect(first_manifest, password)
            except (OSError, paramiko.ssh_exception.NoValidConnectionsError):
                print('OLD ADDRESS AFTER LISTENER MOVE: rejected')
            else:
                raise AssertionError('Old address remains active after move')
    output = io.StringIO()
    proof = root / 'ssh-command-proof.txt'
    command = f"$ErrorActionPreference='Stop'; [IO.File]::WriteAllText('{str(proof)}','remote-command-{attempt}'); Write-Output 'SSH_COMMAND_EXECUTED_{attempt}'; exit 0"
    with contextlib.redirect_stdout(output):
        assert execute(manifest, password, command, 30) == 0
    assert f'SSH_COMMAND_EXECUTED_{attempt}' in output.getvalue()
    assert proof.read_text() == f'remote-command-{attempt}'
    print(f'REAL WINDOWS SSH EXECUTION AFTER SETUP {attempt + 1}: PASS')
print('WINDOWS TERMINAL REAL SOCKET/AUTH/HOST-KEY/ADDRESS-CHANGE/COMMAND/REPEAT ATTACK: SURVIVED')
