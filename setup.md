# Setup — installing this Claude Code configuration

This config is **stack-agnostic and OS-agnostic**. The files are identical on every platform — only the install **paths and shell** differ. This guide covers **Windows (PowerShell)** and **Ubuntu/Linux (bash)**.

## What goes where

| Piece | Scope | Location | Why |
|------|-------|----------|-----|
| 16 agents (`.claude/agents/*.md`) | **Global / user** | `~/.claude/agents/` | Reused across every project |
| `settings.json` (deny-list + modes) | **Global / user** | `~/.claude/settings.json` | The secret/egress protection must travel with the global agents |
| `guard.ps1` / `guard.sh` (optional hook) | **Global / user** | `~/.claude/hooks/` | Mechanical enforcement of the Bash + agent-generation rules |
| `managed-settings.json` (optional) | **Machine policy** | OS policy dir (see §E) | Unbreakable: locks bypass-disable + crown-jewel secret denies |
| `CLAUDE.md` | **Per project** | `<project>/CLAUDE.md` | Project description, package map, conventions |
| `templates/CLAUDE.package.md` | **Per package** | `<project>/<area>/CLAUDE.md` | On-demand stack commands for each subsystem |
| `.gitignore` | **Per project** | `<project>/.gitignore` | Keep secrets & local Claude state out of git |

> `settings.json` is **the same file** on Windows and Linux — the path globs are forward-slash and cross-platform, and the Windows-only Bash denies (e.g. `Invoke-WebRequest`) simply never match on Linux. Copy it as-is on either OS.

Replace `<repo>` below with the path where this config repo lives on the machine you're installing on.

---

## A. Windows (PowerShell)

```powershell
# --- paths ---
$repo = "D:\Github\claude-md\claude md"      # this config repo
$dest = "$env:USERPROFILE\.claude"

# 1. Global directories
New-Item -ItemType Directory -Force "$dest\agents", "$dest\hooks" | Out-Null

# 2. Install the 16 agents globally (reused everywhere)
Copy-Item "$repo\.claude\agents\*.md" "$dest\agents\" -Force

# 3. Install the security baseline at USER scope (covers every project)
Copy-Item "$repo\.claude\settings.json" "$dest\settings.json" -Force
#   If you already have ~/.claude/settings.json, merge the "permissions" block by hand.

# 4. (Optional) Install the enforcement hook
Copy-Item "$repo\.claude\hooks\guard.ps1" "$dest\hooks\guard.ps1" -Force
```

Then, **only if you installed the hook**, add this to `~/.claude/settings.json` next to `permissions`:

```json
"hooks": {
  "PreToolUse": [
    {
      "matcher": "Bash|Write|Edit",
      "hooks": [
        { "type": "command", "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\RV\\.claude\\hooks\\guard.ps1\"" }
      ]
    }
  ]
}
```
> Adjust the path if your home directory differs (`$env:USERPROFILE`).

**Verify (PowerShell):**
```powershell
Get-Content "$env:USERPROFILE\.claude\settings.json" -Raw | ConvertFrom-Json | Out-Null; "settings OK"
# then inside Claude Code:
#   /agents   -> lists all 16 agents with tools + model
#   /memory   -> shows which CLAUDE.md files are loaded
```

---

## B. Ubuntu / Linux (bash)

The hook port (`guard.sh`) needs **jq**:
```bash
sudo apt-get update && sudo apt-get install -y jq
```

```bash
# --- paths ---
REPO="$HOME/claude-md"          # path where you cloned this config repo
DEST="$HOME/.claude"

# 1. Global directories
mkdir -p "$DEST/agents" "$DEST/hooks"

# 2. Install the 16 agents globally (reused everywhere)
cp "$REPO"/.claude/agents/*.md "$DEST/agents/"

# 3. Install the security baseline at USER scope (covers every project)
cp "$REPO/.claude/settings.json" "$DEST/settings.json"
#   If you already have ~/.claude/settings.json, merge the "permissions" block by hand.

# 4. (Optional) Install the enforcement hook
cp "$REPO/.claude/hooks/guard.sh" "$DEST/hooks/guard.sh"
chmod +x "$DEST/hooks/guard.sh"
```

Then, **only if you installed the hook**, add this to `~/.claude/settings.json` next to `permissions`:

```json
"hooks": {
  "PreToolUse": [
    {
      "matcher": "Bash|Write|Edit",
      "hooks": [
        { "type": "command", "command": "$HOME/.claude/hooks/guard.sh" }
      ]
    }
  ]
}
```
> If your Claude Code build doesn't expand `$HOME` in hook commands, use the absolute path (e.g. `/home/<you>/.claude/hooks/guard.sh`).

**Verify (bash):**
```bash
jq . "$HOME/.claude/settings.json" >/dev/null && echo "settings OK"
ls "$HOME/.claude/agents" | wc -l        # expect 16
# then inside Claude Code:
#   /agents   -> lists all 16 agents with tools + model
#   /memory   -> shows which CLAUDE.md files are loaded
```

---

## C. Per project (same on both OSes)

From inside each project root:

**Windows**
```powershell
Copy-Item "$repo\CLAUDE.md" ".\CLAUDE.md"
Copy-Item "$repo\templates\CLAUDE.package.md" ".\apps\web\CLAUDE.md"   # repeat per package/area
Copy-Item "$repo\.gitignore" ".\.gitignore"                            # or merge into an existing one
```

**Ubuntu**
```bash
cp "$REPO/CLAUDE.md" ./CLAUDE.md
cp "$REPO/templates/CLAUDE.package.md" ./apps/web/CLAUDE.md   # repeat per package/area
cp "$REPO/.gitignore" ./.gitignore                            # or merge into an existing one
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
- Every file is identical across Windows/macOS/Linux — only paths and the hook script (`guard.ps1` vs `guard.sh`) differ.
