# DevBox GitHub-to-Tailscale OIDC incident — 2026-10-11

## Reproducible evidence (not inferred from green static gates)

- Run 38144750809 at commit `75c2cad`: GitHub Windows runner and workspace bootstrap succeeded. Tailscale Action failed installing `version: stable`, requesting an invalid URL ending `tailscale-setup-stable-amd64.msi.sha256`; HTTP 404. That issue was corrected by `version: latest`.
- Run 38145211461 at commit `e5fc71e`: Tailscale 1.104.1 installed, then all five `tailscale up` attempts failed with `failed to exchange JWT for access token: token exchange failed with status 404: {"message":"not found"}`. This does **not** reveal which credential field was wrong.
- Run 38147647088 at commit `473cf71`, GitHub Windows job 114494418385: `Bootstrap` PASS; `Check GitHub OIDC claims before Tailscale` FAIL at line 24: `TS_AUDIENCE value is not api.tailscale.com/ followed by TS_OAUTH_CLIENT_ID`. The Tailscale step was SKIPPED; that run **did not** test JWT exchange. The failure empirically demonstrates that the GitHub Environment secret pair was internally inconsistent.
- Screenshot from the Tailscale Trust credentials page showed a single existing credential `doug dev box`, type OIDC, with `auth_keys`, `tag:github-devbox`, generated Client ID and Audience, and subject `repo:dougmcdonald87@220090710/dougs-box@1414179011:environment:devbox`.

## Primary source

Tailscale's Workload Identity Federation documentation explicitly gives the generated audience format `api.tailscale.com/<full client ID>`:
https://tailscale.com/docs/features/workload-identity-federation

Tailscale's GitHub Actions documentation uses `oauth-client-id`, `audience`, `tags`, and `permissions: id-token: write`:
https://tailscale.com/docs/integrations/github/github-action

## Applied change

Commit `d77502dac786318f0e347d713d7b40330970f303` on `main` replaces `secrets.TS_OAUTH_CLIENT_ID` and `secrets.TS_AUDIENCE` references in the OIDC diagnostic and Tailscale join with **one explicitly identified existing non-secret Client ID from the user-provided Tailscale screenshot**. The corresponding audience is derived directly using GitHub Actions `format('api.tailscale.com/{0}', env.DEVBOX_OIDC_CLIENT_ID)`, so the pair cannot silently diverge in GitHub secret settings. All other GitHub DevBox secrets, Lenovo device tags, tailnet policy, existing file shares, OpenCode and RustDesk services are left untouched by this code-only patch.

Ten code-level inspections after commit confirmed both workflow consumer steps refer to the same client ID, both derive the same audience, neither refers to the two old OIDC secrets, and existing storage wiring remains in place. **Code inspection is not a live integration test.**

## Prove Me Wrong adversarial check

- **Claim:** The pair-mismatch blocker in run 38147647088 has been removed.
- **Smallest falsifier:** The revised workflow still reads one of the old secret values or derives its Audience from a different Client ID.
- **Strongest competitor:** The OIDC client identity from the screenshot was transcribed incorrectly, or Tailscale rejects the issuer / subject / workflow claim for reasons unrelated to this pair mismatch.
- **Cheapest safe attack:** Fetch the committed workflow from `main` and verify the four consumer references and both obsolete secret references. That check passed. A subsequent manually dispatched live workflow is required to discriminate the remaining competitors.

**Verdict:** Code-level pair mismatch correction SURVIVED static inspection; overall Tailscale authentication UNVERIFIED. Do not claim the DevBox is up until a live `tailscale up`, storage handshake, backup canary verification and RDP connection pass.

No Tailscale admin changes, credentials recreated, existing laptop reconfiguration or service restart were performed to apply this patch.
