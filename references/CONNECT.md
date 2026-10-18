# Connection runbook — ChatGPT, Work, OpenCode V2, GitHub, Desktop Commander

## Connection order
A. GitHub first: inspect repository branch, current commit, workflow runs and job status with read-only GitHub connector/API. A GitHub repository is not an online Windows machine.
B. Desktop Commander second, only if the task needs filesystem or shell on an online device: list_devices -> choose current device ID -> ping -> hostname/OS -> check target role -> only then request any write.
C. Tailscale/RDP third, only for an already authorized active pilot runner: obtain private IP from its current verified logs, never use a stale IP; confirm outer-host RDP vs actual guest GUI separately.

## ChatGPT online chat / Work
Use the connected GitHub and Remote Desktop Commander apps in the current chat or Work session. Connected tools and approvals are account/session-specific; a ZIP cannot transfer OAuth credentials. If a connector is missing, ask the user to connect it, or remain read-only with public GitHub evidence. Do not claim Work can reach an offline machine.

## OpenCode V2 CLI
OpenCode V2 MCP config lives under mcp.servers, not legacy mcp.<server>. Preferred CLI:
    opencode mcp add remote-desktop-commander --url https://mcp.desktopcommander.app/mcp
    opencode mcp list
    opencode mcp auth remote-desktop-commander
When prompted, complete OAuth in browser. Verify connected state. Example in examples/opencode.v2.jsonc is for manual merge, not replacement of an existing config.
Skill location: .opencode/skills/devbox-continuity/SKILL.md. Project root AGENTS.md is automatically discovered in V2.
GitHub connector access in ChatGPT does NOT carry to OpenCode. Use a separately configured and least-privilege GitHub integration or an authenticated gh CLI; never paste a token into the kit.

## If no devices are online
Do not retry remote shell. Have the owner start the Remote Desktop Commander agent on the correct personal computer using the official dashboard instructions. A current supported launch command is:
    npx @wonderwhy-er/desktop-commander@latest remote
Then list devices again and verify identity. Never auto-install a remote agent on an unidentified machine.

## Official references
https://dev.opencode.ai/v2/docs/mcp-servers/
https://dev.opencode.ai/v2/docs/instructions/
https://dev.opencode.ai/v2/docs/skills/
https://github.com/desktop-commander/remote-desktop-commander
https://github.com/desktop-commander/remote-desktop-commander/blob/main/docs/SETUP.md
