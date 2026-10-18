---
name: devbox-continuity
description: Use when resuming, handing off, connecting to, debugging or safely advancing the old or pilot DevBox across ChatGPT, GitHub, OpenCode V2 and Desktop Commander. Do NOT use for unrelated coding or generic machine administration.
license: MIT
compatibility: opencode
metadata:
  audience: devbox-operators
  opencode/slash: "true"
---
# DevBox continuity skill

## Operating contract
Read the root AGENTS.md first. Load only the reference relevant to the current action; do not dump the entire repository into context. This skill coordinates agents; it does not grant tool access or authorization.

## Triage
1. Read state/CURRENT.json. Treat it as an as-of snapshot, never proof of current status.
2. Read references/MACHINE_REGISTRY.md to select original, pilot, outer host, guest or personal machine.
3. Read references/CONNECT.md if access is needed. Use GitHub for source/run facts; Desktop Commander only for a currently online, independently verified device.
4. Produce a compact identity card and reconcile conflicts. If no verified live target, stop at read-only planning.
5. Read references/ACCEPTANCE.md for the single next proof gate. Consult references/ANTI_LOOP.md if repeated failures, unexpected state or high cost.
6. Route to relevant installed specialist skills using references/SKILL_ROUTER.md. Do not pretend the other platform's plugins are available.
7. Record a durable local event and end with a reproducible handoff. Refer to scripts/continuity.py.

## Hard completion conditions
- No mutation of original main or personal backup drives without specific approval.
- No duplicate workflow dispatch while a relevant run is active or unresolved.
- No expensive test without preflight, estimated cost/usage and authorization.
- No unverified success language. Link evidence for every claimed result.
- A failed theory gets one cheapest safe falsifier before broad rewrites.
- A newly created local checkpoint is not a new Windows backup or CP156.
