# Setup — installing this Claude Code configuration

This config is **stack-agnostic and OS-agnostic**. The files are identical on every platform — only the install **paths and shell** differ. This guide covers **Windows (PowerShell)** and **Ubuntu/Linux (bash)**.

## What goes where

| Piece | Scope | Location | Why |
|------|-------|----------|-----|
| `base` plugin — 23 agents + `/caveman` skill | **Plugin** | via `/plugin` | The main team — install from the marketplace (see §G) |
| Addons: `marketing` (7), `council` (6) | **Plugin** | via `/plugin` | Opt-in add-ons — install from the marketplace (see §G) |
| `settings.json` (deny-list + modes) | **Global / user** | `~/.claude/settings.json` | The security baseline — **not** plugin-able; install it before the plugins |
| Hooks `guard`/`format`/`verify` (`.ps1`+`.sh`, optional) | **Global / user** | `~/.claude/hooks/` | guard = enforce no-secret-read/egress + safe agent-gen; format = auto-format edited file; verify = run project checks before finishing |
| `managed-settings.json` (optional) | **Machine policy** | OS policy dir (see §E) | Unbreakable: locks bypass-disable + crown-jewel secret denies |
| `CLAUDE.md` | **Per project** | `<project>/CLAUDE.md` | Project description, package map, conventions |
| `templates/CLAUDE.package.md` | **Per package** | `<project>/<area>/CLAUDE.md` | On-demand stack commands for each subsystem |
| `.gitignore` | **Per project** | `<project>/.gitignore` | Keep secrets & local Claude state out of git |

> `settings.json` is **the same file** on Windows and Linux — the path globs are forward-slash and cross-platform, and the Windows-only Bash denies (e.g. `Invoke-WebRequest`) simply never match on Linux. Copy it as-is on either OS.

Replace `<repo>` below with the path where this config repo lives on the machine you're installing on.

> **Install in two parts:** (1) the **security baseline** — `settings.json` (+ optional hooks and managed policy) — installs the classic way below (§A/§B, §E); it is *not* plugin-able. (2) the **agent team** — `base` plus the optional `marketing`/`council` addons — installs from the **plugin marketplace** (§G), or by a **manual copy** into `~/.claude/` if you'd rather not use plugins (§H).

---

## A. Windows (PowerShell) — security baseline + hooks

```powershell
# --- paths ---
$repo = "D:\Github\claude-md\claude md"      # this config repo
$dest = "$env:USERPROFILE\.claude"

# 1. Hooks directory
New-Item -ItemType Directory -Force "$dest\hooks" | Out-Null

# 2. Install the security baseline at USER scope (covers every project)
Copy-Item "$repo\.claude\settings.json" "$dest\settings.json" -Force
#   If you already have ~/.claude/settings.json, merge the "permissions" block by hand.

# 3. (Optional) Install the hooks: guard (security) + format/verify (convenience)
Copy-Item "$repo\.claude\hooks\*.ps1" "$dest\hooks\" -Force

# The agents + /caveman skill are NOT copied here — they install as the `base` plugin (see §G).
```

Then, **only if you installed the hook**, add this to `~/.claude/settings.json` next to `permissions`:

```json
"hooks": {
  "PreToolUse": [
    { "matcher": "Bash|Write|Edit", "hooks": [ { "type": "command", "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<you>\\.claude\\hooks\\guard.ps1\"" } ] }
  ],
  "PostToolUse": [
    { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<you>\\.claude\\hooks\\format.ps1\"" } ] }
  ],
  "Stop": [
    { "hooks": [ { "type": "command", "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<you>\\.claude\\hooks\\verify.ps1\"" } ] }
  ]
}
```
> Adjust the path if your home directory differs (`$env:USERPROFILE`). Install only the hooks you want — `guard` (security) is the recommended one; `format`/`verify` are convenience. **Trust note:** `format` auto-runs the project's local formatter binaries and `verify` auto-runs the project's `.claude\checks.cmd`, so enable them only on repos you trust. **`verify` is allowlist-gated:** it runs a project's `.claude\checks.cmd` only when that project's path is also listed in `%USERPROFILE%\.claude\verify-allowed.txt`, so a cloned repo can't auto-run code. Enable a trusted project with `Add-Content "$env:USERPROFILE\.claude\verify-allowed.txt" "<project path>"`, then create `.claude\checks.cmd`.

**Verify (PowerShell):**
```powershell
Get-Content "$env:USERPROFILE\.claude\settings.json" -Raw | ConvertFrom-Json | Out-Null; "settings OK"
# then inside Claude Code (after installing the base plugin — see §G):
#   /plugin   -> shows installed plugins (base / marketing / council)
#   /agents   -> lists the base team (23) plus any addon plugins, with tools + model
#   /memory   -> shows which CLAUDE.md files are loaded
```

---

## B. Ubuntu / Linux (bash) — security baseline + hooks

The hook port (`guard.sh`) needs **jq**:
```bash
sudo apt-get update && sudo apt-get install -y jq
```

```bash
# --- paths ---
REPO="$HOME/claude-md"          # path where you cloned this config repo
DEST="$HOME/.claude"

# 1. Hooks directory
mkdir -p "$DEST/hooks"

# 2. Install the security baseline at USER scope (covers every project)
cp "$REPO/.claude/settings.json" "$DEST/settings.json"
#   If you already have ~/.claude/settings.json, merge the "permissions" block by hand.

# 3. (Optional) Install the hooks: guard (security) + format/verify (convenience)
cp "$REPO"/.claude/hooks/*.sh "$DEST/hooks/"
chmod +x "$DEST"/hooks/*.sh

# The agents + /caveman skill are NOT copied here — they install as the `base` plugin (see §G).
```

Then, **only if you installed the hook**, add this to `~/.claude/settings.json` next to `permissions`:

```json
"hooks": {
  "PreToolUse": [
    { "matcher": "Bash|Write|Edit", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/guard.sh" } ] }
  ],
  "PostToolUse": [
    { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/format.sh" } ] }
  ],
  "Stop": [
    { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/verify.sh" } ] }
  ]
}
```
> If your Claude Code build doesn't expand `$HOME` in hook commands, use the absolute path (e.g. `/home/<you>/.claude/hooks/guard.sh`). Install only the hooks you want — `guard` is the recommended security one. **Trust note:** `format` auto-runs the project's local formatter binaries and `verify` auto-runs the project's executable `.claude/checks.sh`, so enable them only on repos you trust. **`verify` is allowlist-gated:** it runs a project's executable `.claude/checks.sh` only when that project's path is listed in `~/.claude/verify-allowed.txt`, so a cloned repo can't auto-run code. Enable a trusted project with `echo "/path/to/project" >> ~/.claude/verify-allowed.txt`, then create the executable `.claude/checks.sh`.

**Verify (bash):**
```bash
jq . "$HOME/.claude/settings.json" >/dev/null && echo "settings OK"
# then inside Claude Code (after installing the base plugin — see §G):
#   /plugin   -> shows installed plugins (base / marketing / council)
#   /agents   -> lists the base team (23) plus any addon plugins, with tools + model
#   /memory   -> shows which CLAUDE.md files are loaded
```

---

## C. Per project (same on both OSes)

From inside each project root:

**Windows** (run in PowerShell — not cmd — from your project root)
```powershell
$repo = "D:\Github\claude-md\claude md"     # the config repo; RE-SET this in each new terminal
Copy-Item "$repo\CLAUDE.md" ".\CLAUDE.md"
# Per package/area — repeat for each REAL subsystem folder (create it first if needed):
New-Item -ItemType Directory -Force ".\apps\web" | Out-Null
Copy-Item "$repo\templates\CLAUDE.package.md" ".\apps\web\CLAUDE.md"
Copy-Item "$repo\.gitignore" ".\.gitignore"                            # skip/merge if one already exists
```

**Ubuntu** (run from your project root)
```bash
REPO="$HOME/claude-md"          # the config repo; RE-SET this in each new shell
cp "$REPO/CLAUDE.md" ./CLAUDE.md
# Per package/area — repeat for each REAL subsystem folder (create it first if needed):
mkdir -p ./apps/web
cp "$REPO/templates/CLAUDE.package.md" ./apps/web/CLAUDE.md
cp "$REPO/.gitignore" ./.gitignore                            # skip/merge if one already exists
```

Then fill in `<APP_NAME>`, the repo/package map, and each area's `install / test / lint / build / run` commands.

**First run in a project (both OSes):**
```text
claude --permission-mode plan
> Use project-analyst to detect the stack, then team-configurator to write the
> AI Team Configuration table into CLAUDE.md.
```
Review the proposed table — and anything under **"Generated agents — review before enabling"** — before approving.

---

## D. Personal overrides & trimming

- `~/.claude/settings.local.json` (or `<project>/.claude/settings.local.json`) is **auto-gitignored** and merges over `settings.json`. Use it for personal, per-machine or per-project tweaks — e.g. re-allow a safe command in one project:
  ```json
  { "permissions": { "allow": ["Bash(curl http://localhost:*)", "Read(vendor/**)"] } }
  ```
  (`vendor/` is build output in Node/Composer but readable source in Go — re-allow it per project if needed.)
- Skip packages you never work in, in any settings layer:
  ```json
  { "claudeMdExcludes": ["**/legacy-vendor/**", "packages/experiments/**"] }
  ```

---

## E. (Optional) Unbreakable enforcement — managed policy

The user-scope `settings.json` can be edited or removed by you (or, in a worst case, by a prompt-injected agent that gets a write approved). For protection that **cannot be overridden by any user/project/local setting or even a CLI flag**, install the managed-policy file. It is the **highest** tier in Claude Code's settings hierarchy.

It locks only the non-negotiables — `disableBypassPermissionsMode` + `disableAutoMode` and a core of crown-jewel secret denies (`.env`, private keys, SSH/cloud/DB creds, `*.tfstate`/`*.tfvars`). The flexible parts (build-dir noise, `.env.*`, the Bash speed-bumps) stay in user scope where you can still tune them per project.

The master copy is `managed/managed-settings.json` in this repo. Installing it writes to an OS policy directory, which requires **admin/root** — that's the point: you can't casually remove it.

**Windows (run PowerShell as Administrator):**
```powershell
$dir = "C:\Program Files\ClaudeCode"
New-Item -ItemType Directory -Force $dir | Out-Null
Copy-Item "$repo\managed\managed-settings.json" "$dir\managed-settings.json" -Force
```

**Ubuntu / Linux (sudo):**
```bash
sudo mkdir -p /etc/claude-code
sudo cp "$REPO/managed/managed-settings.json" /etc/claude-code/managed-settings.json
```

**macOS (sudo):**
```bash
sudo mkdir -p "/Library/Application Support/ClaudeCode"
sudo cp "$REPO/managed/managed-settings.json" "/Library/Application Support/ClaudeCode/managed-settings.json"
```

> Keep the managed file minimal (dangerous-mode disable + crown-jewel secret reads) so per-project flexibility still lives in the user/local layers. Do **not** set `allowManagedPermissionRulesOnly` unless you want the managed deny-list to be the *only* permission rules in effect (it would disable your user-scope deny-list and per-project `allow` rules). To remove the policy later, delete the file from the OS dir with the same admin/root rights.

---

## F. Notes & residual risks

- **Start in Plan mode.** `settings.json` sets `defaultMode: "plan"` and `disableBypassPermissionsMode: "disable"`. Never launch with `--dangerously-skip-permissions`.
- **The `Read` deny-list does not cover shell reads or network egress.** The `Bash(...)` denies are a *speed-bump* (evadable via `.exe`/wrappers/aliases). Real enforcement = plan-mode + per-command approval + no agent has network tools + the optional hook.
- **Unbreakable enforcement** of bypass-disable + core secret denies is the managed policy in §E (highest tier, admin-owned, cannot be overridden).
- **The optional `format`/`verify` hooks run outside the permission system** — plan-mode, the deny-list, and bypass-disable do not constrain hook-spawned processes. `verify` only runs a project's checks when that project's path is on your `~/.claude/verify-allowed.txt` allowlist (so a cloned repo can't auto-run code); `format` runs only formatters already installed in the project. Enable both only on repos you trust. `guard` is the only hook that hardens posture and is safe on any repo.
- Every file is identical across Windows/macOS/Linux — only paths and the hook script (`guard.ps1` vs `guard.sh`) differ.

---

## G. Install the team — plugin marketplace (base + addons)

The agent team ships as Claude Code **plugins**, listed in `.claude-plugin/marketplace.json`: install **`base`** (the main 23-agent team + `/caveman`), then add the **`marketing`** and **`council`** addons per project as needed. Nothing under `plugins/` loads until you install it. Same flow on every OS:

```text
# 1. add this repo as a plugin marketplace (local path works; or <owner>/claude-md once it's pushed to GitHub)
/plugin marketplace add <path-to-this-repo>

# 2. install the base team, then whichever addons you want — toggle any of them anytime from /plugin
/plugin install base@claude-md-packs         # MAIN: 23 engineering agents + the /caveman skill
/plugin install marketing@claude-md-packs    # addon: 7 marketing/content agents + Tavily/DataForSEO researchers
/plugin install council@claude-md-packs      # addon: 6 council seats + the /council skill
```

- **`base`** is the main install — the 23 zero-network engineering agents plus the `/caveman` skill. Pair it with the `settings.json` security baseline (§A/§B), which is required and is not part of any plugin.
- **`marketing`** adds the 7 marketing/content agents. Two are network-enabled (`content-researcher` via Tavily, `seo-rank-monitor` via DataForSEO). Their MCP servers are declared at **plugin scope** in `plugins/marketing/.mcp.json`, because per-subagent inline `mcpServers` is ignored inside a plugin. Set `TAVILY_API_KEY` / `DATAFORSEO_USERNAME` / `DATAFORSEO_PASSWORD` in your environment first, then run `/mcp` to confirm the servers connect and the exact tool names. Full security model: [`council-and-network-config.md`](council-and-network-config.md). If your build doesn't pick up the plugin-scope `.mcp.json`, move those two servers into your global `~/.claude.json` instead.
- **`council`** adds the 6 reasoning seats and the `/council` skill — pure reasoners, no network, no scripts.
- Both packs are **agents/skills only — no hooks** — so they keep the core's least-privilege posture. Disable or remove a pack anytime from `/plugin` (or `/plugin marketplace remove`).

---

## H. Manual install (no plugins)

Prefer not to use the plugin system? The agents and skills are plain files — copy them straight into `~/.claude/` and skip plugins entirely. The `settings.json` security baseline (§A/§B) still applies either way. Replace `<repo>` with this config repo's path.

**Windows (PowerShell)**
```powershell
$repo = "<repo>"; $dest = "$env:USERPROFILE\.claude"
New-Item -ItemType Directory -Force "$dest\agents","$dest\skills" | Out-Null
Copy-Item "$repo\plugins\*\agents\*.md"          "$dest\agents\" -Force            # all 36 (use \base\ for just the 23)
Copy-Item "$repo\plugins\base\skills\caveman"    "$dest\skills\caveman"  -Recurse -Force
Copy-Item "$repo\plugins\council\skills\council" "$dest\skills\council"  -Recurse -Force
```

**Ubuntu / macOS (bash)**
```bash
repo="<repo>"; dest="$HOME/.claude"
mkdir -p "$dest/agents" "$dest/skills"
cp "$repo"/plugins/*/agents/*.md "$dest/agents/"                  # all 36 (use plugins/base/ for just the 23)
cp -r "$repo/plugins/base/skills/caveman"    "$dest/skills/caveman"
cp -r "$repo/plugins/council/skills/council" "$dest/skills/council"
```

- For just the base team, copy from `plugins/base/agents/` instead of `plugins/*/agents/`.
- The two `marketing` network agents keep their inline `mcpServers` blocks, so they work in a manual install once `TAVILY_API_KEY` / `DATAFORSEO_USERNAME` / `DATAFORSEO_PASSWORD` are set — inline MCP is ignored only *inside* a plugin. Verify with `/mcp`.
- No marketplace step is needed: the copied agents show up in `/agents` immediately.
