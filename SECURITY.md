# SECURITY.md

## Trust boundary

Tailscale is the ONLY added network-security layer on every device in this
architecture. Additions such as a TLS wrapper, a reverse proxy, a second VPN
product, or authentication middleware around rest-server are outside the design
and fail the audit workflow.

Application-level credentials that remain by necessity: native Windows login for
RDP and the restic repository password. Neither is a replacement network product.

## Where secrets live

| Secret value | Lives at | Never in |
|---|---|---|
| RDP password (`DEVBOX_RDP_PASSWORD`) | GitHub Environment `devbox` | code, config files, logs, task state |
| restic password (`RESTIC_PASSWORD`) | GitHub Environment `devbox` | command lines, files outside run-time temp |
| Tailscale WIF ids (`TS_OAUTH_CLIENT_ID`, `TS_AUDIENCE`) | GitHub Environment `devbox` | code (IDs ok in docs as names only) |
| optional SMB trio | GitHub Environment `devbox` | anywhere else |

Runtime use: secrets stream into a per-call temp password file with a restrictive
ACL and are deleted after each restic invocation. Passwords never appear in
command arguments or logs from the DevBox side.

## Audit surface

`validate.yml` enforces on every commit:

- YAML parse on every workflow file.
- PowerShell AST parse on every script file.
- Vocabulary audit: no destructive repository command appears in any code file.
- Config secret-shape scan (leneance: name-only mentions in docs are fine).
- Action pinning: every external action at a full immutable commit SHA.

What stays manual (owner-vetoed matters): budget settings, WIF trust creation,
grants merge, storage-host setup and maintenance.

## Reporting

Security-relevant issue in the design itself: open a private message with Doug
(the owner). If this repository is ever published, add a contact to this file
that fits the reality of that publication.
