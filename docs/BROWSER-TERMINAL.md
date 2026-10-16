# Tailscale-only browser command control

Every manually started DevBox starts a Linux relay in the same workflow. The
relay is a Tailscale SSH server; Windows uses its built-in OpenSSH server. This
does not require PAM or an additional tunnel. Browser SSH is available on all
Tailscale plans, according to the official SSH Console documentation.

## One-time owner access

Before connecting, review `security/terminal-access.example.hujson`. Substitute
the exact owner identity and merge its additional entries into the existing
policy, preserving every existing rule. Do not replace the whole policy with
the fragment. A restrictive policy needs both network access on TCP 22 and the
SSH rule. An existing allow-all network grant already covers TCP 22, but its
default `autogroup:self` SSH rule does not cover the tagged relay.

The new SSH rule grants the named owner root access to Linux nodes carrying
`tag:github-devbox`; it requires Tailscale check-mode authentication. Windows
nodes do not run the Tailscale SSH server. The Linux relay's root user can run
administrative commands on Windows using the existing RDP credential. Grant
this access only after explicit approval. No account policy is changed by the
workflow or by these example files.

## Start and connect

1. Finish the previous DevBox through the existing verified Save/Finish flow.
   Do not cancel a session or start a duplicate.
2. Run `devbox.yml` from current `main`, operation `start`.
3. Wait for Windows restore and the first verified backup. Only after these
   succeed is the public terminal manifest published. The relay first proves
   a harmless Windows command, then enables Tailscale SSH and reports readiness.
4. In Tailscale Machines, select `codex-relay-<run ID>`, choose SSH, and
   connect as `root`. Follow the required Tailscale reauthentication prompt.
5. Run `devbox` for a command prompt, or use `devbox 'Get-Service Audiosrv'`.

Each command opens a fresh PowerShell process; use a complete command when
state must span several operations. This is command control, not screen viewing.
Commands needing an interactive installer or a GUI are not covered. A command
timeout closes the client; the remote process may still be running.

## Address and credential lifetime

Windows obtains its current address with `tailscale ip -4`. The relay reads a
public manifest scoped to the exact current workflow run and attempt. It pins
the host's ed25519 public key; it does not silently accept a new host key.
Neither today's IP nor a previous boot's key is hard-coded.

The relay holds the existing RDP password in a root-only file under `/run` on
the ephemeral Linux runner. It publishes no password/private key and never
sends the GitHub API token to the artifact-storage redirect. Both nodes are
ephemeral. The relay monitors the Windows job and exits when it confirms the
job ended. Transient status failures use bounded backoff; the GitHub job timeout
still limits relay lifetime. Save/Finish and periodic backup remain in the
existing Windows session manager.

## Verification boundary

Real Windows loopback tests verified rejection of a stopped listener, wrong
password, wrong key and stale address; remote commands succeeded after moving
the address and after repeating setup. Separate tests cover the restore gate
and transient status failures. These checks do not establish a successful live
Tailscale relay, browser SSH connection, or recovery across a fresh production
runner. Require a harmless browser-initiated Windows command and another safe
restart before declaring control complete.

Official sources:
- https://tailscale.com/docs/features/tailscale-ssh/tailscale-ssh-console
- https://tailscale.com/docs/features/tailscale-ssh
- https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse
- https://docs.paramiko.org/en/4.0/

The Windows desktop remains `devbox-<run ID>` (Windows). Use its own Tailscale address in Windows App. `codex-relay-<run ID>` is a separate Linux machine for browser SSH; its address is not a Windows RDP destination. Each fresh start discovers and pairs the current Windows address automatically.
