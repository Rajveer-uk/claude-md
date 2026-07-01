# Claude Code Configuration — polyglot, security-vetted

A lean, layered, **stack- and OS-agnostic** configuration for [Claude Code](https://claude.com/claude-code): a global agent team plus per-project memory that adapts to whatever language, framework, package manager, and build tool a project actually uses. The agents install once and are reused across every project; each project gets its own `CLAUDE.md`.

Every file in this repo was produced through a full multi-dimension security audit (prompt-injection, permissions/blast-radius, secret exposure, context leakage, network/exfiltration, supply chain, provenance, and cross-file combination risks) with each finding independently verified.

**Contents:** [This repo vs vanilla Claude Code](#this-repo-vs-vanilla-claude-code) · [What's inside](#whats-inside) · [Design principles](#design-principles) · [The agent team](#the-agent-team-36) · [Skills](#skills) · [Install](#install) · [Security posture](#security-posture) · [Further reading](#further-reading)

## This repo vs vanilla Claude Code

Vanilla Claude Code is a blank, capable agent: you drive every task in one context window, in full prose, with only the built-in tools. This repo turns that into a **standing engineering org** — a security baseline, a 36-agent specialist team, 100+ concrete skill playbooks, and terse/delegation modes — installed once and reused across every project.

### Token utilization

Bodies of agents/skills/commands load **on demand**, not up front — so the comparison isn't "190 extra files in every prompt":

| | Vanilla Claude Code | This repo |
|---|---|---|
| **Always-on overhead** | ~none | **Bounded** — Claude Code caps the agent/skill *listing* to ~1% of the context window (`skillListingBudgetFraction`), so 190+ installed items add a small, fixed cost — not 190 full files |
| **Response prose** | full verbosity | **`/caveman` cuts ~65%** of prose tokens (its design target) while keeping code, errors, and paths verbatim |
| **Large multi-file tasks** | all grows in one window | **delegated to subagents** whose exploration / review / audit runs in *separate* context windows — the main thread stays lean |
| **Generated code** | as written | **`ponytail`** strips it to the minimal version that works |

**Net:** a slightly higher *fixed* baseline (the bounded listing) buys **materially lower token growth on real, multi-step work** — the long sessions where cost actually accumulates. On a big review or refactor, the heavy reading happens inside subagent contexts and the answer comes back terse, instead of inflating the single window you pay for. On a one-line question, the overhead is the bounded listing and nothing else.

> Figures are mechanism-based estimates and documented design targets (e.g. caveman's ~65%), **not audited benchmarks** — real savings depend on task shape.

### Quality improvements

Structural, not cosmetic:

- **Right specialist, least privilege.** 36 role-scoped agents (plus curated stack experts and on-demand `<framework>-expert` generation) instead of one generalist — each with an explicit minimal tool set.
- **A real merge gate.** `code-reviewer` (correctness/security) + `ponytail` (over-engineering) + `security-auditor` run before code lands, catching what a single pass misses.
- **Playbooks, not guesses.** 100+ skills carry concrete patterns, checklists, and anti-patterns (testing/TDD, architecture, per-stack idioms, performance, accessibility), so output follows known-good practice.
- **Better decisions.** The 6-seat `/council` stress-tests ambiguous or high-stakes calls from independent angles before you commit.
- **Safety by default.** Plan-mode-first, a deny-list (no secret reads, no `WebFetch`/`WebSearch`, no destructive Bash) and no-bypass mode mean fewer costly mistakes and zero accidental exfiltration — every file was security-audited with findings independently verified.
- **Proactive by default.** A standing `UserPromptSubmit` hook makes the team delegate and use skills without being asked, scaled to task size.

The payoff is fewer wrong turns, less rework, tighter diffs, and a documented security posture — quality wins that outweigh raw token math on anything beyond a one-liner.


## What's inside

```
.
├── CLAUDE.md                     # project-root template (copy one into each project)
├── setup.md                      # install guide — Windows (PowerShell) + Ubuntu (bash)
├── council-and-network-config.md # council + network connector (setup + security model)
├── .gitignore
├── templates/CLAUDE.package.md   # per-package / per-subsystem template (loads on demand)
├── managed/managed-settings.json # optional admin policy — unbreakable bypass-disable + core secret denies
├── .claude-plugin/
│   └── marketplace.json          # marketplace listing the four plugins below
├── plugins/                      # the team — installed via /plugin (nothing loads until installed)
│   ├── base/                     # MAIN: 23 zero-network engineering agents + /caveman skill + 1 static prompt hook
│   │   ├── .claude-plugin/plugin.json
│   │   ├── agents/*.md
│   │   └── skills/caveman/SKILL.md
│   ├── marketing/                # ADDON: 7 marketing/content agents (incl. the only 2 network researchers)
│   │   ├── .claude-plugin/plugin.json
│   │   ├── .mcp.json             # plugin-scope MCP (Tavily + DataForSEO) — keys from env
│   │   └── agents/*.md
│   ├── council/                  # ADDON: 6 council seats + the /council skill
│   │   ├── .claude-plugin/plugin.json
│   │   ├── agents/*.md
│   │   └── skills/council/SKILL.md
│   └── ecc/                      # ADDON: curated + audited ECC vendoring — 42 agents, 117 skills, 34 commands
│       ├── .claude-plugin/plugin.json
│       ├── agents/*.md · skills/*/SKILL.md · commands/*.md
│       └── ATTRIBUTION.md         # provenance + MIT license + every audit edit
└── .claude/                      # SECURITY BASELINE (classic install — not plugin-able)
    ├── settings.json             # deny-list + plan mode — install at USER scope (~/.claude/)
    └── hooks/                    # optional enforcement / convenience hooks
        ├── guard.ps1  / guard.sh    # block secret-read/egress + over-privileged agent generation
        ├── format.ps1 / format.sh   # PostToolUse: auto-format the edited file (project-local tools)
        └── verify.ps1 / verify.sh    # Stop: run the project's allowlisted checks before finishing
```

## Design principles

- **Stack-agnostic + dynamic.** Universal specialists handle any ecosystem; `project-analyst` detects the stack, `team-configurator` prefers a framework-specific agent and generates a `<framework>-expert` on demand. Curated experts ship for the recurring stacks (Laravel, React+Tailwind/shadcn, Frappe, n8n).
- **Least privilege, zero network by default.** Every agent declares an explicit minimal `tools` list. **The `base` plugin's 23 agents are all air-gapped — zero network tools.** The only two network-capable agents (`content-researcher`, `seo-rank-monitor`) ship in the optional `marketing` addon, so a base-only install has no network surface at all; across the full 36-agent roster, 34 have zero network. Network is opt-in, per-agent, and never inherited (see the connector below).
- **OS-agnostic, layered & lean, self-improving.** Identical files across Windows/macOS/Linux; a small root `CLAUDE.md` points to on-demand per-package files; agents update `CLAUDE.md` when corrected.

## The agent team (36)

**36 agents — 23 in the `base` plugin, 7 in `marketing`, 6 in `council`.**

**Engineering (23) — the `base` plugin.** Planning/review on `opus` (`tech-lead-orchestrator`, `api-architect`, `security-auditor`, `code-reviewer`, `ponytail` — an over-engineering reviewer that lists what to delete); execution/analysis on `sonnet` (`project-analyst`, `team-configurator`, `backend-developer`, `frontend-developer`, `database-expert`, `ui-ux-designer`, `test-engineer`, `debugger`, `devops-troubleshooter`, `performance-optimizer`, `dependency-manager`, `deployment-engineer`, `code-archaeologist`); curated stack experts (`laravel-expert`, `react-tailwind-expert`, `frappe-expert`, `n8n-expert`); docs on `haiku` (`documentation-specialist`). All zero-network. Plus one static, no-network auto-delegation prompt hook (see setup.md).

**Marketing & content (7) — `marketing` plugin.** Draft/strategy, no network: `conversion-copywriter`, `content-writer`, `content-editor` (haiku), `email-campaign-writer`, `growth-strategist` (opus). 🌐 **Network-enabled (read-only):** `content-researcher` (Tavily web search) and `seo-rank-monitor` (DataForSEO SEO metrics) — the **only** two agents with any network access. Install only if you do marketing work: `/plugin install marketing@claude-md-packs`.

**Decision council (6) — `council` plugin.** Pure reasoners (no network, no `Agent` tool): `council-optimist`, `council-pessimist`, `council-out-of-the-box` (opus), `council-skeptic`, `council-pragmatist`, `council-chair` (opus). Bundles the **`/council <question>`** skill (the main session fans the seats out and synthesizes via the chair). Install: `/plugin install council@claude-md-packs`. Pattern adapted from Karpathy's `llm-council` + persona councils.

**ECC extras (42 agents + 117 skills + 34 commands) — optional `ecc` plugin.** Includes 10 ECC agent-engineering knowledge skills (agent architecture, autonomous loops, eval-driven dev); the broader ECC harness/command machinery was trimmed for token economy. A curated, security-audited subset of [ECC](https://github.com/affaan-m/ECC) (MIT): per-language reviewers and build-error resolvers (Go, Rust, Java, Kotlin, Swift, C#, C++, Dart/Flutter, Python, TS, React, Vue, Django, FastAPI, PHP…), plus TDD, refactor, accessibility, type-design, and open-source-release agents, and a large engineering-skills library. **Namespaced separately** so nothing collides with `base`; **pure markdown** (no scripts/hooks/installers); network stays governed by `settings.json`. Install: `/plugin install ecc@claude-md-packs`. Provenance and the exact audit edits: [`plugins/ecc/ATTRIBUTION.md`](plugins/ecc/ATTRIBUTION.md).

## Skills

- **`/caveman [lite|full|ultra]`** (in the `base` plugin) — ultra-terse output mode that cuts ~65% of response tokens while keeping code, errors, and technical facts exact; auto-reverts to full prose for security warnings and irreversible-action confirmations. The prose counterpart to the `ponytail` reviewer (which strips *code* to the minimal version that works).
- **`/council <question>`** (in the `council` plugin) — convene the 6-seat decision council and return a synthesized verdict.
- **117 ECC skills** (in the optional `ecc` plugin) — per-stack patterns, testing/TDD, architecture, performance, accessibility, code-tour, and more; surfaced on demand or via `/ecc:<skill>`.

## Install

Two steps. **Step 1** is the same either way; for **Step 2**, pick plugins (recommended) **or** a manual copy.

### Step 1 — Security baseline (required, both methods)

`settings.json` (the deny-list + plan mode) is *not* plugin-able, so copy it to `~/.claude/` the classic way — full Windows/Ubuntu commands in [`setup.md`](setup.md) §A/§B. The optional hooks and managed policy install the same way. Skip this and the agents still run, but **without** the security guarantees.

### Step 2 · Option A — Plugin marketplace (recommended)

Add the marketplace once, then install the `base` team plus any addons; toggle them anytime from `/plugin`:

```text
/plugin marketplace add .                    # local path to this repo's root (or <owner>/claude-md once pushed)
/plugin install base@claude-md-packs         # MAIN:  23 engineering agents + /caveman skill
/plugin install marketing@claude-md-packs    # addon: 7 marketing/content agents (+ Tavily/DataForSEO)
/plugin install council@claude-md-packs      # addon: 6 council seats + /council skill
/plugin install ecc@claude-md-packs          # addon: 42 ECC agents + 117 skills + 34 commands
```

Nothing under `plugins/` loads until you install it, so a base-only setup stays lean and network-free. The `marketing` addon declares its MCP servers at plugin scope (`plugins/marketing/.mcp.json`) because per-subagent inline `mcpServers` is ignored inside a plugin; set the `TAVILY_API_KEY` / `DATAFORSEO_*` env vars and verify with `/mcp`.

### Step 2 · Option B — Manual install (no plugins)

The agents and skills are plain files — copy them straight into `~/.claude/` and skip the plugin system entirely. Replace `<repo>` with this repo's path.

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

For just the base team, copy from `plugins/base/agents/` instead of `plugins/*/agents/`. The two `marketing` network agents keep their inline `mcpServers` blocks, so they work in a manual install once `TAVILY_API_KEY` / `DATAFORSEO_*` are set (inline MCP is ignored only *inside* a plugin).

## Security posture

- `settings.json` denies reading secrets/credentials across ecosystems, build/vendor output, network-egress + destructive Bash, **and the built-in `WebFetch`/`WebSearch`** (so the only network path is the scoped MCP connector).
- `defaultMode: "plan"` + `disableBypassPermissionsMode: "disable"`; `--dangerously-skip-permissions` is off by design.
- **Scoped network connector (deliberate, documented deviation):** network ships **only in the optional `marketing` plugin** — `content-researcher` (Tavily) and `seo-rank-monitor` (DataForSEO), via the plugin's `.mcp.json` (never inherited). Both are **read-only on files** — no agent has both write and network, and a default core-only install has **no network surface at all**. The secret deny-list, untrusted-fetched-content rule, and per-agent scoping keep the exfiltration surface minimal. Full model + setup in [`council-and-network-config.md`](council-and-network-config.md).
- **The `settings.json` baseline and hooks install the classic way, not as plugins** (a plugin can't set permissions). The baseline is required; `guard` hardens posture, `format`/`verify` are convenience (allowlist-gated); an **optional managed policy** adds unbreakable enforcement. See [`setup.md`](setup.md).

## Further reading

- **[`setup.md`](setup.md)** — full install (Windows + Ubuntu): the `settings.json` baseline, hooks, managed policy, and the plugin marketplace.
- **[`council-and-network-config.md`](council-and-network-config.md)** — the council and the network connector in depth.

## Acknowledgements

The engineering team structure follows patterns popularized by the open-source Claude Code community (the "AI Team" / `awesome-claude-agents`, wshobson/agents, VoltAgent collections). The council adapts Karpathy's `llm-council` and persona-council projects. The `ponytail` over-engineering reviewer and the `/caveman` terse-output skill adapt the ideas of [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) and [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) (both MIT) — concept only, rewritten to this repo's read-only, least-privilege model; no upstream code (hooks, MCP servers, compression scripts) is included. **All agent prompts here are independently written** for a least-privilege, security-reviewed threat model; no third-party agent text is reproduced verbatim.

## License

[MIT](LICENSE).
