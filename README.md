# Claude Code Configuration — polyglot, security-vetted

![License](https://img.shields.io/badge/license-MIT-blue)
![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin%20marketplace-6f42c1)
![Packs](https://img.shields.io/badge/packs-4-1f6feb)
![Agents](https://img.shields.io/badge/agents-79-1f6feb)
![Skills](https://img.shields.io/badge/skills-125-1f6feb)
![Commands](https://img.shields.io/badge/commands-38-1f6feb)
![Security](https://img.shields.io/badge/security-audited-2ea44f)
![OS](https://img.shields.io/badge/OS-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
![Apps](https://img.shields.io/badge/apps-CLI%20%7C%20Desktop%20%7C%20IDE%20%7C%20claude.ai-lightgrey)

A lean, layered, **stack- and OS-agnostic** configuration for [Claude Code](https://claude.com/claude-code) and the Claude apps: a global agent team plus per-project memory that adapts to whatever language, framework, package manager, and build tool a project actually uses. The agents install once and are reused across every project; each project gets its own `CLAUDE.md` and a fix-once ledger; the same core rules reach the Desktop app, VS Code, cloud sessions, chat and Cowork.

Every file in this repo was produced through a full multi-dimension security audit (prompt-injection, permissions/blast-radius, secret exposure, context leakage, network/exfiltration, supply chain, provenance, and cross-file combination risks) with each finding independently verified.

**Contents:** [This repo vs vanilla Claude Code](#this-repo-vs-vanilla-claude-code) · [Works across every Claude app](#works-across-every-claude-app) · [Fix once, never twice](#fix-once-never-twice) · [What's inside](#whats-inside) · [Design principles](#design-principles) · [The agent team](#the-agent-team-37) · [Skills](#skills) · [Install](#install) · [Security posture](#security-posture) · [Further reading](#further-reading)

## This repo vs vanilla Claude Code

Vanilla Claude Code is a blank, capable agent: you drive every task in one context window, in full prose, with only the built-in tools. This repo turns that into a **standing engineering org** — a security baseline, a 37-agent specialist team, 100+ concrete skill playbooks, a fix-once guard system, and terse/delegation modes — installed once and reused across every project.

### Token utilization

Bodies of agents/skills/commands load **on demand**, not up front — so the comparison isn't "240 extra files in every prompt". What every session does pay is each installed pack's **listing** (the name and description of every agent and skill Claude can invoke), measured with `claude plugin details <pack>`:

| | Vanilla Claude Code | This repo |
|---|---|---|
| **Always-on overhead** | ~none | **Measured per pack:** `base` ≈2.9k tokens · `marketing` ≈0.86k (≈0.7k in context) · `council` ≈0.5k · `ecc` ≈15.4k — so `ecc` goes on only in projects that need it. Commands marked `disable-model-invocation` (`/marketing:draft`, `/marketing:review`) add nothing until you run them |
| **Working agreement** | — | One static `SessionStart` line at startup, `/clear` and compaction — not re-sent with every prompt |
| **Response prose** | full verbosity | **`/caveman` cuts ~65%** of prose tokens (its design target, on chat-style prose; an independent test on agentic coding measured ~8.5% fewer output tokens with no quality change — JetBrains, 2026-07) while keeping code, errors, and paths verbatim; built-in `outputStyle: "Concise"` is a lighter option |
| **Large multi-file tasks** | all grows in one window | **delegated to subagents** only when it pays (10+ files to read, 3+ independent parts, an independent review): their exploration / review / audit runs in *separate* context windows and only a short result returns — the main thread stays lean |
| **Small or sequential tasks** | inline | **inline too** — no subagent overhead where it doesn't pay |
| **Generated code** | as written | **`ponytail`** strips it to the minimal version that works |
| **Remembering past fixes** | re-explained in chat | **guards** — ~0 tokens while green; rows are read only for the area being touched |

**Net:** a measured *fixed* baseline (≈2.9k tokens for `base`) buys **materially lower main-context growth on real, multi-step work** — the long sessions where cost actually accumulates. It is not free in total: a subagent carries its own system prompt, `CLAUDE.md` and tool overhead, and Anthropic's published figures are **≈4× the tokens of a chat for an agent and ≈15× for its multi-agent research system** (agent teams run ≈7× a standard session when teammates are in plan mode). That is why the base rules keep small, sequential and same-file work inline and delegate only work that is large, independent, or verbose enough to be worth isolating.

> Figures are mechanism-based estimates, measured always-on costs and documented design targets (e.g. caveman's ~65%), **not audited benchmarks** — real savings depend on task shape.

### Worked example — reviewing a 6-file change

*Task: review a ~1,500-line change across 6 files, apply fixes, then ~10 follow-up turns.* Modeled from **real constants** (caveman's ~65% target, the measured ≈2.9k-token `base` always-on cost, the ~2.7K-token median skill body measured in this repo) with the task assumptions stated — **not an instrumented benchmark**.

| Cost driver | Vanilla Claude Code | This repo | Why |
|---|---|---|---|
| **Reading the change** (~30K tokens) | lands in the one window and is **re-sent every turn** → ~300K carried over ~10 turns | read inside the **`code-reviewer` subagent**; only a ~1K findings summary returns → ~10K carried | delegation keeps heavy reads out of the persistent context |
| **Review + fix prose** (~8K) | full verbosity | **~2.8K** under `/caveman` | ~65% prose reduction |
| **Always-on overhead** | none | **≈2.9k** (`base`, measured) | `claude plugin details base` |

**Result for this scenario: ≈80–85% less main-context token growth and ≈65% smaller responses**, for a fixed listing cost and a *similar one-shot read* (the subagent still reads the code once — it just doesn't carry it forward across turns). The subagent's own overhead makes the *total* billed tokens higher than the main-context figure suggests, so the saving is in how much context each later turn re-sends. It scales with session length and baseline verbosity; a **one-line question** stays inline and sees mostly the ~65% shorter answer plus the fixed listing.

### Quality improvements

Structural, not cosmetic:

- **Right specialist, least privilege.** 37 role-scoped agents (plus curated stack experts and on-demand `<framework>-expert` generation) instead of one generalist — each with an explicit minimal tool set.
- **A real merge gate.** `code-reviewer` (correctness/maintainability) + `ponytail` (over-engineering) + `security-auditor` (vulnerabilities) run before code lands, catching what a single pass misses.
- **Playbooks, not guesses.** 100+ skills carry concrete patterns, checklists, and anti-patterns (testing/TDD, architecture, per-stack idioms, performance, accessibility), so output follows known-good practice.
- **Better decisions.** The 6-seat `/council` stress-tests ambiguous or high-stakes calls from independent angles before you commit.
- **Safety by default.** Plan-mode-first, a deny-list (no secret reads, no `WebFetch`/`WebSearch`, no destructive Bash or PowerShell), an ask list for outbound actions and no-bypass mode mean fewer costly mistakes and no casual exfiltration path — every file was security-audited with findings independently verified.
- **Proactive by default, delegation when it pays.** A static `SessionStart` hook (startup, `/clear`, compaction) makes the team use skills without being asked and sets balanced delegation: small, sequential or same-file work inline (except specialist-owned deliverables such as marketing copy, which always go to their guarded agent); 10+ files, 3+ independent parts or an independent review → parallel subagents in one message, each given only the context it needs plus the matching ledger rows.
- **Fixed once, stays fixed.** Every fix or correction leaves a guard and a ledger row, and new work is checked against all of them before it's called done (see [Fix once, never twice](#fix-once-never-twice)).

The payoff is fewer wrong turns, less rework, tighter diffs, and a documented security posture — quality wins that outweigh raw token math on anything beyond a one-liner.

## Works across every Claude app

Set each layer up once; every app picks up the layers it can read — no per-app reconfiguration:

| Layer | Set once | Reaches |
|---|---|---|
| **Machine** `~/.claude` | `settings.json` baseline, a copy of `global/CLAUDE.md`, plugins, hooks | CLI, **Desktop app Code tab** (local + SSH), VS Code, JetBrains — one config per machine |
| **Cloud environment** (Setup script) | `templates/cloud-setup.sh`: the baseline (no Plan default), a copy of `global/CLAUDE.md` and the `base` plugin, installed into each new cloud container | every cloud Code session in any repo — web, the phone app (a continued session keeps it) and Desktop's cloud environment |
| **Repo** (committed) | `CLAUDE.md`, `REGRESSIONS.md`, `.claude/guards.*`, `.claude/settings.json`, CI, `.claude/agents/` + `.claude/skills/` copies | every surface, including cloud Code sessions (web, mobile, Desktop cloud) |
| **claude.ai account** | Instructions for Claude (`claude-ai/personal-preferences.md`); account plugins `base`, `council`, plus `marketing` only where its Tavily/DataForSEO servers are acceptable in every signed-in session | chat (web + Desktop), Cowork, and synced into **every** signed-in Claude Code session as `<name>@synced`, MCP servers included |
| **claude.ai Projects** | one per role (`claude-ai/project-*.md`) + knowledge files | chat |

**Remote Control** drives your full local setup from phone or web. Desktop-only machines install the packs through `templates/user-settings.plugins.json` — no terminal needed. Per-app caveats, handoffs and the daily loop: [`WORKFLOW.md`](WORKFLOW.md). Install: [`setup.md`](setup.md) → *Quick start*.

## Fix once, never twice

Every bug fix or owner correction — code, marketing copy, ops, docs, strategy — leaves a guard behind, and new work is verified against all earlier fixes:

- **Ledger** — `REGRESSIONS.md` at the project root, one row per fix: `| ID | Area | Rule (must stay true) | Guard | Added |`. The guard is the strongest available: `test:` > `check:` > `review:`. Rows are never deleted.
- **Runner** — `.claude/guards.sh` / `.ps1` runs every guard (tests, lint, banned-phrase content lint, ledger integrity). Before "done", Claude runs the full set once and reports `Guards: <command> → exit 0, <summary>; R-00x ✓` on the first line — or `Guards: RED — <step>: <reason>` and does not claim done.
- **Procedure** — the `regression-guard` skill (`base`): grep the rows for the area, reproduce, fix the code or content (never the test), add the guard and the row, pass matching rows into every subagent hand-off.
- **Enforcement** — the `verify` Stop hook (allowlisted projects), the CI template (zero model tokens), and the `guard` hook, which asks only when an edit would change or remove an existing ledger row, a guard runner or a banned phrase (appends to the ledger or banned list pass). Wording corrections become lines in `brand/banned-phrases.txt`; voice corrections go into `brand/voice.md`.
- **In chat** (no shell) the ledger is a Project knowledge file, and Claude outputs the new row for you to paste.
- **Complete, not just green** — for incomplete prompts, issues or review comments: the `requirements-gate` skill turns a multi-step ask into `AC1…ACn` (asked + implied work), asks with a pop-up only where readings change the work, and ends with an AC → evidence table (`Requirements: n/m met` is the report's second line). `/spec` → `/implement-plan` adds a written spec, a resume-safe run and the read-only `completion-auditor`; the `no-stubs` and `spec-integrity` guard steps and the optional `plan-gate` Stop hook make "looks done" fail mechanically. Which flow when: [`WORKFLOW.md`](WORKFLOW.md#4-daily-loop--development).

This repo guards itself the same way: its own `REGRESSIONS.md`, `.claude/guards.sh` and `.github/workflows/guards.yml`. Where each piece is enforced: [`WORKFLOW.md`](WORKFLOW.md#9-where-fix-once-is-enforced).

## What's inside

```
.
├── CLAUDE.md                     # project-root template (copy one into each project)
├── REGRESSIONS.md                # this repo's own fix-once ledger
├── WORKFLOW.md                   # one daily workflow across every Claude app + where fix-once is enforced
├── setup.md                      # install guide — Quick start (Desktop + every app), Windows (PowerShell) + Ubuntu (bash)
├── council-and-network-config.md # council + network connector (setup + security model)
├── .gitignore
├── global/CLAUDE.md              # machine-wide working agreement → copy (never symlink) to ~/.claude/CLAUDE.md
├── claude-ai/                    # claude.ai account layer (chat, Cowork)
│   ├── personal-preferences.md   # paste into Settings → General → Instructions for Claude
│   ├── project-marketing.md      # claude.ai Project instructions — marketing
│   └── project-generic.md        # claude.ai Project instructions — ops / docs / strategy / other roles
├── scripts/
│   └── package-claude-ai.sh/.ps1 # validate + zip skills for upload (only where plugins don't reach)
├── templates/
│   ├── CLAUDE.package.md         # per-package / per-subsystem template (loads on demand)
│   ├── REGRESSIONS.md            # fix-once ledger template
│   ├── guards.sh / guards.ps1    # committed guard runner → <project>/.claude/
│   ├── checks.sh / checks.cmd    # local-only wrapper the verify hook runs (gitignored)
│   ├── user-settings.plugins.json # Desktop-only machines: marketplace + base via ~/.claude/settings.json
│   ├── sandbox-settings.json     # opt-in OS sandbox (Linux/macOS/WSL2)
│   ├── rules/content.md          # optional path-scoped content rules → <project>/.claude/rules/
│   ├── banned-phrases.txt        # → <project>/brand/banned-phrases.txt (content-lint)
│   ├── brand-voice.md            # → <project>/brand/voice.md (brand-voice skill)
│   ├── PROGRESS.md               # optional state file for multi-session work
│   └── github/regression-guards.yml # CI: guards on every PR/push + weekly, zero model tokens
├── managed/managed-settings.json # optional admin policy — unbreakable bypass-disable + core secret denies
├── .github/workflows/guards.yml  # this repo's own CI guard run
├── .claude-plugin/
│   └── marketplace.json          # marketplace listing the four plugins below
├── plugins/                      # the team — installed via /plugin (nothing loads until installed)
│   ├── base/                     # MAIN: 25 zero-network engineering agents + 6 skills + 2 commands + 1 SessionStart hook
│   │   ├── .claude-plugin/plugin.json
│   │   ├── agents/*.md
│   │   ├── commands/implement-plan.md, spec.md
│   │   ├── hooks/hooks.json      # one static SessionStart line (startup, /clear, compaction)
│   │   ├── skills/*/SKILL.md     # caveman, secure-code-reviewer, work-quality-checker, regression-guard, setup-advisor, requirements-gate (+ references/)
│   │   └── evals/                # `claude plugin eval` suite: skill triggering, routing, no over-delegation
│   ├── marketing/                # ADDON: 7 marketing/content agents (incl. the only 2 network researchers) + 2 skills + 2 commands
│   │   ├── .claude-plugin/plugin.json
│   │   ├── .mcp.json             # plugin-scope MCP (Tavily + DataForSEO, pinned) — keys from env
│   │   ├── agents/*.md
│   │   ├── skills/*/SKILL.md     # ai-writing-tells, brand-voice
│   │   ├── commands/*.md         # /marketing:draft, /marketing:review
│   │   └── evals/                # banned phrases, writer routing, researcher reaches (mocked) Tavily
│   ├── council/                  # ADDON: 6 council seats + the /council skill
│   │   ├── .claude-plugin/plugin.json
│   │   ├── agents/*.md
│   │   ├── skills/council/SKILL.md
│   │   └── evals/                # seats fan out, chair runs last
│   └── ecc/                      # ADDON (per project): curated + audited ECC vendoring — 41 agents, 116 skills, 34 commands
│       ├── .claude-plugin/plugin.json
│       ├── agents/*.md · skills/*/SKILL.md · commands/*.md
│       └── ATTRIBUTION.md         # provenance + MIT license + every audit edit
└── .claude/                      # SECURITY BASELINE (classic install — not plugin-able)
    ├── settings.json             # deny-list + ask list + plan mode — install at USER scope (~/.claude/)
    ├── settings.hooks.example.json # hook registrations to merge (+ opt-in per-prompt delegation directive)
    ├── guards.sh                 # this repo's own guard runner
    └── hooks/                    # optional enforcement / convenience hooks
        ├── guard.ps1  / guard.sh    # block secret-read/egress + over-privileged agent generation; ask before guard/ledger edits
        ├── format.ps1 / format.sh   # PostToolUse: auto-format the edited file (project-local tools)
        └── verify.ps1 / verify.sh    # Stop: run the project's allowlisted guards before finishing
```

## Design principles

- **Stack-agnostic + dynamic.** Universal specialists handle any ecosystem; `project-analyst` detects the stack, `team-configurator` prefers a framework-specific agent and generates a `<framework>-expert` on demand. Curated experts ship for the recurring stacks (Laravel, React+Tailwind/shadcn, Frappe, n8n).
- **Least privilege, zero network by default.** Every agent declares an explicit minimal `tools` list. **The `base` plugin's 25 agents are all air-gapped — zero network tools.** The only two network-capable agents (`content-researcher`, `seo-rank-monitor`) ship in the optional `marketing` addon, so a base-only install has no network surface at all — as long as `marketing` is neither installed locally nor enabled on your claude.ai account (account plugins sync into every signed-in Claude Code session); across the full 38-agent roster, 36 have zero network. Network is opt-in, per-agent, and never inherited (see the connector below).
- **OS-agnostic, app-agnostic, layered & lean, self-improving.** Identical files across Windows/macOS/Linux and across the Claude apps; a small root `CLAUDE.md` points to on-demand per-package files; HTML-comment maintainer notes cost zero tokens; corrections become guards and ledger rows; a project-specific lesson becomes one line in that project's (or area's) `CLAUDE.md`, and a general lesson a proposed one-line diff to `~/.claude/CLAUDE.md`, applied only with your approval.

## The agent team (38)

**38 agents — 25 in the `base` plugin, 7 in `marketing`, 6 in `council`** (plus 41 in the optional `ecc` pack).

**Engineering (25) — the `base` plugin.** Planning/deep review on `opus` (`tech-lead-orchestrator`, `api-architect`, `security-auditor`, `ponytail` — an over-engineering reviewer that lists what to delete); execution/analysis on `sonnet` (`code-reviewer`, `completion-auditor` — a read-only check that every AC has evidence, `backend-developer`, `frontend-developer`, `database-expert`, `ui-ux-designer`, `test-engineer`, `debugger`, `devops-troubleshooter`, `performance-optimizer`, `deployment-engineer`, `code-archaeologist`); curated stack experts (`laravel-expert`, `react-tailwind-expert`, `frappe-expert`, `n8n-expert`); fast/cheap on `haiku` (`project-analyst`, `team-configurator`, `dependency-manager`, `ops-triage` — read-only ops triage for logs/disk/queues/containers — and `documentation-specialist`). All zero-network. Plus one static, no-network `SessionStart` working-agreement hook (see setup.md §G).

**Marketing & content (7) — `marketing` plugin.** Draft/strategy, no network: `conversion-copywriter`, `content-writer`, `content-editor` (haiku), `email-campaign-writer`, `growth-strategist` (opus). 🌐 **Network-enabled (read-only):** `content-researcher` (Tavily web search) and `seo-rank-monitor` (DataForSEO SEO metrics) — the **only** two agents with any network access. Ships the `ai-writing-tells` and `brand-voice` skills and the ledger-aware `/marketing:draft` and `/marketing:review` commands. Install only if you do marketing work: `/plugin install marketing@claude-md-packs`.

**Decision council (6) — `council` plugin.** Pure reasoners (no network, no `Agent` tool): `council-optimist`, `council-pessimist`, `council-out-of-the-box` (opus), `council-skeptic`, `council-pragmatist`, `council-chair` (opus). Bundles the **`/council <question>`** skill (the main session fans the seats out and synthesizes via the chair). The seats start without `CLAUDE.md` and get their context — question, constraints, matching ledger rows — from the skill; in chat, where sub-agents aren't available, the skill runs a single-model fallback. Install: `/plugin install council@claude-md-packs`. Pattern adapted from Karpathy's `llm-council` + persona councils.

**ECC extras (41 agents + 116 skills + 34 commands) — optional `ecc` plugin.** Includes 10 ECC agent-engineering knowledge skills (agent architecture, autonomous loops, eval-driven dev); the broader ECC harness/command machinery was trimmed for token economy. A curated, security-audited subset of [ECC](https://github.com/affaan-m/ECC) (MIT): per-language reviewers and build-error resolvers (Go, Rust, Java, Kotlin, Swift, C#, C++, Dart/Flutter, Python, TS, React, Vue, Django, FastAPI, PHP…), plus TDD, refactor, accessibility, type-design, and open-source-release agents, and a large engineering-skills library. **Namespaced separately** so nothing collides with `base`; **pure markdown** (no scripts/hooks/installers); network stays governed by `settings.json`. It adds ≈15k always-on tokens, so install it **per project**: `claude plugin install ecc@claude-md-packs --scope local`. Provenance and the exact audit edits: [`plugins/ecc/ATTRIBUTION.md`](plugins/ecc/ATTRIBUTION.md).

## Skills

- **`/caveman [lite|full|ultra]`** (in the `base` plugin) — ultra-terse output mode that cuts ~65% of response tokens (design target, chat-style prose; ~8.5% measured on agentic coding) while keeping code, errors, and technical facts exact; auto-reverts to full prose for security warnings and irreversible-action confirmations. The prose counterpart to the `ponytail` reviewer (which strips *code* to the minimal version that works).
- **`secure-code-reviewer`** (in the `base` plugin) — OWASP-focused defensive audit of code you paste or point at: severity-triaged report (Critical→Low) with secure-code fixes; explains risk without generating exploit payloads. Complements the `security-auditor` agent — the agent does delegated repo-wide scans, the skill audits inline what you show it.
- **`work-quality-checker`** (in the `base` plugin) — ruthless pre-send QA for emails, decks, concept notes, proposals, and scripts: logic-gap audit, top-3 sentence rewrites, the three toughest boss/client questions with suggested answers, and a binary "Ship it" / "Fix these 2 things first" verdict. Also turns raw meeting notes into a decisions/owners/deadlines dashboard.
- **`regression-guard`** (in the `base` plugin) — the fix-once procedure for any role: grep `REGRESSIONS.md` for the area before editing, turn every bug fix or correction into a guard (test > check > review) plus one ledger row, run the full guard set before "done" and lead the report with the `Guards:` evidence line. Short checklist; code, content and chat references load only when needed.
- **`setup-advisor`** (in the `base` plugin) — "what should I install?" / "audit my Claude setup": inventories what's installed (`claude plugin list`, always-on cost via `claude plugin details`), reads the project's `CLAUDE.md`, ledger area tags, manifests and content dirs, merges Anthropic's `claude-code-setup` recommender when present (and proposes it when not), then reports the top 3–5 picks with evidence, always-on cost and the exact install command, and asks via a multi-select pop-up. Trusted sources only (these packs, Anthropic-authored plugins in `claude-plugins-official`, your account skills); additive only, with duplicates listed as optional cleanup for you to decide; read-only and network-free until you approve.
- **`/implement-plan <plan-file…>`** (command in the `base` plugin) — execute a detailed plan file end-to-end: new branch off the current one, one subagent per plan item routed to the pack agent's declared model (subagents never run on fable — only the orchestrator), statuses marked done in the plan file itself, the full guard run and review gate (`code-reviewer` + `ponytail`, `security-auditor` when warranted), one commit per item, one push at the end. It also builds the AC list and checks every AC maps to a task before branching, resumes an existing branch and skips done items, lets subagents return `NEEDS_CONTEXT` so the orchestrator asks you, proves every AC with evidence through `completion-auditor` before the reviewers, escalates to you after 2 unclean rounds, and reports `Requirements: n/m met` on line 2. `--strict` adds a per-task done-criteria contract for high-stakes work; a `specs/<slug>.features.json` file switches it to one-feature-per-session mode.
- **`/spec <request>`** (command in the `base` plugin) — turns a vague or incomplete request into `specs/<slug>.md` (from `templates/SPEC.md`): explores the repo, interviews you with batched pop-ups, writes requirements `AC1…` with how each is verified, out of scope, files and interfaces, an end-to-end check and a task plan in which every task covers ACs. No code edits; hand-off is `/implement-plan specs/<slug>.md` in a fresh session.
- **`requirements-gate`** (in the `base` plugin) — the everyday version for any multi-step prompt, issue or review comment: lists the ask as `AC1…` including implied work (tests, other callers, docs, config, paired files), asks only where readings change the work, and before "done" maps every AC to evidence; an AC not met means not done.
- **`ai-writing-tells`** (in the `marketing` plugin) — the shared banned-patterns list the writers and editor apply to every draft.
- **`brand-voice`** (in the `marketing` plugin) — applies the project's `brand/voice.md` to drafts and reviews, and logs each voice correction so it holds for every writer.
- **`/marketing:draft <brief>`** (command in the `marketing` plugin) — draft copy end-to-end: matching `mkt/` ledger rows, parallel research where facts are needed, the right writer, an editor pass, the content-lint guard run and a quality verdict.
- **`/marketing:review <file>`** (command in the `marketing` plugin) — review a file before it ships: editor pass, ledger rows, banned phrases, unsupported claims, open `[VERIFY]` items, verdict.
- **`/council <question>`** (in the `council` plugin) — convene the 6-seat decision council and return a synthesized verdict.
- **116 ECC skills** (in the optional `ecc` plugin) — per-stack patterns, testing/TDD, architecture, performance, accessibility, code-tour, and more; surfaced on demand or via `/ecc:<skill>`.

## Install

Three steps on a machine, one per project, one per claude.ai account — the full, ordered list (with Windows and Ubuntu commands) is [`setup.md`](setup.md) → **Quick start**. **Step 1** is the same either way; for **Step 2**, pick plugins (recommended) **or** a manual copy.

**One command** (steps 1 and 2 plus the plugins; safe to re-run; merges `settings.json` add-only with a backup): `bash <repo>/scripts/install-user-config.sh --packs base,council --hooks guard` · Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File <repo>\scripts\install-user-config.ps1 -Packs base,council -Hooks guard`. **Cloud sessions (web + phone):** paste `templates/cloud-setup.sh` into the cloud environment's Setup script ([`setup.md`](setup.md) Quick start step 10).

### Step 1 — Security baseline + global memory (required, both methods)

`settings.json` (the deny-list, ask list + plan mode) is *not* plugin-able, so copy it to `~/.claude/` the classic way — full Windows/Ubuntu commands in [`setup.md`](setup.md) §A/§B. Copy (never symlink) `global/CLAUDE.md` to `~/.claude/CLAUDE.md` for the machine-wide working agreement. The optional hooks and managed policy install the same way. Skip this and the agents still run, but **without** the security guarantees.

### Step 2 · Option A — Plugin marketplace (recommended)

Add the marketplace once, then install the `base` team plus any addons; toggle them anytime from `/plugin`:

```text
/plugin marketplace add .                    # local path to this repo's root (or <owner>/claude-md once pushed)
/plugin install base@claude-md-packs         # MAIN:  25 engineering agents + 6 skills + /implement-plan + /spec
/plugin install marketing@claude-md-packs    # addon: 7 marketing/content agents (+ Tavily/DataForSEO) + 2 skills + 2 commands
/plugin install council@claude-md-packs      # addon: 6 council seats + /council skill
/plugin install ecc@claude-md-packs          # addon, per project: 41 ECC agents + 116 skills + 34 commands
/plugin marketplace add anthropics/claude-plugins-official   # Anthropic's official marketplace (skip if already listed)
/plugin install claude-code-setup@claude-plugins-official    # Anthropic's read-only setup recommender; setup-advisor builds on it
```

From a shell: `claude plugin marketplace add <owner>/claude-md`, then `claude plugin install base@claude-md-packs`. **Claude Desktop:** the Code tab's **+ → Plugins** installs from a known marketplace; on a machine without a terminal, merge `templates/user-settings.plugins.json` into `~/.claude/settings.json` and restart.

Nothing under `plugins/` loads until you install it (or enable it on your claude.ai account, which syncs it into every signed-in Claude Code session as `<name>@synced`), so a base-only setup stays lean and network-free. The `marketing` addon declares its MCP servers at plugin scope (`plugins/marketing/.mcp.json`) because per-subagent inline `mcpServers` is ignored inside a plugin; set the `TAVILY_API_KEY` / `DATAFORSEO_*` env vars (Desktop: its Local environment editor) and verify with `/mcp`.

### Step 2 · Option B — Manual install (no plugins)

The agents, skills and commands are plain files — copy them straight into `~/.claude/` and skip the plugin system entirely. Replace `<repo>` with this repo's path.

**Windows (PowerShell)**
```powershell
$repo = "<repo>"; $dest = "$env:USERPROFILE\.claude"
New-Item -ItemType Directory -Force "$dest\agents","$dest\skills","$dest\commands" | Out-Null
Copy-Item "$repo\plugins\*\agents\*.md"          "$dest\agents\" -Force            # all 79 across packs (use \base\ for just the 25; ecc's skills/commands are NOT copied here)
Copy-Item "$repo\plugins\base\skills\caveman"                "$dest\skills\" -Recurse -Force
Copy-Item "$repo\plugins\base\skills\secure-code-reviewer"   "$dest\skills\" -Recurse -Force
Copy-Item "$repo\plugins\base\skills\work-quality-checker"   "$dest\skills\" -Recurse -Force
Copy-Item "$repo\plugins\base\skills\regression-guard"       "$dest\skills\" -Recurse -Force
Copy-Item "$repo\plugins\base\skills\setup-advisor"          "$dest\skills\" -Recurse -Force
Copy-Item "$repo\plugins\base\skills\requirements-gate"      "$dest\skills\" -Recurse -Force
Copy-Item "$repo\plugins\council\skills\council"             "$dest\skills\" -Recurse -Force
Copy-Item "$repo\plugins\marketing\skills\ai-writing-tells"  "$dest\skills\" -Recurse -Force
Copy-Item "$repo\plugins\marketing\skills\brand-voice"       "$dest\skills\" -Recurse -Force
Copy-Item "$repo\plugins\base\commands\implement-plan.md"   "$dest\commands\" -Force
Copy-Item "$repo\plugins\base\commands\spec.md"             "$dest\commands\" -Force
Copy-Item "$repo\plugins\marketing\commands\draft.md"       "$dest\commands\marketing-draft.md"  -Force
Copy-Item "$repo\plugins\marketing\commands\review.md"      "$dest\commands\marketing-review.md" -Force
```

**Ubuntu / macOS (bash)**
```bash
repo="<repo>"; dest="$HOME/.claude"
mkdir -p "$dest/agents" "$dest/skills" "$dest/commands"
cp "$repo"/plugins/*/agents/*.md "$dest/agents/"                  # all 79 across packs (use plugins/base/ for just the 25; ecc's skills/commands are NOT copied here)
for s in base/skills/caveman base/skills/secure-code-reviewer base/skills/work-quality-checker base/skills/regression-guard \
         base/skills/setup-advisor base/skills/requirements-gate council/skills/council marketing/skills/ai-writing-tells marketing/skills/brand-voice; do
  cp -r "$repo/plugins/$s" "$dest/skills/"
done
cp "$repo/plugins/base/commands/implement-plan.md" "$dest/commands/"
cp "$repo/plugins/base/commands/spec.md"           "$dest/commands/"
cp "$repo/plugins/marketing/commands/draft.md"     "$dest/commands/marketing-draft.md"
cp "$repo/plugins/marketing/commands/review.md"    "$dest/commands/marketing-review.md"
```

For just the base team, copy from `plugins/base/agents/` instead of `plugins/*/agents/`. The two `marketing` network agents keep their inline `mcpServers` blocks, so they work in a manual install once `TAVILY_API_KEY` / `DATAFORSEO_*` are set (inline MCP is ignored only *inside* a plugin). Marketing's commands are renamed on copy (`/marketing-draft`, `/marketing-review`) so they can't shadow another `/draft` or `/review`.

### Step 3 — Per project and per claude.ai account

Per project: `CLAUDE.md`, `REGRESSIONS.md`, the guard runners, the CI template and `.claude/settings.json` for cloud sessions ([`setup.md`](setup.md) §C). Per claude.ai account: paste `claude-ai/personal-preferences.md` into Instructions for Claude, add `<owner>/claude-md` as a plugin marketplace (install `base` and `council`; add `marketing` only where its Tavily/DataForSEO servers are acceptable in every signed-in Claude Code session, since account plugins sync there; never `ecc`) and create one Project per role (setup.md Quick start step 8).

## Security posture

- `settings.json` denies reading secrets/credentials across ecosystems — including **home-anchored** rules (`~/.ssh/**`, `~/.aws/**`, …), since a `**/` rule only matches under the working directory — build/vendor output, network-egress + destructive shell commands **for both the `Bash` and the Windows `PowerShell` tool**, **and the built-in `WebFetch`/`WebSearch`**, so the sanctioned network path for agents is the scoped MCP connector. Outbound and publish actions (`ssh`, `rsync`, `gh release`, `npm publish`, `docker push`, …) are on an **ask** list that prompts even in auto mode.
- `defaultMode: "plan"` + `disableBypassPermissionsMode: "disable"` + `useAutoModeDuringPlan: false` (planning stays human-gated); `--dangerously-skip-permissions` is off by design.
- **Shell deny rules are a speed-bump, not a wall:** they match command text, so absolute paths (`/usr/bin/curl`), `sh -c`, interpreters and `npx` can get past them. Backstops: plan mode + per-command approval, the `guard` hook (also covers `PowerShell` and `Monitor`, and interpreter reads of secret paths), and the opt-in OS sandbox (`templates/sandbox-settings.json`; Linux/macOS/WSL2).
- **Scoped network connector (deliberate, documented deviation):** network ships **only in the optional `marketing` plugin** — `content-researcher` (Tavily) and `seo-rank-monitor` (DataForSEO), via the plugin's `.mcp.json` (never inherited). Under a plugin install their tools are **plugin-scoped** (`mcp__plugin_marketing_tavily__tavily_search`, `mcp__plugin_marketing_dataforseo__…`); the agents list those plus the classic `mcp__tavily__…` / `mcp__dataforseo__…` names for a manual install. Both are **read-only on files** — no agent has both write and network, and a default core-only install has **no network surface at all** (unless `marketing` is enabled on your claude.ai account, which syncs it in; see the next bullet). Every pack agent has an explicit `tools:` list, so no other subagent can call these tools; the main session can see them, so keep them on "ask". The secret deny-list, untrusted-fetched-content rule, and per-agent scoping keep the exfiltration surface minimal. Full model + setup in [`council-and-network-config.md`](council-and-network-config.md).
- **Caveat — claude.ai connectors:** when you sign in to Claude Code with a claude.ai account, connectors you added on claude.ai (and MCP servers from plugins enabled on the account) reach the **main session** too. They're outside this repo's scoping; pack subagents don't get them. Review with `/mcp`; block with `deniedMcpServers` or `disableClaudeAiConnectors`.
- **Account plugins sync everywhere.** A plugin enabled on your claude.ai account loads in **every** signed-in Claude Code session as `<name>@synced`, MCP servers included. Put `base` and `council` on the account; add `marketing` only if its Tavily/DataForSEO servers are acceptable in every session. To opt one machine out, set `"marketing@synced": false` under `enabledPlugins` in `~/.claude/settings.json` or run `claude plugin disable marketing@synced`, then confirm with `claude plugin list`.
- **The `settings.json` baseline and hooks install the classic way, not as plugins** (a plugin can't set permissions). The baseline is required; `guard` hardens posture, `format`/`verify` are convenience (allowlist-gated); an **optional managed policy** adds unbreakable enforcement — the only layer a cloned repo's `.claude/settings.json` can't override. For single-repo cloud sessions, commit a copy of `.claude/settings.json` as the project's `.claude/settings.json` to carry the baseline into the repo. See [`setup.md`](setup.md).

## Further reading

- **[`setup.md`](setup.md)** — full install: the Quick start for Claude Desktop and every other app, then Windows + Ubuntu detail — the `settings.json` baseline, global memory, hooks, managed policy, per-project files, the plugin marketplace, updating, and cloud/Remote Control/Cowork.
- **[`WORKFLOW.md`](WORKFLOW.md)** — the day-to-day playbook across apps: which app for what, checks, daily loops per role, token rules, where fix-once is enforced, troubleshooting.
- **[`council-and-network-config.md`](council-and-network-config.md)** — the council and the network connector in depth.

## Acknowledgements

The engineering team structure follows patterns popularized by the open-source Claude Code community (the "AI Team" / `awesome-claude-agents`, wshobson/agents, VoltAgent collections). The council adapts Karpathy's `llm-council` and persona-council projects. The `ponytail` over-engineering reviewer and the `/caveman` terse-output skill adapt the ideas of [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) and [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) (both MIT) — concept only, rewritten to this repo's read-only, least-privilege model; no upstream code (hooks, MCP servers, compression scripts) is included. **All agent prompts here are independently written** for a least-privilege, security-reviewed threat model; no third-party agent text is reproduced verbatim.

## License

[MIT](LICENSE).
