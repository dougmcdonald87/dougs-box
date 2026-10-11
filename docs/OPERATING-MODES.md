# OPERATING-MODES.md

The DevBox must not pretend the world is simpler than the platform terms. Three
legitimate modes; pick yours honestly before the first run.

## A. OSS_ZERO_COST

For a genuine non-commercial open-source project:

- public GitHub repository; standard public Windows runner (currently 4 vCPU/16 GB).
- prefer a GitHub organisation for the eventual Tailscale Community on GitHub application.
- OSI-approved licence recommended for the Community plan route.
- Tailscale Personal is fine in this mode because personal open-source tinkering is
  non-commercial. If the activity becomes a company's work, this mode no longer applies.

## B. PERSONAL_LEARNING

- non-commercial home development/learning.
- Tailscale Personal remains the plan.

## C. COMMERCIAL_PRIVATE

- proprietary source stays private.
- Do NOT publish at no cost just to claim the 16 GB runner.
- Do NOT call Tailscale Personal a commercial plan.
- Private-run usage is metered against plan allowances; a strictly £0 strategy is
  not guaranteed under current terms. The DevBox still runs; the honest accounting
  belongs to the owner.

## The hard mode boundary

Never use a public shell repository to pull unrelated proprietary code for free
compute. That is a terms violation, not a design. `config/devbox.json`
`operating_mode` records the chosen mode and the validate workflow greps only
against secrets - the owner's honesty is the enforcement of this page.
