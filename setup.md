# Setup — installing this Claude configuration

This config is **stack-agnostic and OS-agnostic**. The files are identical on every platform — only the install **paths and shell** differ. This guide covers **Windows (PowerShell)** and **Ubuntu/Linux (bash)**, plus the **Claude Desktop app** and the **Claude app / claude.ai** (chat, Cowork). For the day-to-day workflow across apps, see [`WORKFLOW.md`](WORKFLOW.md).

---

## Quick start — Claude Desktop (and every other app)

Set each layer up once; every app reads the layers it can reach. The Desktop app's **Code tab** (local and SSH sessions), the CLI, VS Code and JetBrains all read the same `~/.claude`, so steps 1–6 cover every one of them.

| Layer | Steps | Reaches |
|-------|-------|---------|
| **L1 Machine** `~/.claude` | 0–6, once per machine | CLI, Desktop Code tab, VS Code, JetBrains |
| **L2 Repo** (committed) | 7, once per project | every surface, including cloud Code sessions |
| **L3 claude.ai account** | 8, once per account | chat (web, Desktop Chat tab), Cowork; synced into signed-in Claude Code |
| **L4 claude.ai Projects** | 8, one per role | chat |

**0. Get this repo onto the machine** — once per machine, before anything else. Either `git clone` it (below), or on GitHub open the repo → **Code** → **Download ZIP** and unzip it (no git needed; download again to update). The folder you end up with is **`<repo>`** in every command below. **`<owner>`** = the GitHub account or organisation that hosts *your* copy of this repo (push or fork it there first) — the marketplace commands in steps 4 and 8 and `templates/user-settings.plugins.json` point at `<owner>/claude-md`.
```powershell
git clone "https://github.com/<owner>/claude-md.git" "$env:USERPROFILE\claude-md"   # then <repo> = $env:USERPROFILE\claude-md
```
```bash
git clone "https://github.com/<owner>/claude-md.git" "$HOME/claude-md"   # then <repo> = $HOME/claude-md
```
- **Private repo?** Whether a personal claude.ai account can add a **private** repo as a plugin marketplace (step 8) is undocumented. If it fails, make the repo public — it's designed to be public-safe (no secrets, hosts or client names) — or use the skill-zip fallback in step 8. A Desktop-only machine using the `github` marketplace source (step 4, `templates/user-settings.plugins.json`) also needs git credentials for a private repo on that machine, because Claude Code clones it at session start.

Set the paths in each new terminal (`<repo>` = where you cloned or unzipped this config repo in step 0):

```powershell
$repo = "<repo>"; $dest = "$env:USERPROFILE\.claude"; New-Item -ItemType Directory -Force "$dest\hooks" | Out-Null
```
```bash
REPO="<repo>"; DEST="$HOME/.claude"; mkdir -p "$DEST/hooks"   # e.g. REPO="$HOME/claude-md"
```

**1. Security baseline → `~/.claude/settings.json`** — deny-list, ask list, `defaultMode: "plan"`, bypass disabled, `useAutoModeDuringPlan: false`. Not plugin-able (a plugin can't ship permissions), so install it first. If you already have the file, merge by hand: keep every entry of both `deny`/`ask` lists and your other keys.
```powershell
if (Test-Path "$dest\settings.json") { "settings.json exists - merge $repo\.claude\settings.json into it by hand" } else { Copy-Item "$repo\.claude\settings.json" "$dest\settings.json" }
```
```bash
if [ -e "$DEST/settings.json" ]; then echo "settings.json exists - merge $REPO/.claude/settings.json into it by hand"; else cp "$REPO/.claude/settings.json" "$DEST/settings.json"; fi
```

**2. Global memory → `~/.claude/CLAUDE.md`** — the machine-wide working agreement (`global/CLAUDE.md`). **Copy it, never symlink or hard-link it**: Cowork skips a linked `~/.claude/CLAUDE.md`. If you already have one, merge by hand. Re-copy after each update.
```powershell
if (Test-Path "$dest\CLAUDE.md") { "CLAUDE.md exists - merge $repo\global\CLAUDE.md into it by hand" } else { Copy-Item "$repo\global\CLAUDE.md" "$dest\CLAUDE.md" }
```
```bash
if [ -e "$DEST/CLAUDE.md" ]; then echo "CLAUDE.md exists - merge $REPO/global/CLAUDE.md into it by hand"; else cp "$REPO/global/CLAUDE.md" "$DEST/CLAUDE.md"; fi
```

**3. Hooks (optional; `guard` recommended)** — copy the scripts, then register them in `~/.claude/settings.json` with the JSON in §A (Windows; exec form recommended) or §B (Linux; needs `jq`). The `guard` matcher is now **`Bash|PowerShell|Monitor|Write|Edit`**: Windows' `PowerShell` tool and `Monitor` are separate from `Bash`, so a `Bash|Write|Edit` matcher misses them.
```powershell
Copy-Item "$repo\.claude\hooks\*.ps1" "$dest\hooks\" -Force
```
```bash
cp "$REPO"/.claude/hooks/*.sh "$DEST/hooks/" && chmod +x "$DEST"/hooks/*.sh
```

**4. Plugins (the agent team)** — every route lands in the same user-scope install that the CLI, Desktop Code tab and VS Code share:
- **From a terminal** (same on both OSes; the Desktop app doesn't put `claude` on your PATH — install the CLI separately):
  ```text
  claude plugin marketplace add <owner>/claude-md     # or a local clone: claude plugin marketplace add <repo>
  claude plugin install base@claude-md-packs
  claude plugin install marketing@claude-md-packs     # only where you do marketing work (see "Account plugins sync" below)
  claude plugin install council@claude-md-packs       # optional decision council
  claude plugin marketplace add anthropics/claude-plugins-official   # Anthropic's official marketplace; skip if `claude plugin marketplace list` already shows it
  claude plugin install claude-code-setup@claude-plugins-official     # Anthropic's read-only setup recommender (base's setup-advisor builds on it)
  ```
- **Desktop-only machine (no `claude` CLI):** merge the `extraKnownMarketplaces` + `enabledPlugins` keys from `templates/user-settings.plugins.json` into `~/.claude/settings.json` (replace `<owner>`; they also register Anthropic's `claude-plugins-official` marketplace and enable `claude-code-setup` from it), then check the file still parses (step 9). Claude Code clones the marketplace and installs the enabled plugins at the next session start — restart the Desktop app. **Or skip the JSON:** plugins enabled on your claude.ai account (step 8) sync into signed-in Desktop Code sessions as `<name>@synced` — verify with `/context` (or `claude plugin list` wherever the CLI is installed).
- **Desktop Code tab UI:** once the marketplace is known, **+** (next to the prompt box) → **Plugins** → **Add plugin** installs from it; **Manage plugins** enables, disables or uninstalls, at user, project or local scope. Desktop has no documented way to add a *custom* marketplace — use one of the routes above first. Not available in WSL or cloud sessions.
- **Account plugins sync everywhere (security):** a plugin enabled on your claude.ai account (step 8) also loads in **every** Claude Code session signed in with that account (v2.1.273+) as `<name>@synced` — its skills, agents, hooks **and MCP servers**. A same-name local install wins, so nothing loads twice. So `marketing` on the account means its Tavily/DataForSEO servers start in every signed-in session, not only "where you do marketing work". To turn a synced pack off on one machine, add `"marketing@synced": false` (and/or `"council@synced": false`) under `enabledPlugins` in `~/.claude/settings.json` (the template already sets the `marketing` one), or run `claude plugin disable marketing@synced`; confirm with `claude plugin list`.
- **Auto-update:** off by default for third-party marketplaces. Turn it on in `/plugin` → **Marketplaces**, or set `"autoUpdate": true` on the `claude-md-packs` entry under `extraKnownMarketplaces` (the template ships it `false`). **Trade-off:** auto-update deploys whatever is pushed to the marketplace repo — plugin hooks included — to every machine at its next start, without review. Opt in knowingly; otherwise update by hand (§I) after reading the diff.
- **`ecc` per project only** — it adds ≈15k always-on tokens to every session. From that project's root: `claude plugin install ecc@claude-md-packs --scope local` (just you) or `--scope project` (teammates too). Never user-wide, never on the claude.ai account.
- **What else to install — ask `setup-advisor`:** in a project, ask "what should I install?" or "audit my Claude setup". `base`'s `setup-advisor` skill inventories what's installed, reads the project, merges ideas from Anthropic's `claude-code-setup` (≈0.14k always-on), and proposes 3–5 additive installs from trusted sources only: the claude-md packs, Anthropic-authored plugins in `claude-plugins-official`, and your account skills. Each comes with its evidence, always-on cost and exact command. Nothing installs until you tick it in the pop-up, and it never proposes removing anything (§G).
- **Official marketplace:** Claude Code normally registers `claude-plugins-official` on its own at the first interactive terminal session; the `claude plugin` commands never do. Hence the `marketplace add` line above (or the template entry on a Desktop-only machine).

**5. Desktop environment variables** — Desktop doesn't inherit your shell exports (on macOS it reads only `PATH` and a fixed set of Claude Code variables from your profile; on Windows it doesn't read PowerShell profiles). Set the marketing researchers' keys — `TAVILY_API_KEY`, `DATAFORSEO_USERNAME`, `DATAFORSEO_PASSWORD` — in Desktop's **Local environment editor** (stored encrypted, applies to every local session). Terminal sessions keep using `setx` / `export` ([`council-and-network-config.md`](council-and-network-config.md) §2). Never put keys in a committed file.

**6. VS Code and Desktop keep Plan as the default** — the VS Code extension doesn't take its starting mode from project settings. Add this to your VS Code **user** `settings.json`:
```json
"claudeCode.initialPermissionMode": "plan"
```
In Desktop, a mode you pick in the mode selector (Manual, Accept edits, Auto) is remembered per folder and overrides `defaultMode` for that folder. Picking **Plan** applies to the current session only and doesn't clear a folder's remembered mode — so in a folder where you once picked another mode, pick Plan at the start of each session there, or leave the selector alone in folders you want to stay on Plan. How to reset a remembered pick is undocumented (verify). On Pro, Max and Team plans, decline the one-time offer to switch your default to auto mode.

**7. Per project** — once per repo; commands in §C:
- `CLAUDE.md` (root template) + per-area `CLAUDE.md` (`templates/CLAUDE.package.md`).
- `REGRESSIONS.md` (`templates/REGRESSIONS.md`) — the fix-once ledger. A fresh copy is header-only, so it starts green; example rows (incl. the data-pipeline gotchas) are in `templates/REGRESSIONS.examples.md`, which is reference-only — never copy it into a project, or grep would return inactive rows as live rules.
- `.claude/guards.sh` + `.claude/guards.ps1` (`templates/guards.sh`, `templates/guards.ps1`) — the committed guard runners; set `TEST_CMD` / `LINT_CMD` in `guards.sh` and `$TestCmd` / `$LintCmd` in `guards.ps1`.
- **Local only, trusted projects — after the first green `guards` run:** `.claude/checks.sh` / `.claude/checks.cmd` wrappers (`templates/checks.sh`, `templates/checks.cmd`; gitignored) + the project path in `~/.claude/verify-allowed.txt`, so the `verify` Stop hook runs the guards.
- Optional `.claude/rules/content.md` (`templates/rules/content.md`); content repos add `brand/banned-phrases.txt` (`templates/banned-phrases.txt`) and `brand/voice.md` (`templates/brand-voice.md`).
- CI: `.github/workflows/regression-guards.yml` (`templates/github/regression-guards.yml`) — guards on every PR/push and weekly, zero model tokens.
- `.claude/settings.json` — a copy of this repo's `.claude/settings.json` (the same baseline you installed in `~/.claude`) — single-repo cloud sessions don't read `~/.claude`, so this carries the deny-list and Plan default there. Routines have no mode picker and may stall on a Plan default: test with **Run now**, and leave `defaultMode` out of repos you run routines on if it stalls. Headless runs (`claude -p`, CI, scripts) also start in Plan and can't leave it — pass `--permission-mode acceptEdits` (or `default`) when a non-interactive run must edit files (verified in a live headless test).
- Cloud sessions skip plugins that repo settings declare (`enabledPlugins` / `extraKnownMarketplaces`): commit copies of the agents/skills a cloud session needs into `.claude/agents/` and `.claude/skills/` (§H commands, with the project's `.claude` as the destination).
- Optional `PROGRESS.md` (`templates/PROGRESS.md`) for work that spans sessions.
- Specs: `/spec` writes `specs/<slug>.md` from `templates/SPEC.md` (plugin installs carry the section list inside the command), and, for multi-session work, `specs/<slug>.features.json` from `templates/features.json`. The template runner's `no-stubs` and `spec-integrity` steps guard them; `STUB_SCAN=0` turns `no-stubs` off for one run.

**8. Claude app (chat + Cowork) — once per claude.ai account:**
- **Settings → General → "Instructions for Claude":** paste the block from `claude-ai/personal-preferences.md`. It applies to every chat, Cowork and scheduled tasks — not to Claude Code, which reads step 2's file.
- **Customize → Plugins → Add marketplace** (the **+** under Personal plugins) → `<owner>/claude-md` (private repo: see step 0). Install **`base` + `council` — not `ecc`**. Add **`marketing`** on the account only if you accept its Tavily/DataForSEO MCP servers loading in every signed-in Claude Code session (step 4, "Account plugins sync everywhere"); otherwise install `marketing` per machine or project (step 4, §G), or keep it on the account and turn `marketing@synced` off on each machine. Chat (web, Desktop Chat tab) gets skills and commands (agents and hooks are greyed out); Cowork gets everything; signed-in Claude Code syncs them as `<name>@synced`, and a same-name local install wins, so nothing loads twice. Mobile has no plugins. After a release, click **Update** on the marketplace.
- **Projects, one per role:** instructions from `claude-ai/project-marketing.md` or `claude-ai/project-generic.md`; knowledge files = `brand/voice.md`, `brand/banned-phrases.txt`, that role's `REGRESSIONS.md` and 3–5 example pieces.
- **Skill zips — fallback only** for surfaces plugins don't reach (mobile, the API, cloud Code sessions). Build validated zips with `bash scripts/package-claude-ai.sh` (Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package-claude-ai.ps1`), turn on code execution under Settings → Capabilities, then **Customize → Skills → + → Create skill → Upload a skill**. A skill you upload *and* get from a plugin is listed twice in Claude Code.

**9. Verify** — first that `settings.json` still parses (always after a hand-merge), then in the CLI, the Desktop Code tab or VS Code, then in the Claude app:

```powershell
Get-Content "$env:USERPROFILE\.claude\settings.json" -Raw | ConvertFrom-Json | Out-Null; "settings OK"
```
```bash
python3 -m json.tool "$HOME/.claude/settings.json" >/dev/null && echo "settings OK"
```

| Check | Expect |
|-------|--------|
| `settings.json` parse check (above) | `settings OK` — an error means the hand-merge broke the JSON (a missing comma or brace); fix it before starting a session |
| `/context` | **Memory files** lists `~/.claude/CLAUDE.md` (+ the project's `CLAUDE.md`); custom agents with their source; skills |
| `claude plugin list` (terminal) | `base@claude-md-packs` enabled (+ your addons, and `claude-code-setup@claude-plugins-official`); `@synced` copies show "not loaded" where a local copy exists; `marketing@synced` disabled if you turned it off |
| `claude plugin details base` | the **Always-on** token line: base ≈2.9k (marketing ≈0.86k — ≈0.7k actually in context, since the tool counts the two manual-only commands Claude never sees; council ≈0.5k, ecc ≈15.4k) |
| `/hooks` (read-only view) | `guard` / `format` / `verify` as installed, plus `base`'s `SessionStart` hook |
| `/skills` | `caveman`, `secure-code-reviewer`, `work-quality-checker`, `regression-guard`, `setup-advisor` (+ addon skills, and `claude-code-setup`'s `claude-automation-recommender`); check the "claude.ai sync" group for duplicates |
| `/mcp` (marketing only) | `tavily` / `dataforseo` connected |
| Ask "what did the SessionStart hook tell you?" | the one-line `claude-md:` working agreement |
| **Claude app** (chat, Cowork): ask "what instructions and skills do you have?" | the rules from Instructions for Claude, plus the account plugins' skills (`caveman`, `regression-guard`, `council`, …) |
| **Claude app**: **Customize → Plugins** | the `claude-md` marketplace, with the packs you installed in step 8 enabled |

`/agents` no longer lists agents (it prints a reminder) — use `/context`, the `@agent-` typeahead, or ask "list your subagents". In the Desktop Code tab, commands that open a terminal dialog may answer "isn't available in this environment"; use `/context` or ask instead. `/status` shows which settings files loaded; `/doctor` surfaces parse errors and duplicate names (verify — duplicate-name detection isn't documented).

---

## What goes where

| Piece | Scope | Location | Why |
|------|-------|----------|-----|
| `base` plugin — 25 agents + 6 skills + `/implement-plan` + `/spec` + 1 `SessionStart` hook | **Plugin** | via `/plugin`, Desktop **+ → Plugins**, or `claude plugin` | The main team — install from the marketplace (see §G) |
| Addons: `marketing` (7 agents + 2 skills + 2 commands), `council` (6 + `/council`), `ecc` (per project) | **Plugin** | via `/plugin` | Opt-in add-ons — install from the marketplace (see §G) |
| `settings.json` (deny-list + ask list + modes) | **Global / user** | `~/.claude/settings.json` | The security baseline — **not** plugin-able; install it before the plugins |
| `global/CLAUDE.md` | **Global / user** | `~/.claude/CLAUDE.md` (copy) | Working agreement for every project on this machine |
| `templates/user-settings.plugins.json` (Desktop-only machines) | **Global / user** | merged into `~/.claude/settings.json` | Marketplace + `base` (+ Anthropic's `claude-code-setup`) without the `claude` CLI; `marketing@synced` off; auto-update opt-in |
| Hooks `guard`/`format`/`verify`/`plan-gate` (`.ps1`+`.sh`, optional) | **Global / user** | `~/.claude/hooks/` | guard = enforce no-secret-read/egress + safe agent-gen, and ask before guard/ledger edits; format = auto-format edited file; verify = run the project's guards before finishing; plan-gate = don't finish an `/implement-plan` run with plan items or ACs still open |
| `templates/sandbox-settings.json` (optional; Linux/macOS/WSL2) | **Global / user** | merged into `~/.claude/settings.json` | OS-enforced network control for shell commands |
| `managed-settings.json` (optional) | **Machine policy** | OS policy dir (see §E) | Unbreakable: locks bypass-disable + crown-jewel secret denies |
| `CLAUDE.md` | **Per project** | `<project>/CLAUDE.md` | Project description, package map, conventions |
| `templates/CLAUDE.package.md` | **Per package** | `<project>/<area>/CLAUDE.md` | On-demand stack commands for each subsystem |
| `templates/REGRESSIONS.md` | **Per project** (committed) | `<project>/REGRESSIONS.md` | Fix-once ledger: one guarded row per fix or correction |
| `templates/guards.sh` + `templates/guards.ps1` | **Per project** (committed) | `<project>/.claude/guards.sh`, `.ps1` | Guard runner: tests, lint, content-lint, ledger-integrity |
| `templates/checks.sh` / `templates/checks.cmd` | **Per project, local only** (gitignored) | `<project>/.claude/checks.sh`, `.cmd` | One-line wrapper the allowlisted `verify` hook runs → the guard runner |
| `.claude/settings.json` (this repo's baseline) | **Per project** (committed) | `<project>/.claude/settings.json` | Baseline for single-repo cloud sessions |
| `templates/rules/content.md` (optional) | **Per project** | `<project>/.claude/rules/content.md` | Content rules that load only when content files are read |
| `templates/banned-phrases.txt`, `templates/brand-voice.md` | **Per project** (content) | `<project>/brand/banned-phrases.txt`, `brand/voice.md` | Automated wording guard + brand voice |
| `templates/github/regression-guards.yml` | **Per project** (CI) | `<project>/.github/workflows/regression-guards.yml` | Guards on every PR/push + weekly |
| `templates/PROGRESS.md` (optional) | **Per project** | `<project>/PROGRESS.md` | State for multi-session work |
| `templates/SPEC.md`, `templates/features.json` (optional) | **Per project** | `<project>/specs/<slug>.md`, `specs/<slug>.features.json` | Written by `/spec`: requirements AC1… with evidence, and the multi-session feature list |
| `.gitignore` | **Per project** | `<project>/.gitignore` | Keep secrets & local Claude state out of git |
| `claude-ai/personal-preferences.md` | **claude.ai account** | Settings → General → Instructions for Claude | The core rules in chat and Cowork |
| `claude-ai/project-*.md` | **claude.ai Project** | Project instructions | One Project per role |
| `scripts/package-claude-ai.sh` / `.ps1` | **claude.ai account** | Customize → Skills (upload) | Skill zips, only where plugins don't reach |

> `settings.json` is **the same file** on Windows and Linux — the path globs are forward-slash and cross-platform, and the Windows-only denies (e.g. `Invoke-WebRequest`, the `PowerShell(...)` rules) simply never match on Linux. Copy it as-is on either OS.

Replace `<repo>` below with the path where this config repo lives on the machine you're installing on.

> **Install in parts:** (1) the **security baseline** — `settings.json` (+ `global/CLAUDE.md`, optional hooks and managed policy) — installs the classic way below (§A/§B, §E); it is *not* plugin-able. (2) the **agent team** — `base` plus the optional `marketing`/`council`/`ecc` addons — installs from the **plugin marketplace** (§G), or by a **manual copy** into `~/.claude/` if you'd rather not use plugins (§H). (3) **per project** files (§C). (4) the **claude.ai account** layer (Quick start step 8).

---

## A. Windows (PowerShell) — security baseline, global memory + hooks

```powershell
# --- paths ---
$repo = "<repo>"      # this config repo on the local machine, e.g. "$env:USERPROFILE\claude-md"
$dest = "$env:USERPROFILE\.claude"

# 1. Hooks directory
New-Item -ItemType Directory -Force "$dest\hooks" | Out-Null

# 2. Install the security baseline at USER scope (covers every project)
#    If you already have ~/.claude/settings.json, back it up and merge the "permissions" block and "useAutoModeDuringPlan" by hand instead.
#    Never copy over an existing file: that drops your merged "hooks" block (switching the guard hook off) and every other key you added.
if (Test-Path "$dest\settings.json") { Copy-Item "$dest\settings.json" "$dest\settings.json.$(Get-Date -Format yyyyMMdd-HHmmss).bak"; "settings.json exists - backed it up; merge $repo\.claude\settings.json into it by hand" } else { Copy-Item "$repo\.claude\settings.json" "$dest\settings.json" }

# 3. Global memory — the machine-wide working agreement. COPY it (never a symlink or hard link: Cowork skips those).
#    If you already have ~/.claude/CLAUDE.md, merge by hand instead (the guard below never overwrites it).
if (Test-Path "$dest\CLAUDE.md") { "CLAUDE.md exists - merge $repo\global\CLAUDE.md into it by hand" } else { Copy-Item "$repo\global\CLAUDE.md" "$dest\CLAUDE.md" }

# 4. (Optional) Install the hooks: guard (security) + format/verify (convenience)
Copy-Item "$repo\.claude\hooks\*.ps1" "$dest\hooks\" -Force

# The agents + skills are NOT copied here — they install as the `base` plugin (see §G).
```

Then, **only if you installed the hooks**, add this to `~/.claude/settings.json` next to `permissions`. Keep it when you later update the baseline: merge the new `settings.json` in, never copy it over the file — a copy drops this `hooks` block and silently switches `guard` off. **Exec form (recommended):** `command` + `args` start `powershell.exe` directly — no shell, no nested quoting — so it behaves the same whether or not Git Bash is installed:

```json
"hooks": {
  "PreToolUse": [
    { "matcher": "Bash|PowerShell|Monitor|Write|Edit", "hooks": [ { "type": "command", "command": "powershell.exe", "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:/Users/<you>/.claude/hooks/guard.ps1"] } ] }
  ],
  "PostToolUse": [
    { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "powershell.exe", "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:/Users/<you>/.claude/hooks/format.ps1"] } ] }
  ],
  "UserPromptSubmit": [
    { "hooks": [ { "type": "command", "command": "powershell.exe", "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:/Users/<you>/.claude/hooks/verify.ps1"], "timeout": 30 } ] }
  ],
  "Stop": [
    { "hooks": [ { "type": "command", "command": "powershell.exe", "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:/Users/<you>/.claude/hooks/verify.ps1"] } ] },
    { "hooks": [ { "type": "command", "command": "powershell.exe", "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:/Users/<you>/.claude/hooks/plan-gate.ps1"], "timeout": 15 } ] }
  ]
}
```

**Shell form (alternative):** a single `command` string. On Windows, shell-form hook commands run through Git Bash — or PowerShell when Git Bash isn't installed — never `cmd`:

```json
"hooks": {
  "PreToolUse": [
    { "matcher": "Bash|PowerShell|Monitor|Write|Edit", "hooks": [ { "type": "command", "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<you>\\.claude\\hooks\\guard.ps1\"" } ] }
  ],
  "PostToolUse": [
    { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<you>\\.claude\\hooks\\format.ps1\"" } ] }
  ],
  "UserPromptSubmit": [
    { "hooks": [ { "type": "command", "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<you>\\.claude\\hooks\\verify.ps1\"", "timeout": 30 } ] }
  ],
  "Stop": [
    { "hooks": [ { "type": "command", "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<you>\\.claude\\hooks\\verify.ps1\"" } ] },
    { "hooks": [ { "type": "command", "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<you>\\.claude\\hooks\\plan-gate.ps1\"", "timeout": 15 } ] }
  ]
}
```
> Adjust the path if your home directory differs (`$env:USERPROFILE`). Install only the hooks you want — `guard` (security) is the recommended one; `format`/`verify` are convenience. The same registrations, plus an **opt-in per-prompt delegation directive** (the old `base` prompt hook), are in `.claude/settings.hooks.example.json`. **`guard`** blocks secret reads through `Bash`, `PowerShell` and `Monitor` (including interpreters such as python/node), prompts on network egress, and **asks** before an edit changes or removes existing `REGRESSIONS.md` rows (appends pass), before any edit to `.claude/guards.*` or `.claude/checks.*`, and before lines are removed from `brand/banned-phrases.txt`. **Trust note:** `format` auto-runs the project's local formatter binaries and `verify` auto-runs the project's `.claude\checks.cmd`, so enable them only on repos you trust. **`verify` is allowlist-gated:** it runs a project's `.claude\checks.cmd` (the local wrapper from `templates/checks.cmd` that calls the committed `.claude\guards.ps1`) only when that project's path is also listed in `%USERPROFILE%\.claude\verify-allowed.txt`, so a cloned repo can't auto-run code. After a trusted project's first green `guards` run (§C), create its `.claude\checks.cmd` and enable it with `Add-Content "$env:USERPROFILE\.claude\verify-allowed.txt" "<project path>"`. **`plan-gate`** (optional, convenience) keeps Claude from finishing while an `/implement-plan` run still has open plan items or ACs, up to 3 nudges, then warns "plan NOT complete". It reads only the plan files named in `.claude\plan-gate.local.json`, a marker `/implement-plan` writes for the current session, and runs no project code, so it needs no allowlist; without a marker it exits at once. All Stop hooks share Claude Code's cap of 8 consecutive continuations (verify 3 + plan-gate 3 fits).

**Verify (PowerShell):**
```powershell
Get-Content "$env:USERPROFILE\.claude\settings.json" -Raw | ConvertFrom-Json | Out-Null; "settings OK"
claude plugin list           # after §G: base@claude-md-packs (+ addons) enabled
claude plugin details base   # the Always-on token line (~2.9k for base)
# then inside Claude Code (CLI, Desktop Code tab or VS Code):
#   /context  -> Memory files lists ~/.claude/CLAUDE.md; custom agents with source; skills
#   /plugin   -> shows installed plugins (base / marketing / council) — CLI; Desktop: + -> Plugins
#   /memory   -> opens/edits memory files (it lists locations, not what loaded — use /context for that)
#   /hooks    -> guard / format / verify / plan-gate + base's SessionStart hook (read-only view)
#   /skills   -> caveman, secure-code-reviewer, work-quality-checker, regression-guard, setup-advisor, requirements-gate (+ addon skills)
#   /status   -> the settings files that loaded (user, project, managed)
#   @agent-   -> typeahead lists the pack agents (/agents only prints a reminder now)
```

---

## B. Ubuntu / Linux (bash) — security baseline, global memory + hooks

The hook port (`guard.sh`) needs **jq**:
```bash
sudo apt-get update && sudo apt-get install -y jq   # Ubuntu/Debian
# macOS (Homebrew): brew install jq
```

```bash
# --- paths ---
REPO="<repo>"          # path where you cloned this config repo, e.g. "$HOME/claude-md"
DEST="$HOME/.claude"

# 1. Hooks directory
mkdir -p "$DEST/hooks"

# 2. Install the security baseline at USER scope (covers every project)
#    If you already have ~/.claude/settings.json, back it up and merge the "permissions" block and "useAutoModeDuringPlan" by hand instead.
#    Never copy over an existing file: that drops your merged "hooks" block (switching the guard hook off) and every other key you added.
if [ -e "$DEST/settings.json" ]; then cp "$DEST/settings.json" "$DEST/settings.json.$(date +%Y%m%d-%H%M%S).bak"; echo "settings.json exists - backed it up; merge $REPO/.claude/settings.json into it by hand"; else cp "$REPO/.claude/settings.json" "$DEST/settings.json"; fi

# 3. Global memory — the machine-wide working agreement. COPY it (never a symlink or hard link: Cowork skips those).
#    If you already have ~/.claude/CLAUDE.md, merge by hand instead (the guard below never overwrites it).
if [ -e "$DEST/CLAUDE.md" ]; then echo "CLAUDE.md exists - merge $REPO/global/CLAUDE.md into it by hand"; else cp "$REPO/global/CLAUDE.md" "$DEST/CLAUDE.md"; fi

# 4. (Optional) Install the hooks: guard (security) + format/verify (convenience)
cp "$REPO"/.claude/hooks/*.sh "$DEST/hooks/"
chmod +x "$DEST"/hooks/*.sh

# The agents + skills are NOT copied here — they install as the `base` plugin (see §G).
```

Then, **only if you installed the hooks**, add this to `~/.claude/settings.json` next to `permissions`. Keep it when you later update the baseline: merge the new `settings.json` in, never copy it over the file — a copy drops this `hooks` block and silently switches `guard` off.

```json
"hooks": {
  "PreToolUse": [
    { "matcher": "Bash|PowerShell|Monitor|Write|Edit", "hooks": [ { "type": "command", "command": "/home/<you>/.claude/hooks/guard.sh" } ] }
  ],
  "PostToolUse": [
    { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "/home/<you>/.claude/hooks/format.sh" } ] }
  ],
  "UserPromptSubmit": [
    { "hooks": [ { "type": "command", "command": "/home/<you>/.claude/hooks/verify.sh", "timeout": 30 } ] }
  ],
  "Stop": [
    { "hooks": [ { "type": "command", "command": "/home/<you>/.claude/hooks/verify.sh" } ] },
    { "hooks": [ { "type": "command", "command": "/home/<you>/.claude/hooks/plan-gate.sh", "timeout": 15 } ] }
  ]
}
```
> `verify` is registered twice on purpose: on `UserPromptSubmit` it only records a marker — the tree state it last checked, or the current tree on the session's first prompt (never runs checks, always exits 0); on `Stop` it skips only when nothing changed since that marker, so files written in between (e.g. by a background subagent) are still checked — so a question or review turn in a project whose checks are already red isn't blocked into unrelated fixes. Without the `UserPromptSubmit` entry it still works, just without that skip.
> Use absolute paths: replace `/home/<you>` with your real home (`echo $HOME`; macOS is `/Users/<you>`) — user-scope hooks get no `$CLAUDE_PROJECT_DIR` and `$HOME` isn't expanded reliably in hook commands. The exec form also works: `"command": "/home/<you>/.claude/hooks/guard.sh", "args": []`. Shell-form commands run via `sh -c` on Linux and macOS. Install only the hooks you want — `guard` is the recommended security one; it also **asks** before an edit changes or removes existing `REGRESSIONS.md` rows (appends pass), before any edit to `.claude/guards.*` / `.claude/checks.*`, and before lines are removed from `brand/banned-phrases.txt`. The opt-in per-prompt delegation directive (the old `base` prompt hook) is in `.claude/settings.hooks.example.json`. **Trust note:** `format` auto-runs the project's local formatter binaries and `verify` auto-runs the project's executable `.claude/checks.sh`, so enable them only on repos you trust. **`verify` is allowlist-gated:** it runs a project's executable `.claude/checks.sh` (the local wrapper from `templates/checks.sh` that calls the committed `.claude/guards.sh`) only when that project's path is listed in `~/.claude/verify-allowed.txt`, so a cloned repo can't auto-run code. After a trusted project's first green `guards` run (§C), create its executable `.claude/checks.sh` and enable it with `echo "/path/to/project" >> ~/.claude/verify-allowed.txt`. **`plan-gate`** (optional, convenience) keeps Claude from finishing while an `/implement-plan` run still has open plan items or ACs, up to 3 nudges, then warns "plan NOT complete". It reads only the plan files named in `.claude/plan-gate.local.json`, a marker `/implement-plan` writes for the current session, and runs no project code, so it needs no allowlist; without a marker it exits at once. All Stop hooks share Claude Code's cap of 8 consecutive continuations (verify 3 + plan-gate 3 fits). An opt-in, per-project soft check (`_optional_promptCompletionCheck`, a small-model Stop hook) is documented in `.claude/settings.hooks.example.json`.

**Verify (bash):**
```bash
jq . "$HOME/.claude/settings.json" >/dev/null && echo "settings OK"
claude plugin list           # after §G: base@claude-md-packs (+ addons) enabled
claude plugin details base   # the Always-on token line (~2.9k for base)
# then inside Claude Code (CLI, Desktop Code tab or VS Code):
#   /context  -> Memory files lists ~/.claude/CLAUDE.md; custom agents with source; skills
#   /plugin   -> shows installed plugins (base / marketing / council) — CLI; Desktop: + -> Plugins
#   /memory   -> opens/edits memory files (it lists locations, not what loaded — use /context for that)
#   /hooks    -> guard / format / verify / plan-gate + base's SessionStart hook (read-only view)
#   /skills   -> caveman, secure-code-reviewer, work-quality-checker, regression-guard, setup-advisor, requirements-gate (+ addon skills)
#   /status   -> the settings files that loaded (user, project, managed)
#   @agent-   -> typeahead lists the pack agents (/agents only prints a reminder now)
```

---

## C. Per project (same on both OSes)

From inside each project root:

**Windows** (run in PowerShell — not cmd — from your project root)
```powershell
$repo = "<repo>"     # the config repo on the local machine, e.g. "$env:USERPROFILE\claude-md"; RE-SET this in each new terminal
Copy-Item "$repo\CLAUDE.md" ".\CLAUDE.md"
# Per package/area — repeat for each REAL subsystem folder (create it first if needed):
New-Item -ItemType Directory -Force ".\apps\web" | Out-Null
Copy-Item "$repo\templates\CLAUDE.package.md" ".\apps\web\CLAUDE.md"
Copy-Item "$repo\.gitignore" ".\.gitignore"                            # skip/merge if one already exists

# Fix once: the ledger + the committed guard runners
New-Item -ItemType Directory -Force ".\.claude",".\.github\workflows" | Out-Null
Copy-Item "$repo\templates\REGRESSIONS.md" ".\REGRESSIONS.md"
Copy-Item "$repo\templates\guards.sh"  ".\.claude\guards.sh"
Copy-Item "$repo\templates\guards.ps1" ".\.claude\guards.ps1"
Copy-Item "$repo\templates\github\regression-guards.yml" ".\.github\workflows\regression-guards.yml"   # CI, zero model tokens
# Baseline for single-repo cloud sessions (merge if the project already has a .claude\settings.json)
Copy-Item "$repo\.claude\settings.json" ".\.claude\settings.json"

# Optional — content work
New-Item -ItemType Directory -Force ".\.claude\rules",".\brand" | Out-Null
Copy-Item "$repo\templates\rules\content.md"     ".\.claude\rules\content.md"
Copy-Item "$repo\templates\banned-phrases.txt"   ".\brand\banned-phrases.txt"
Copy-Item "$repo\templates\brand-voice.md"       ".\brand\voice.md"
# Optional — work that spans sessions
Copy-Item "$repo\templates\PROGRESS.md" ".\PROGRESS.md"
# Next: set $TestCmd / $LintCmd and run the guards until green (below) — only then add the local verify wrapper
```

**Ubuntu** (run from your project root)
```bash
REPO="<repo>"          # the config repo, e.g. "$HOME/claude-md"; RE-SET this in each new shell
cp "$REPO/CLAUDE.md" ./CLAUDE.md
# Per package/area — repeat for each REAL subsystem folder (create it first if needed):
mkdir -p ./apps/web
cp "$REPO/templates/CLAUDE.package.md" ./apps/web/CLAUDE.md
cp "$REPO/.gitignore" ./.gitignore                            # skip/merge if one already exists

# Fix once: the ledger + the committed guard runners
mkdir -p ./.claude ./.github/workflows
cp "$REPO/templates/REGRESSIONS.md" ./REGRESSIONS.md
cp "$REPO/templates/guards.sh"  ./.claude/guards.sh
cp "$REPO/templates/guards.ps1" ./.claude/guards.ps1
cp "$REPO/templates/github/regression-guards.yml" ./.github/workflows/regression-guards.yml   # CI, zero model tokens
# Baseline for single-repo cloud sessions (merge if the project already has a .claude/settings.json)
cp "$REPO/.claude/settings.json" ./.claude/settings.json

# Optional — content work
mkdir -p ./.claude/rules ./brand
cp "$REPO/templates/rules/content.md"   ./.claude/rules/content.md
cp "$REPO/templates/banned-phrases.txt" ./brand/banned-phrases.txt
cp "$REPO/templates/brand-voice.md"     ./brand/voice.md
# Optional — work that spans sessions
cp "$REPO/templates/PROGRESS.md" ./PROGRESS.md
# Next: set TEST_CMD / LINT_CMD and run the guards until green (below) — only then add the local verify wrapper
```

Then fill in `<APP_NAME>`, the repo/package map, and each area's `install / test / lint / build / run` commands. Set the `tests` and `lint` step commands — `TEST_CMD` / `LINT_CMD` in `.claude/guards.sh`, `$TestCmd` / `$LintCmd` in `.claude/guards.ps1` — and check `CONTENT_DIRS` (PowerShell: `$ContentDirs`); run `bash .claude/guards.sh` (Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File .claude\guards.ps1`) once to see a baseline. A freshly copied `REGRESSIONS.md` is header-only (examples are in `templates/REGRESSIONS.examples.md`, never copied), so `ledger-integrity` starts green; fix any other red step before going on. Every step prints `OK <step>`, `ERROR <step>: <reason>` or `SKIP <step>: <reason>`, then one summary line; full output goes to `.claude/guards.log` (gitignored). Add a `check:` step for any rule a test can't cover — the runner's header shows how.

**After the first green `guards` run — LOCAL ONLY (gitignored), trusted projects:** let the `verify` hook run the guards. Adding it only now means `verify` starts gating once you've configured the runner and seen it pass — a red runner behind the wrapper would block every "done" until it's fixed.

**Windows**
```powershell
$repo = "<repo>"     # the config repo, as above
Copy-Item "$repo\templates\checks.cmd" ".\.claude\checks.cmd"
Add-Content "$env:USERPROFILE\.claude\verify-allowed.txt" (Get-Location).Path
```

**Ubuntu**
```bash
REPO="<repo>"          # the config repo, as above
cp "$REPO/templates/checks.sh" ./.claude/checks.sh
chmod +x ./.claude/checks.sh ./.claude/guards.sh
pwd >> "$HOME/.claude/verify-allowed.txt"
```

- **`.claude/checks.sh` / `.cmd` stay local on purpose.** They are the trigger the `verify` hook auto-runs, so they're gitignored and created only by you, per trusted project; the guard logic itself lives in the committed `.claude/guards.*`, which CI and cloud sessions run too.
- **Cloud sessions** read the committed `.claude/settings.json` only in single-repo sessions, and never install plugins from it — commit copies of the agents/skills they need (§H, destination = the project's `.claude\`). If you run routines on the repo, test that a Plan default doesn't stall them (Quick start step 7).
- **Ledger area tags** are lowercase: `code/<area>`, `mkt/<channel>`, `ops/<system>`, `docs/<area>`, `biz/<area>`. How rows get added and checked: [`WORKFLOW.md`](WORKFLOW.md).

**First run in a project (both OSes):**
```text
claude --permission-mode plan
> Use project-analyst to detect the stack, then team-configurator to write the
> AI Team Configuration table into CLAUDE.md.
```
Review the proposed table — and anything under **"Generated agents — review before enabling"** — before approving.

---

## D. Personal overrides & trimming

- `<project>/.claude/settings.local.json` merges over the project's `settings.json` and is excluded from git automatically when Claude Code creates it (if you create it by hand, check it's in `.gitignore`). `~/.claude/settings.local.json` isn't a documented file — put personal, machine-wide tweaks in `~/.claude/settings.json` instead. Use the project file for personal per-project tweaks — e.g. re-allow a safe command in one project:
  ```json
  { "permissions": { "allow": ["Bash(curl http://localhost:*)", "Read(vendor/**)"] } }
  ```
  (`vendor/` is build output in Node/Composer but readable source in Go — re-allow it per project if needed. An `allow` can't override a `deny` from any layer.)
- Skip packages you never work in, in any settings layer:
  ```json
  { "claudeMdExcludes": ["**/legacy-vendor/**", "packages/experiments/**"] }
  ```
- Personal project notes go in `<project>/CLAUDE.local.md` (gitignored; loads after `CLAUDE.md`).
- Optional user-settings knobs in `~/.claude/settings.json`: `"outputStyle": "Concise"` for terser replies (a lighter alternative to `/caveman`), and `"remoteControlAtStartup": true` to reach every local session from phone or web (§J).

---

## E. (Optional) Unbreakable enforcement — managed policy

The user-scope `settings.json` can be edited or removed by you (or, in a worst case, by a prompt-injected agent that gets a write approved). A cloned repo's `.claude/settings.json` also **outranks** your user settings for single-value keys — it could set `disableAllHooks` or a looser `defaultMode`. For protection that **cannot be overridden by any user/project/local setting or even a CLI flag**, install the managed-policy file. It is the **highest** tier in Claude Code's settings hierarchy.

It locks only the non-negotiables — `disableBypassPermissionsMode` and a core of crown-jewel secret denies: `.env`/`.envrc` (including the filesystem-wide `//**/.env` form), private keys and keystores (`*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.keystore`, `*.jks`, `*.ppk`, SSH keys), SSH/cloud/container/DB credentials, `*.tfstate`/`*.tfvars` — now also **home-anchored** (`~/.ssh/**`, `~/.aws/**`, `~/.azure/**`, `~/.config/gcloud/**`, `~/.config/gh/**`, `~/.gnupg/**`, `~/.kube/**`, `~/.docker/**`, `~/.git-credentials`, `~/.netrc`, `~/.npmrc`, `~/.pypirc`, `~/.pgpass`, `~/.my.cnf`, `~/.claude/.credentials.json`). A `**/.ssh/**` rule only matches under the working directory, so the `~/` forms are what protect your home directory while Claude works in a project. There is no supported managed key to disable auto-accept (`acceptEdits`) mode — bypass mode is the lock that matters, and the user-scope `defaultMode: "plan"` baseline covers the default. If you want stronger locks, your copy of the managed file can also carry `"useAutoModeDuringPlan": false`, `permissions.defaultMode: "plan"` or `permissions.disableAutoMode: "disable"`. The flexible parts (build-dir noise, `.env.*`, the Bash/PowerShell speed-bumps) stay in user scope where you can still tune them per project.

**Where it applies:** the CLI, VS Code, JetBrains, the Desktop Code tab and Cowork sessions running on that device all read the device policy file. Cloud Code sessions don't — only server-managed settings (Team/Enterprise, set by an Owner in the admin console) reach them.

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

> Keep the managed file minimal (dangerous-mode disable + crown-jewel secret reads) so per-project flexibility still lives in the user/local layers. Do **not** set `allowManagedPermissionRulesOnly` unless you want the managed deny-list to be the *only* permission rules in effect (it would disable your user-scope deny-list and per-project `allow` rules). Check it took effect with `/status`. To remove the policy later, delete the file from the OS dir with the same admin/root rights.

---

## F. Notes & residual risks

- **Start in Plan mode.** `settings.json` sets `defaultMode: "plan"` and `disableBypassPermissionsMode: "disable"`. Never launch with `--dangerously-skip-permissions`. It also sets **`useAutoModeDuringPlan: false`**: when auto mode is available, its classifier would otherwise approve shell commands during planning; `false` keeps planning human-gated (honoured from user or managed settings — a project file's `false` is ignored). VS Code needs `claudeCode.initialPermissionMode: "plan"`, and Desktop remembers a per-folder mode pick (Quick start step 6).
- **What the deny-list covers.** `Read` denies apply to Claude's file tools, the file commands Claude Code recognises in Bash (`cat`, `head`, `tail`, `sed`, `tee`) and redirect targets — **not** to `grep -r` or to scripts (Python, Node). A `**/x` rule only matches under the working directory, so the baseline adds home-anchored `~/…` rules and `//**/.env` for secrets outside the project. The `Bash(...)`/`PowerShell(...)` denies are a *speed-bump*: they match command text, so absolute paths (`/usr/bin/curl`), `sh -c '…'`, interpreters (python, node) and `npx` get past them. Real enforcement = plan-mode + per-command approval + no `base`/`council` agent has network tools (only `marketing`'s two researchers do — and account-synced `marketing@synced` loads them in every signed-in session unless you turn it off, Quick start step 4) + the `guard` hook (which also catches interpreter reads of secret paths) + the optional sandbox below.
- **PowerShell parity (Windows).** Claude's `PowerShell` tool is separate from `Bash`: `Bash(...)` rules and a `Bash|Write|Edit` hook matcher don't cover it. The baseline mirrors each shell deny and ask rule as `PowerShell(...)`, and the `guard` matcher is `Bash|PowerShell|Monitor|Write|Edit`.
- **Ask list.** Outbound and publish actions — `ssh`, `rsync`, `gh gist`, `gh repo create`, `gh release`, `npm publish`, `docker push` (Bash and PowerShell) — always prompt; ask rules keep prompting even in auto mode.
- **Opt-in sandbox — `templates/sandbox-settings.json`** (Linux, macOS, WSL2; native Windows isn't supported; Linux/WSL2 need `bubblewrap` + `socat`). It puts every Bash, PowerShell and Monitor command behind OS-enforced network control, so a connection to an unlisted host prompts whichever program makes it — the gap the text-matching denies leave. `autoAllowBashIfSandboxed` stays `false`, so nothing gets auto-approved; hooks and MCP servers run outside the sandbox. Try it for one session with `claude --settings <repo>/templates/sandbox-settings.json`, merge it into `~/.claude/settings.json` to keep it, then check `/sandbox`.
- **Unbreakable enforcement** of bypass-disable + core secret denies is the managed policy in §E (highest tier, admin-owned, cannot be overridden). A cloned repo's `.claude/settings.json` outranks your user file for single-value keys (e.g. `disableAllHooks: true` would silence `guard`/`verify`) — read a new repo's `.claude/settings.json` before trusting the folder.
- **The optional `format`/`verify` hooks run outside the permission system** — plan-mode, the deny-list, and bypass-disable do not constrain hook-spawned processes. `verify` only runs a project's checks when that project's path is on your `~/.claude/verify-allowed.txt` allowlist (so a cloned repo can't auto-run code); `format` runs only formatters already installed in the project. Enable both only on repos you trust. `guard` is the only hook that hardens posture and is safe on any repo. `verify` blocks finishing while the guards are red, up to 3 times in a row by default (`CLAUDE_VERIFY_MAX_BLOCKS`), then stops blocking and shows a "checks still RED" message (Claude Code itself ends a turn after 8 consecutive Stop-hook blocks) — at that point the `regression-guard` rule is to report `Guards: RED` and not claim done.
- **Desktop specifics.** Desktop doesn't inherit shell exports — set MCP keys in its Local environment editor (Quick start step 5). **WSL** sessions have no plugins (use the Local environment, or the CLI inside WSL). **SSH** sessions read the *remote* host's `~/.claude` — install the baseline, global `CLAUDE.md` and packs there.
- **claude.ai connectors.** When you sign in to Claude Code with a claude.ai account, connectors you added on claude.ai reach the **main session** too. The pack agents' explicit `tools:` lists keep them away from subagents. Review them with `/mcp`; block per server with `deniedMcpServers`, or all of them with `disableClaudeAiConnectors`.
- Every file is identical across Windows/macOS/Linux — only paths and the hook script (`guard.ps1` vs `guard.sh`) differ.

---

## G. Install the team — plugin marketplace (base + addons)

The agent team ships as Claude Code **plugins**, listed in `.claude-plugin/marketplace.json`: install **`base`** (the main 25-agent team + 6 skills), then add the **`marketing`** and **`council`** addons as needed, and **`ecc`** per project. Nothing under `plugins/` loads until you install it. Same flow on every OS:

```text
# 1. add this repo as a plugin marketplace (local path works; or <owner>/claude-md once it's pushed to GitHub)
/plugin marketplace add <path-to-this-repo>

# 2. install the base team, then whichever addons you want — toggle any of them anytime from /plugin
/plugin install base@claude-md-packs         # MAIN: 25 engineering agents + 6 skills + /implement-plan + /spec
/plugin install marketing@claude-md-packs    # addon: 7 marketing/content agents + 2 skills + /marketing:draft, /marketing:review
/plugin install council@claude-md-packs      # addon: 6 council seats + the /council skill
/plugin install ecc@claude-md-packs          # addon, per project only: 41 ECC agents + 116 skills + 34 commands

# 3. Anthropic's official marketplace + its read-only setup recommender (base's setup-advisor builds on it)
/plugin marketplace add anthropics/claude-plugins-official   # skip if /plugin marketplace list already shows claude-plugins-official
/plugin install claude-code-setup@claude-plugins-official
```

`/plugin install <plugin>` opens the plugin's page in the panel — confirm the install there; `/reload-plugins` applies changes to a running session. From a shell the equivalents are `claude plugin marketplace add <owner>/claude-md` and `claude plugin install <pack>@claude-md-packs` (add `--scope local` or `--scope project` for `ecc`); in the Desktop Code tab use **+ → Plugins** (Quick start step 4).

- **`base`** is the main install — the 25 zero-network engineering agents, 6 skills (`/caveman`, `secure-code-reviewer`, `work-quality-checker`, `regression-guard`, `setup-advisor`, `requirements-gate`) and the `/implement-plan` and `/spec` commands. Pair it with the `settings.json` security baseline (§A/§B), which is required and is not part of any plugin. It ships **one static, no-network `SessionStart` hook** (matcher `startup|clear|compact`, 10-second timeout) that adds one working-agreement line — small, sequential or same-file work inline; 10+ files, 3+ independent parts or an independent review → parallel subagents; use relevant skills unasked; apply `regression-guard` before calling work done. It **replaces the old per-prompt `UserPromptSubmit` hook**, which re-sent its directive with every prompt; for per-prompt reinforcement, merge the opt-in snippet from `.claude/settings.hooks.example.json` into your user settings. `/hooks` only shows it (read-only). To turn it off, disable `base` (`/plugin`, or `claude plugin disable base@claude-md-packs`), or set `"disableAllHooks": true` — which also silences `guard` and `verify`.
- **`marketing`** adds the 7 marketing/content agents, the `ai-writing-tells` and `brand-voice` skills, and the ledger-aware `/marketing:draft` and `/marketing:review` commands (they check the matching `mkt/` rows in `REGRESSIONS.md` and the project's `brand/` files). Two agents are network-enabled (`content-researcher` via Tavily, `seo-rank-monitor` via DataForSEO). Their MCP servers are declared at **plugin scope** in `plugins/marketing/.mcp.json`, because per-subagent inline `mcpServers` is ignored inside a plugin. Under a plugin install the tools are named **`mcp__plugin_marketing_tavily__tavily_search`**, `mcp__plugin_marketing_dataforseo__…`; the agents list these plus the classic `mcp__tavily__…` / `mcp__dataforseo__…` names used by a manual install. Set `TAVILY_API_KEY` / `DATAFORSEO_USERNAME` / `DATAFORSEO_PASSWORD` in your environment first (Desktop: its Local environment editor), then run `/mcp` to confirm the servers connect and the exact tool names. Full security model: [`council-and-network-config.md`](council-and-network-config.md). If your build doesn't pick up the plugin-scope `.mcp.json`, move those two servers into your global `~/.claude.json` instead. **Enabled on the claude.ai account, `marketing` also loads — MCP servers included — in every signed-in Claude Code session as `marketing@synced`**; to keep it to marketing machines, leave it off the account (or set `"marketing@synced": false` on every other machine) and install it per machine/project (Quick start steps 4 and 8).
- **`council`** adds the 6 reasoning seats and the `/council` skill — pure reasoners, no network, no scripts. The seats start without `CLAUDE.md` (`omitClaudeMd`); the skill passes each one the question, the key constraints and the matching `REGRESSIONS.md` rows. Where sub-agents aren't available (claude.ai chat, mobile) the skill runs a single-model chat fallback.
- **`ecc`** adds a curated, security-audited subset of [ECC](https://github.com/affaan-m/ECC) (MIT, snapshot `81af407`): 41 agents, 116 engineering skills, and 34 slash-commands — an engineering core plus 10 ECC agent-engineering knowledge skills (the broader ECC harness/command machinery was trimmed for token economy). It is **namespaced separately** so nothing collides with `base`, and is **pure markdown** — no bundled scripts, hooks, or installers. It adds ≈15k always-on tokens, so enable it **per project** (`--scope local` / `--scope project`), never user-wide. Web access stays blocked by the `settings.json` baseline; `ecc`'s `github-ops` skill uses the authenticated `gh` CLI, and `inherit-legacy-style` can install a user-gated hook (review before accepting). Provenance and the exact audit edits: [`plugins/ecc/ATTRIBUTION.md`](plugins/ecc/ATTRIBUTION.md).
- **`setup-advisor`** (`base` skill) + **`claude-code-setup`** (Anthropic, `claude-plugins-official`, ≈0.14k always-on, read-only): ask "what should I install?", "audit my Claude setup" or "set up Claude for this project". The skill inventories what's installed (`claude plugin list`, `claude plugin details`), reads `CLAUDE.md`, the `REGRESSIONS.md` area tags, manifests and content dirs, and runs Anthropic's `claude-automation-recommender` for hook/MCP/subagent ideas when `claude-code-setup` is installed (it recommends installing it otherwise). It reports the top 3–5 picks as a table (evidence, always-on cost, exact command) and asks with a multi-select pop-up. **Trusted sources only**: the claude-md packs, Anthropic-authored plugins in `claude-plugins-official` (not the partner plugins that marketplace also lists), and your account skills. **Additive only**: duplicates are listed as optional cleanup for you to decide. It fetches nothing, and nothing installs until you tick it; each install still goes through the permission prompt. Claude Code normally registers `claude-plugins-official` on its own at the first interactive terminal session, but the `claude plugin` commands never do, so run step 3's `marketplace add` if `/plugin marketplace list` lacks it.
- The **`marketing`/`council`/`ecc`** addon packs are **agents/skills/commands only — no hooks** (`base` ships one static, no-network `SessionStart` hook; see above; `marketing` also ships its two MCP servers) — so they keep the core's least-privilege posture. Disable or remove a pack anytime from `/plugin` (or `/plugin marketplace remove`).
- **Measure the always-on cost** of an installed pack with `claude plugin details <pack>`: base ≈2.9k tokens, marketing ≈0.86k (≈0.7k actually in context — the tool also counts the two manual-only `/marketing:*` commands, whose descriptions Claude never sees), council ≈0.5k, ecc ≈15.4k; Anthropic's `claude-code-setup` ≈0.14k.
- **Validate (maintainers, zero model tokens):** `claude plugin validate . --strict` for the marketplace, plus `claude plugin validate plugins/<pack> --strict` for each pack — the marketplace check doesn't open the packs' agent, skill, command or hook files. It catches broken frontmatter, which matters: a plugin agent whose frontmatter fails to parse loads with **every** field ignored, including its `tools:` allowlist. This repo's own `.claude/guards.sh` runs it as the `plugin-validate` step whenever the `claude` CLI is on PATH.
- **Evals (maintainers, behavioural guards for the packs):** suites live in `plugins/base/evals/`, `plugins/marketing/evals/` and `plugins/council/evals/`. Run one from the repo root with `claude plugin eval plugins/<pack> --threshold 0.8 --max-cost-usd 10` (add `--trust-plugin` when there's no interactive terminal, e.g. CI or scripts) — they check that skills trigger, routing picks the right agents, trivial prompts stay inline (no over-delegation), the researcher reaches Tavily and drafts avoid banned phrases. Run them before a version bump or after editing a `description` or `hooks/hooks.json`; each pack's `evals/README.md` has the cheap-pass and CI flags. Each run is real model usage on your account (every case runs with and without the plugin), so keep the `--max-cost-usd` cap. MCP servers are mocked by default, so the network cases need no keys; on native Windows, run any suite that grants shell tools under WSL2. Results go to `evals/results/` (gitignored).

---

## H. Manual install (no plugins)

Prefer not to use the plugin system? The agents, skills and commands are plain files — copy them straight into `~/.claude/` and skip plugins entirely. The `settings.json` security baseline and `global/CLAUDE.md` (§A/§B) still apply either way. Replace `<repo>` with this config repo's path.

> ⚠️ **Flat-copying collapses plugin namespaces.** Copying `plugins/*/agents/*.md` into the single `~/.claude/agents/` directory drops the per-plugin namespacing the marketplace install provides — if two packs ever ship agents with the same `name:` field, which one loads is nondeterministic (filesystem read order). **Prefer the plugin install (§G) as the default**; if you do install manually, run `/doctor` afterwards to surface duplicate agent names (verify — also check the custom-agent list in `/context`).

**Windows (PowerShell)**
```powershell
$repo = "<repo>"; $dest = "$env:USERPROFILE\.claude"
New-Item -ItemType Directory -Force "$dest\agents","$dest\skills","$dest\commands" | Out-Null
Copy-Item "$repo\plugins\*\agents\*.md"          "$dest\agents\" -Force            # all 78 across packs (use \base\ for just the 24; ecc's skills/commands are NOT copied here)
# skills — base (5), council (1), marketing (2); each lands as $dest\skills\<name>
Copy-Item "$repo\plugins\base\skills\caveman"                "$dest\skills\" -Recurse -Force
Copy-Item "$repo\plugins\base\skills\secure-code-reviewer"   "$dest\skills\" -Recurse -Force
Copy-Item "$repo\plugins\base\skills\work-quality-checker"   "$dest\skills\" -Recurse -Force
Copy-Item "$repo\plugins\base\skills\regression-guard"       "$dest\skills\" -Recurse -Force
Copy-Item "$repo\plugins\base\skills\setup-advisor"          "$dest\skills\" -Recurse -Force
Copy-Item "$repo\plugins\council\skills\council"             "$dest\skills\" -Recurse -Force
Copy-Item "$repo\plugins\marketing\skills\ai-writing-tells"  "$dest\skills\" -Recurse -Force
Copy-Item "$repo\plugins\marketing\skills\brand-voice"       "$dest\skills\" -Recurse -Force
# commands — marketing's are renamed so they can't shadow another /draft or /review
Copy-Item "$repo\plugins\base\commands\implement-plan.md"   "$dest\commands\" -Force
Copy-Item "$repo\plugins\marketing\commands\draft.md"       "$dest\commands\marketing-draft.md"  -Force
Copy-Item "$repo\plugins\marketing\commands\review.md"      "$dest\commands\marketing-review.md" -Force
```

**Ubuntu / macOS (bash)**
```bash
repo="<repo>"; dest="$HOME/.claude"
mkdir -p "$dest/agents" "$dest/skills" "$dest/commands"
cp "$repo"/plugins/*/agents/*.md "$dest/agents/"                  # all 78 across packs (use plugins/base/ for just the 24; ecc's skills/commands are NOT copied here)
# skills — base (5), council (1), marketing (2); each lands as $dest/skills/<name>
for s in base/skills/caveman base/skills/secure-code-reviewer base/skills/work-quality-checker base/skills/regression-guard \
         base/skills/setup-advisor council/skills/council marketing/skills/ai-writing-tells marketing/skills/brand-voice; do
  cp -r "$repo/plugins/$s" "$dest/skills/"
done
# commands — marketing's are renamed so they can't shadow another /draft or /review
cp "$repo/plugins/base/commands/implement-plan.md" "$dest/commands/"
cp "$repo/plugins/marketing/commands/draft.md"     "$dest/commands/marketing-draft.md"
cp "$repo/plugins/marketing/commands/review.md"    "$dest/commands/marketing-review.md"
```

- For just the base team, copy from `plugins/base/agents/` instead of `plugins/*/agents/` (and only the base skills and `implement-plan.md`).
- `setup-advisor` works in a manual install too; Anthropic's `claude-code-setup`, which it builds on, ships only as a plugin, so install that from `claude-plugins-official` (§G step 3) or let `setup-advisor` propose it.
- Command names in a manual install: `/implement-plan`, `/marketing-draft`, `/marketing-review` (the plugin install names them `/base:implement-plan`, `/marketing:draft`, `/marketing:review`).
- The two `marketing` network agents keep their inline `mcpServers` blocks (pinned to the same versions as `plugins/marketing/.mcp.json`), so they work in a manual install once `TAVILY_API_KEY` / `DATAFORSEO_USERNAME` / `DATAFORSEO_PASSWORD` are set — inline MCP is ignored only *inside* a plugin. Tool names here are the classic `mcp__tavily__…` / `mcp__dataforseo__…`. Verify with `/mcp`.
- No marketplace step is needed: the copied agents load immediately — check with `/context` (custom agents and their source) or the `@agent-` typeahead.
- **For cloud Code sessions**, run the same copies into the project's `.claude\` (`.claude/`) instead of `~/.claude/` and commit them — cloud sessions load a repo's `.claude/agents|skills|commands` but never `~/.claude` or repo-declared plugins.
- **After any manual install, run `/doctor`** to surface duplicate agent `name:` fields before you rely on the team (verify — duplicate-name detection isn't documented; `/context` lists custom agents with their source).

---

## I. Updating an existing install

Updates flow from the **marketplace source** (the GitHub repo you added), so the new version must have been pushed there first. Each pack's `version` in `plugins/<pack>/.claude-plugin/plugin.json` governs updates: a push **without a version bump never reaches installed users**. Maintainers bump it on every release (and never set `version` in `marketplace.json` too). This release: `base` 1.7.0, `marketing` 1.1.0, `council` 1.1.0, `ecc` 1.1.2.

**Plugin installs (§G):**
```text
# 1. refresh the marketplace manifest from its source
/plugin marketplace update claude-md-packs

# 2. update the packs you already have (or use the /plugin menu -> Update)
/plugin install base@claude-md-packs          # e.g. picks up base 1.7.0 — requirements-gate, /spec, completion-auditor (1.6.0: regression-guard + setup-advisor + the SessionStart hook)

# 3. install any pack added since you set up (new packs do not appear on their own)
/plugin install ecc@claude-md-packs           # per project: 41 agents + 116 skills + 34 commands

# 4. Anthropic's plugins update from their own marketplace
/plugin marketplace update claude-plugins-official
/plugin install claude-code-setup@claude-plugins-official   # first time: add the marketplace first (§G step 3)
```
From a shell: `claude plugin marketplace update claude-md-packs`, then `claude plugin update base@claude-md-packs` (repeat per pack); for Anthropic's plugins, `claude plugin marketplace update claude-plugins-official`, then `claude plugin update claude-code-setup@claude-plugins-official`. Run `/reload-plugins` in an open session to apply.
- **New in base 1.7.0 — completeness:** the `requirements-gate` skill, the `/spec` command and the read-only `completion-auditor` agent; `/implement-plan` now audits every AC against evidence, resumes an existing branch, and has `--strict` and multi-session modes. Copy the optional `plan-gate` hook with the others (§A/§B) and re-copy `templates/guards.*` into projects to get the `no-stubs` and `spec-integrity` steps.
- **New in base 1.6.0 — `setup-advisor`:** after updating, ask "what should I install?" in each active project. It reads what's installed and the project, then proposes additive installs from trusted sources (including `claude-code-setup` if it's missing) and installs only what you tick (§G).
- If prompted to **trust `base`'s new `SessionStart` hook**, accept it, then confirm with `/hooks` (open `/hooks` once to reload if it does not fire). The old per-prompt hook is gone from the plugin; its opt-in snippet is in `.claude/settings.hooks.example.json`.
- Plugin updates do **not** touch the `settings.json` security baseline (§A/§B) or `~/.claude/CLAUDE.md` — re-merge `.claude/settings.json` when a release note says the baseline changed (back up and merge; copying it over the file drops your merged `hooks` block and switches `guard` off), and **re-copy `global/CLAUDE.md`** after each pull (it's a copy, not a link; merge by hand if you've edited yours).
- **claude.ai account:** click **Update** on the `claude-md` marketplace under Customize → Plugins; signed-in Claude Code picks up synced plugins at its next start. If `global/CLAUDE.md` changed, update the pasted block from `claude-ai/personal-preferences.md` too.
- **Projects:** template changes (`templates/guards.*`, `templates/github/regression-guards.yml`, `.claude/settings.json`) don't reach existing projects on their own — diff and merge them in; keep each project's `REGRESSIONS.md` rows.
- Toggle or remove a pack anytime from `/plugin` (or `/plugin marketplace remove`).

**Manual installs (§H):** `git pull` this repo, then re-run the §H copy commands (they overwrite in place). Delete any files removed upstream if you want an exact mirror.

> Tip: to auto-update on startup, set `"autoUpdate": true` on the `claude-md-packs` entry under `extraKnownMarketplaces` in `~/.claude/settings.json` (or `/plugin` → Marketplaces → Enable auto-update). It's opt-in (`templates/user-settings.plugins.json` ships `false`, and the same for its `claude-plugins-official` entry) because it deploys whatever is pushed to the marketplace repo — plugin hooks included — to every machine without review; turn it on knowingly.
> The interactive `/plugin` menu is the reliable path — it surfaces update/install actions directly.

---

## J. Cloud sessions, Remote Control, Cowork

A summary — the full "what each app loads" matrix, handoffs and the daily routine are in [`WORKFLOW.md`](WORKFLOW.md).

- **Cloud Code sessions** (claude.ai/code, the mobile app's Code tab, Desktop's cloud environment, `claude --cloud`, routines) load only what the repo commits: `CLAUDE.md`, `.claude/rules/`, `.claude/agents|skills|commands/`, `.mcp.json`, and `.claude/settings.json` hooks + permission rules (**single-repo sessions only**) — plus the skills enabled on your claude.ai account. They never load `~/.claude` (no global `CLAUDE.md`, user settings, hooks or plugins) and never install plugins that repo settings declare. So commit a copy of this repo's `.claude/settings.json` as the project's `.claude/settings.json` and copies of the agents/skills you need (§C, §H); CI runs the guards regardless. In cloud, start a new session instead of `/clear`; `/plugin` isn't available. Team/Enterprise: server-managed settings can install plugins in cloud sessions. Claude Code Projects (beta): add packs under Project settings → Plugins.
- **Remote Control** is the one way to drive your **full local setup** (global `CLAUDE.md`, packs, hooks, MCP, deny-list) from phone or web: set `"remoteControlAtStartup": true` in `~/.claude/settings.json` (a project-level `true` is ignored), turn on Desktop → Settings → Claude Code → "Enable remote control by default", or run `/remote-control` in a session. Needs a Pro, Max, Team or Enterprise plan with a claude.ai sign-in (not an API key); on Team/Enterprise an Owner enables it first.
- **Handoffs:** CLI → Desktop `/desktop`; Desktop `/resume` lists CLI sessions; Desktop → cloud **Continue in → Claude Code on the Web**; terminal → cloud `claude --cloud "<task>"` (push first — it clones your GitHub remote); cloud → terminal `claude --teleport` or `/tp`.
- **Cowork and chat (the Claude app)** never read `~/.claude` skills or plugins. They get the account layer from Quick start step 8: Instructions for Claude, account plugins (Cowork runs their agents and hooks; chat gets skills and commands) and per-role Projects. The marketing Tavily/DataForSEO servers are local stdio servers — in Cowork they run only while the Desktop app is open; with `marketing` on the account they also start in every signed-in Claude Code session (as `marketing@synced`) unless you turn that off (Quick start step 4). Whether Cowork reads a folder's `CLAUDE.md` is undocumented: ask it to list its instruction sources. The device managed policy (§E) reaches Cowork sessions on that machine.
- **Where user hooks don't run** (cloud sessions, Cowork, chat), the `verify` hook can't hold "done" to green guards. On **Code surfaces** — cloud sessions, or Desktop without the user hooks — use the `/goal` recipe in [`WORKFLOW.md`](WORKFLOW.md), whose condition requires the guard output to appear in the conversation. `/goal` doesn't change the permission mode, so leave Plan first (it needs a mode that can edit). `/goal` isn't available in **chat or Cowork**: there the `regression-guard` skill's `Guards: manual check …` first line is the gate.
