# DevBox Universal Continuity Kit v2
**Read this first.** This is a portable, PUBLIC-SAFE, self-contained handoff archive for ChatGPT chat/Work, OpenCode V2 CLI, and other coding agents. It is NOT a deployed DevBox, a credential bundle, or proof of persistent Windows recovery.

## Five-minute start
1. Download this branch as a ZIP; extract to a working directory. Do not merge this documentation-only branch into main or pilot: its Git tree intentionally contains only the kit.
2. In ChatGPT chat or Work: upload the ZIP, ask the agent to read AGENTS.md and prompts/CHATGPT_RESUME.md, and authorize specific connected apps as needed. Uploading a ZIP does not automatically connect apps or computers.
3. In OpenCode V2: open the extracted directory as the workspace, read AGENTS.md, load the devbox-continuity skill from .opencode/skills, and use prompts/OPENCODE_RESUME.md. Use a separate checkout of the real source repo for code edits.
4. Configure Remote Desktop Commander only when required. See references/CONNECT.md and examples/opencode.v2.jsonc. Complete OAuth separately per client.
5. Before any action: refresh live GitHub branch SHA, Actions status, Desktop Commander device list and target identity. Never start a new runner to learn what an old runner did.

## Truth order
Live read-only observation (GitHub Actions/API or authenticated machine) > immutable commit/run logs > checked-in docs > local event ledger > old ZIP/checkpoint > chat memory. Conflicts are BLOCKERS, not invitations to guess.

## What is included
- AGENTS.md: compact universal instructions.
- .opencode/skills/devbox-continuity/SKILL.md: OpenCode V2-compatible skill.
- references/: machine identity, connections, safety, anti-loop rules, specialist skill routing, acceptance plan.
- state/: historical evidence snapshot, schema and decisions; not a live control plane.
- scripts/continuity.py: offline-first event recording and preflight; standard library only.
- tests/: unit tests for the ledger, to run locally after extraction.
- examples/: optional V2 MCP/permissions configuration; never overwrite an existing config without review.
- prompts/: precise handoffs for both clients.

## Verification status
The files were authored from GitHub and official OpenCode V2 / Desktop Commander documentation on 2026-10-18. This archive does NOT contain the prior private CP155 ZIP and does NOT claim to have inspected it. Offline Desktop Commander devices prevented a live machine check. Python tests are supplied, but were not executed by the packaging environment; run them before trusting the script.

## Start commands
From the extracted kit root:
    python -m unittest discover -s tests -v
    python scripts/continuity.py doctor
    python scripts/continuity.py last

To log a verified step from an extracted, non-Git checkout (NOT a live acceptance):
    python scripts/continuity.py checkpoint --target pilot --offline --summary "Read-only inventory" --evidence "https://github.com/dougmcdonald87/dougs-box/actions" --next "Reconcile live run status"

Never treat a locally logged event as a published or verified Windows backup. Read references/ACCEPTANCE.md for actual success gates.

## Sources
- Pilot repo: https://github.com/dougmcdonald87/dougs-box
- OpenCode V2 instructions: https://dev.opencode.ai/v2/docs/instructions/
- OpenCode V2 skills: https://dev.opencode.ai/v2/docs/skills/
- OpenCode V2 MCP: https://dev.opencode.ai/v2/docs/mcp-servers/
- OpenCode V2 permissions: https://dev.opencode.ai/v2/docs/permissions/
- Desktop Commander Remote: https://github.com/desktop-commander/remote-desktop-commander

**Security:** The GitHub repository hosting this archive is PUBLIC. Never put private machine identifiers, account tokens, recovery material, credential files, customer data or private CP155 attachments into this branch or its ZIP.
