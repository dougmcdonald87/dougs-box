"""Pinned-host SSH command client. No public listener or unverified host keys."""
import argparse
import base64
import json
import os
from pathlib import Path
import sys
import time

import paramiko


def connect(manifest, password):
    kind, encoded, *_ = manifest['hostKey'].split()
    if kind != 'ssh-ed25519':
        raise ValueError('Only the manifest ed25519 host key is accepted')
    key = paramiko.Ed25519Key(data=base64.b64decode(encoded, validate=True))
    client = paramiko.SSHClient()
    client.get_host_keys().add(manifest['address'], kind, key)
    client.set_missing_host_key_policy(paramiko.RejectPolicy())
    try:
        client.connect(manifest['address'], username=manifest['account'], password=password,
                       look_for_keys=False, allow_agent=False, timeout=15,
                       auth_timeout=15, banner_timeout=15)
    except Exception:
        client.close()
        raise
    return client


def execute(manifest, password, command, timeout=300):
    prefix = []
    for name, field in [('DEVBOX_WSROOT', 'workspaceRoot'), ('DEVBOX_CONTROL_PATH', 'controlPath')]:
        value = manifest.get(field, '')
        if value:
            prefix.append(f"$env:{name}='" + value.replace("'", "''") + "';")
    if manifest.get('workspaceRoot'):
        prefix.append('Set-Location -LiteralPath $env:DEVBOX_WSROOT;')
    command = ''.join(prefix) + command
    encoded = base64.b64encode(command.encode('utf-16le')).decode('ascii')
    client = connect(manifest, password)
    try:
        channel = client.get_transport().open_session(timeout=15)
        channel.exec_command('powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand ' + encoded)
        deadline = time.monotonic() + timeout if timeout > 0 else None
        while True:
            while channel.recv_ready():
                sys.stdout.write(channel.recv(32768).decode('utf-8', errors='replace'))
                sys.stdout.flush()
            while channel.recv_stderr_ready():
                sys.stderr.write(channel.recv_stderr(32768).decode('utf-8', errors='replace'))
                sys.stderr.flush()
            if channel.exit_status_ready() and not channel.recv_ready() and not channel.recv_stderr_ready():
                return channel.recv_exit_status()
            if deadline is not None and time.monotonic() >= deadline:
                raise TimeoutError('Command exceeded the client wait limit; remote process status is unknown')
            time.sleep(0.05)
    finally:
        client.close()


def main():
    parser = argparse.ArgumentParser(description='Run Windows PowerShell over the existing tailnet')
    parser.add_argument('--state', default='/run/devbox-control')
    parser.add_argument('--timeout', type=int, default=300, help='Command wait in seconds; 0 waits without a client deadline')
    parser.add_argument('command', nargs='?')
    args = parser.parse_args()
    state = Path(args.state)
    manifest = json.loads((state / 'manifest.json').read_text(encoding='utf-8-sig'))
    password = (state / 'password').read_text(encoding='utf-8')
    if args.command is not None:
        return execute(manifest, password, args.command, args.timeout)
    print('Windows command console. Each command opens a fresh PowerShell process. Type exit to leave.')
    while True:
        try:
            command = input('DevBox PS> ')
        except (EOFError, KeyboardInterrupt):
            print()
            return 0
        if command.strip().lower() == 'exit':
            return 0
        if command.strip():
            try:
                result = execute(manifest, password, command, args.timeout)
                print(f'[exit {result}]')
            except Exception as exc:
                print(f'Command failed: {type(exc).__name__}: {exc}', file=sys.stderr)


if __name__ == '__main__':
    sys.exit(main())
