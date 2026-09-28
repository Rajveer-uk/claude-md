# Workflow — one playbook for every Claude app

The owner's day-to-day guide: which app to open, how to confirm the config is live, the daily loop for each role, and where fix-once is enforced. Install steps are in [`setup.md`](setup.md) and the overview is in [`README.md`](README.md). No session loads this file, so it costs 0 tokens.

**Contents:** [Which app](#1-which-app-for-what) · [Set up once](#2-set-up-once) · [Check it's applied](#3-check-its-applied-2-minutes) · [Dev loop](#4-daily-loop--development) · [Marketing loop](#5-daily-loop--marketing) · [Other roles](#6-other-roles) · [Parallel work](#7-which-parallel-mechanism) · [Tokens](#8-token-rules) · [Fix-once](#9-where-fix-once-is-enforced) · [Anywhere](#10-use-it-from-anywhere) · [Upkeep](#11-monthly-upkeep) · [Troubleshooting](#12-my-claudemd-isnt-applied--troubleshooting)

## 1. Which app for what

| Job | Open | What config it gets |
|-----|------|---------------------|
| **Coding in a repo** | Desktop app **Code** tab (Local) or the CLI. VS Code and JetBrains work too | Every local surface reads the same per-machine config: L1 + L2. Use whichever you prefer; there's nothing extra to set up |
| **Away from the machine** | **Remote Control** from your phone or the web. It drives your local session | Full L1 + L2, because it is the local session |
| **Parallel or offline code work** | A **cloud** session (claude.ai/code, mobile, or the Desktop cloud environment) | Only what the repo commits (L2) plus the skills enabled on your claude.ai account. No `~/.claude` and no plugins — unless the cloud environment's Setup script installs your user layer into each container (L1c below): then global `CLAUDE.md`, the baseline rules and the `base` pack load too, in every repo. A cloud session you continue on your phone is the same container, so it keeps them |
| **Marketing or strategy chat, quick drafts** | Claude app → that role's **Project** (L4) | Instructions for Claude, account plugins (skills and commands only; sub-agents and hooks are greyed out) and the Project's knowledge |
| **File-based knowledge work** (folders of docs or content) | **Cowork** in the Claude app | Instructions for Claude and the account plugins (everything, including agents and hooks) |
| **Decisions** (pricing, hiring, architecture, positioning) | `/council`, in Code (the seats run as agents) or in chat (a sequential fallback) | The `council` pack |
| **What to install, or a setup audit** | Ask *"what should I install?"* in that project, in Code (CLI or Desktop Code tab) | `base`'s `setup-advisor` skill, plus Anthropic's `claude-code-setup` when installed. Evidence-based picks from trusted sources only; installs only what you tick, never removes anything |

Mobile has no plugins. There you get account-uploaded skills and Remote Control.

Other Claude apps (Claude in Chrome, Excel, PowerPoint, Slack) use the account layer (L3: Instructions for Claude plus account plugins and skills), not `~/.claude`. What each one loads varies, so check in each app.

## 2. Set up once

There are four layers. You set each one up once, and it reaches the apps listed in its row. Steps are in [`setup.md`](setup.md) and templates in `templates/`.

| Layer | What | Where | Reaches |
|-------|------|-------|---------|
| **L1 Machine** | `settings.json` (hardened baseline) · `CLAUDE.md`, a **copy** of `global/CLAUDE.md` (never a symlink) · plugins: `base` everywhere, `marketing`/`council` where needed, `ecc` only in projects that need it · hooks: `guard` (recommended), `format`/`verify` (optional) | `~/.claude/` | CLI, Desktop Code tab, VS Code, JetBrains (SSH sessions use the remote host's `~/.claude`). Phone and web reach it through Remote Control |
| **L2 Repo / folder** (committed) | `CLAUDE.md` · `REGRESSIONS.md` · `.claude/guards.sh` + `.claude/guards.ps1` · per-area `CLAUDE.md` · `.claude/settings.json` · CI workflow · optional: `.claude/rules/content.md`, `brand/voice.md`, `brand/banned-phrases.txt`, `PROGRESS.md` · for cloud sessions, copies of the agents and skills they need in `.claude/agents/` and `.claude/skills/` | the repo | Every surface, including cloud. Chat gets it when you upload the files as Project knowledge |
| **L1c Cloud environment** | The environment's **Setup script** = `templates/cloud-setup.sh` (installs from your public claude-md `main`: the baseline without the Plan default, a copy of `global/CLAUDE.md`, the `base` plugin) | the cloud environment's settings (session title bar → environment menu → Edit) | Every **new** cloud Code session in that environment, in any repo: web, the Claude app on your phone, Desktop's cloud environment, `claude --cloud` |
| *Local only* (gitignored) | `.claude/checks.sh` / `.claude/checks.cmd`: a one-line wrapper that calls the guard runner · the project's path added to `~/.claude/verify-allowed.txt` | this machine | The `verify` Stop hook |
| **L3 claude.ai account** | **Instructions for Claude** (Settings → General), pasted from `claude-ai/personal-preferences.md` · account plugins via Customize → Plugins → Add marketplace `<owner>/claude-md`: `base` and `council`; `marketing` only where its Tavily/DataForSEO servers are acceptable in every signed-in Claude Code session; never `ecc` · skill zips from `scripts/package-claude-ai.sh` / `.ps1`, only for mobile, the API and cloud Code sessions | claude.ai | Web and Desktop chat (skills and commands), Cowork (everything), and **every** signed-in local Claude Code session, where they sync as `<name>@synced`, MCP servers included (a local install with the same name wins) |
| **L4 claude.ai Projects** (one per role) | Instructions from `claude-ai/project-marketing.md` or `claude-ai/project-generic.md`, plus knowledge files: brand voice, banned phrases, that role's `REGRESSIONS.md`, example pieces | claude.ai | Chat inside that Project, synced across devices |

**Per-surface one-offs**
- **Desktop-only machine (no CLI):** merge `templates/user-settings.plugins.json` into `~/.claude/settings.json`. The plugins install at the next session start. Desktop's **+ → Plugins** has no documented way to add a custom marketplace.
- **VS Code** ignores `defaultMode`. Set `"claudeCode.initialPermissionMode": "plan"` in your VS Code *user* settings.
- **Desktop** doesn't inherit shell exports. Put `TAVILY_API_KEY` and `DATAFORSEO_*` in its **Local environment editor**.
- **Desktop** remembers the mode you pick for each folder, and that pick overrides `defaultMode`. Picking Plan lasts one session and doesn't clear a folder's remembered mode, so in a folder that has drifted, pick Plan at the start of each session. How to reset the remembered pick isn't documented; verify on your build.
- **Instructions for Claude** covers every chat, Cowork session and scheduled task, but not Claude Code. Keep it in step with `global/CLAUDE.md`.
- **Uploaded skills** also sync into local Claude Code. Don't upload a skill that a plugin already ships, or it gets listed twice.
- **Account plugins** load in every signed-in Claude Code session as `<name>@synced`, MCP servers included. To keep `marketing`'s Tavily/DataForSEO servers off one machine, set `"marketing@synced": false` under `enabledPlugins` in `~/.claude/settings.json` or run `claude plugin disable marketing@synced`, then confirm with `claude plugin list`.

## 3. Check it's applied (2 minutes)

`/agents` no longer lists agents; since v2.1.198 it only prints a reminder. Use these checks instead:

| Surface | Run / do | Expect |
|---------|----------|--------|
| CLI · Desktop Code tab | `/context` | *Memory files* lists `~/.claude/CLAUDE.md` and the project `CLAUDE.md`. Custom agents appear with their source (`base:…`). Skills and token use are shown |
| | `claude plugin list` (in a shell) | `base` enabled (plus `marketing`/`council` where installed). Any `<name>@synced` twin shows as not loaded, and `marketing@synced` as disabled where you opted out |
| | `claude plugin details base` | *Always-on* ≈2.9k tokens (marketing ≈0.86k, council ≈0.5k, ecc ≈15.4k) |
| | `/hooks` | The `base` SessionStart hook, plus `guard`/`verify` if you installed them |
| | `/skills` · `@agent-` typeahead | Pack skills and agents, none of them listed twice |
| | Desktop only: **+ → Plugins → Manage plugins** | The packs, enabled |
| Claude app (chat / Cowork) | Ask *"What instructions and skills do you have?"* · open **Customize → Plugins** | Your Instructions for Claude (plus the Project's instructions), with `base`/`marketing`/`council` installed |
| Cloud session | `/context` · ask *"List your subagents and skills"* | The repo `CLAUDE.md`, the committed agents and skills, and account skills (`anthropic-skills:*`). No pack plugins and no base hook — with the L1c Setup script: also `~/.claude/CLAUDE.md` ("Working agreement"), the `base:` agents and skills and the base SessionStart rule |

- The docs imply, but don't state, that the Desktop Code tab loads `~/.claude/CLAUDE.md`. Verify with `/context`.
- If Desktop answers "isn't available in this environment" to a panel command such as `/hooks`, run that command in the CLI. Verify on your build.

## 4. Daily loop — development

Do one task per session and pick the model at the start (`opusplan` works). Sessions start in Plan mode.

1. **Explore.** Run `grep -i "code/<area>" REGRESSIONS.md` and read only the matching rows. Grep or glob before reading anything. If there are 10+ files to read, use a subagent (`project-analyst`, `code-archaeologist`) that returns a short summary. For multi-file work, run the guards once first as a baseline, so failures that already exist aren't blamed on your change.
2. **Plan.** Plan multi-file or risky changes and review the plan before any edit. Skip this step when you can describe the diff in one sentence. For a multi-step ask, the `requirements-gate` skill first lists it as `AC1…ACn` (what was asked plus the implied work: tests, other callers, docs, config, paired `.sh`/`.ps1` files), asks with a pop-up only where different readings would change the work, and records the rest as assumptions.
3. **Implement.** Do small, sequential or same-file work inline. Use parallel subagents only for independent parts on **disjoint files**, launched in one message, with each brief carrying the matching ledger rows. Running the guards with `--fast` is fine mid-task.
4. **Guard.** Run the full guard set once, in the main thread (not in a subagent, which would hide the detail): `bash .claude/guards.sh`, or on Windows `powershell -NoProfile -ExecutionPolicy Bypass -File .claude\guards.ps1`. The report's first line is the evidence:
   `Guards: bash .claude/guards.sh → exit 0, <summary line>; R-004 ✓ R-011 ✓`. If it reads `Guards: RED — <step>: <reason>`, the task is **not** done.
   When the task has an AC list, line 2 is `Requirements: 5/5 met` (or `Requirements: 4/5 — AC3 partial: <reason>`), backed by one piece of evidence per AC (`file:line`, a test name, or a command and its exit code). An AC that isn't met means the task is **not** done, exactly like RED.
5. **Review.** `code-reviewer` runs last. Add `security-auditor` when the change touches auth, secrets, input handling or dependencies, and `ponytail` for diffs over the inline limit (step 6).
6. **Commit.** Use a Conventional Commit, and never commit on red. Every commit passes the **review gate** first: `code-reviewer` and `ponytail` review the diff being committed, every blocking finding is fixed and the guards re-run, and only then is it committed. A diff of 10 changed lines or fewer (or the `CLAUDE_REVIEW_GATE_INLINE_MAX` you set) with no binary file may use the inline checklist instead of the two agents. The optional `review-gate` hook enforces it: `git commit` is denied until a review is recorded for exactly that diff, and any later edit needs a new one.

**Bug fix.** Write a failing test first; it must fail *for the expected reason*. Then fix the code, not the test. Add the strongest guard you can (`test:` beats `check:`, which beats `review:`) and one ledger row. If there's a general lesson, propose a one-line diff to `~/.claude/CLAUDE.md` that passes the test "Would removing this cause Claude to make mistakes?". Apply it only once you approve. The `debugger` agent can help.

| ID | Area | Rule (must stay true) | Guard | Added |
|----|------|-----------------------|-------|-------|
| R-012 | code/api | A retried webhook never charges twice | `test: tests/test_webhooks.py::test_retry_is_idempotent` | 2026-09-25 |

**Big feature.** Ask Claude to interview you, or run **`/spec <request>`**, which does it with batched pop-ups. It then writes the spec (`specs/<slug>.md` from `templates/SPEC.md`; a root `SPEC.md` works too), covering the requirements `AC1…ACn` and how each is verified, the files and interfaces involved, what is out of scope, an end-to-end verification step, and a task plan in which every task names the ACs it covers. Approve it, then start a **fresh session** (or approve with the clear-context option) and run `/implement-plan specs/<slug>.md` (or `/implement-plan SPEC.md`): it creates a branch (or resumes it), runs one agent per task and a review gate, proves every AC with evidence through the `completion-auditor` agent, commits each task, and pushes once.

**Incomplete prompt or comment → partial delivery.** This is the failure where a short prompt, issue or review comment gets its literal half built and the rest silently dropped. Four layers catch it, from cheapest to strictest:

| Layer | What it catches | Cost |
|-------|-----------------|------|
| `requirements-gate` skill (base, triggers on any multi-step ask) | Unstated companion work, and forks Claude would otherwise resolve narrowly. It lists `AC1…`, asks with a pop-up, and ends with an AC → evidence table | ≈0.5–1.5k tokens per multi-step task; 0 on one-line edits |
| `/spec` → `/implement-plan` → `completion-auditor` | Requirements with no task, items marked done with no proof, scope drift, unbounded review loops, and a lost place after compaction (the command is resume-safe) | ≈10–25% over a plain `/implement-plan` run |
| Guard steps `no-stubs` + `spec-integrity` (`templates/guards.*`) | TODO/stub/placeholder markers, "rest of code unchanged" elisions and newly skipped tests in the diff; an AC marked `met` with no evidence; a feature list edited to pass | 0 model tokens (they run in the guards, the verify hook and CI) |
| `plan-gate` Stop hook (optional, local) | Claude ending the turn while plan items or ACs are still open | 0 tokens unless it blocks (≈100 per nudge, at most 3) |

**Which orchestrator:** **A (default)** `/spec` → `/implement-plan` with the completion audit. **B (`/implement-plan --strict`)** for auth, payments, client data or FCA-facing output: each task agrees its done-criteria with `completion-auditor` before any code and is audited on its own; it costs about 1.5–2.5× a normal run. **C (multi-session)** for work spanning days or more than ~15 ACs: `/spec` also writes `specs/<slug>.features.json`, and each session implements one feature whose `passes` is false (see the next paragraph). Community orchestrators (ruflo/claude-flow, claude-squad, Task Master, BMAD, spec-kit) were reviewed and not installed: none publishes a reproducible benchmark that beats this loop, and each adds fetch-and-execute installs, network access or heavy per-feature ceremony.

**Multi-session work.** Keep a `PROGRESS.md` (from `templates/PROGRESS.md`) with status, what's done, what's next and failed approaches. At the start of a session, read it along with `git log --oneline -10`. At the end, update it, then `/clear`. Anything you fix graduates into a ledger row; `PROGRESS.md` itself is disposable. For a feature with a feature list (`specs/<slug>.features.json`, from `templates/features.json`), that file is the source of truth: each session picks one entry whose `passes` is false, implements it, runs its `verify`, and sets only `passes` and `evidence`. The `spec-integrity` guard step fails if an entry is removed, its description or check is edited without your OK, or `passes` is true with no evidence. Never run these loops with `--dangerously-skip-permissions`.

## 5. Daily loop — marketing

**Content folder (Code tab or CLI).** The folder holds `CLAUDE.md`, `brand/voice.md`, `brand/banned-phrases.txt`, `REGRESSIONS.md` (the `mkt/` rows) and the guard runner, whose `content-lint` step checks the directories listed in `CONTENT_DIRS`.

1. **`/marketing:draft`** drafts from a brief, applying `brand/voice.md` (through the `brand-voice` skill) and the matching `mkt/` rows. If the brief needs current facts, run `content-researcher` first; it and `seo-rank-monitor` are the only two agents with network access.
2. **`/marketing:review`** has the draft checked against the voice, the banned phrases and the `mkt/` rows, and violations are flagged by ID.
3. **`bash .claude/guards.sh`** must print `OK content-lint`. Report the evidence line as in §4.
4. **Record every correction once:**
   - wording ("never say *X*") → add a line to `brand/banned-phrases.txt`. `content-lint` enforces it automatically, so it needs no `review:` row;
   - voice or tone → append `Updated: <date> — <rule> — <reason>` to `brand/voice.md` and add a `mkt/<channel>` ledger row;
   - claims, offers or compliance → add a `mkt/<topic>` row with the strongest guard (`check:` wherever it can be scripted).

**Quick work in chat.** Use the **Marketing** Project (L4); its knowledge files hold the same voice, banned phrases and ledger. When you correct it, it outputs the new ledger row. Paste that into the repo file and re-upload the knowledge file.

**Folders of files.** Use Cowork with the `marketing` and `base` account plugins. The docs don't say whether Cowork reads a folder's `CLAUDE.md`, so verify by asking it to list its instruction sources. L3 applies either way.

## 6. Other roles

| Role | Loop | Fix-once |
|------|------|----------|
| **Ops incident** | `ops-triage` (read-only: logs, disk, queues), then `devops-troubleshooter` for failed deploys or CI, then the fix | An `ops/<system>` row plus a `check:` step in `.claude/guards.sh`, such as a config assertion (see the runner's commented example) |
| **Docs drift** | `documentation-specialist` updates the docs together with the code change | A `docs/<area>` row with a `check:`, e.g. "the documented command still exists". The weekly CI run catches drift |
| **Strategy / growth** | `growth-strategist` for plans; `/council` for high-stakes calls (in chat, its sequential fallback runs) | Any rule a decision creates becomes a `biz/<area>` row, with a `review:` guard that names an observable outcome |
| **Any role in chat** | A generic Project (`claude-ai/project-generic.md`) with the role's `REGRESSIONS.md` as knowledge | When you correct Claude, it outputs the row and you paste it into the file |

## 7. Which parallel mechanism

| Mechanism | Use when | Relative cost |
|-----------|----------|---------------|
| **Inline** (main thread) | The work is small, sequential or in the same file | Lowest; this is the default |
| **Subagents** (pack agents) | There are 10+ files to read, 3+ independent parts, verbose output to keep out of the main thread, or an independent review | Agents use ≈4× chat tokens, and only a short result returns. Launch them in one message, and resume an agent (SendMessage) for follow-ups |
| **Fork** (`/subtask`) | A side task needs this conversation's context | Cheaper start, because it inherits the context and prompt cache |
| **Worktrees** (`isolation: worktree`) | Parallel edits can't be split into disjoint files | Same as subagents, plus a merge step |
| **Workflows** | A job outgrows a handful of subagents. **Only when the owner asks** | A run can use meaningfully more tokens than the same task in conversation (Anthropic's multi-agent research system ran ≈15× chat) |
| **Agent teams** | Teammates need to coordinate with each other. **Only when the owner asks** | ≈7× the tokens of a standard session when teammates run in plan mode (Anthropic's costs page); each teammate is a separate Claude instance |

- Subagents, except a fork, don't see the conversation. Each brief needs an objective, inputs (paths plus the matching `REGRESSIONS.md` rows), boundaries, the output (≤200 words, with details in a file) and the tools/model.
- The built-in **Explore** agent runs on the main model; it's cheap only because it skips `CLAUDE.md`. For haiku-tier search, use `project-analyst` or `documentation-specialist`.
- Keep `ultracode` out of your settings: it runs every substantive task as a workflow at `xhigh` effort and switches off the Large-workflow warning and the concurrent-subagent limit. Optional guard rails: `"workflowSizeGuideline": "small"` in `~/.claude/settings.json`, and turn off the ultracode keyword trigger in `/config` if you type the word by accident. You can still say "use a workflow" whenever you want one.

## 8. Token rules

1. Do small, sequential or same-file work inline, without subagents — except deliverables a pack specialist owns with its own guardrails (marketing copy → the marketing writers; security audits → `security-auditor`), even when small.
2. Use subagents when there are **10+ files to read, 3+ independent parts, verbose output to isolate, or an independent review**. Launch the independent ones in parallel in **one** message, and run parallel edits only on disjoint files. Each brief covers the objective, inputs (paths plus matching ledger rows), boundaries, output (a ≤200-word result, with details in a file whose path it returns) and tools/model. Resume an agent for follow-ups. Use workflows and agent teams only when the owner asks.
3. Read in a targeted way: grep or glob first, then read only the range you need. Don't re-read files that haven't changed.
4. Use Plan mode for multi-file or risky work. Skip planning when the diff fits in one sentence.
5. Pick the model at session start. `opusplan` means Opus plans and Sonnet executes (today Opus 5.5 `claude-opus-5-5`, $4/$20 per million input/output tokens, and Sonnet 5 `claude-sonnet-5`, $2/$10; Haiku 4.5 `claude-haiku-4-5` is $1/$5). The aliases `opus`/`sonnet`/`haiku` follow the newest model of each family, so the installer pins them with `ANTHROPIC_DEFAULT_OPUS_MODEL` / `_SONNET_MODEL` / `_HAIKU_MODEL`: a new release changes nothing until you bump a pin on purpose, after checking its price. Keep Fable 5.1 (`claude-fable-5-1`, $10/$50) for the main session only when a task needs it, never for subagents. On a Pro plan, start sessions on Sonnet 5 and switch to Opus 5.5 with `/model` only for hard design or debugging; each switch between planning and execution re-sends the context once. Agents keep their tiers (opus for planning and security, sonnet for implementation, haiku for search and docs). Leave effort at its default.
6. Do one task per session. `/clear` between tasks (in cloud, start a new session) and after two failed corrections on the same issue. Use `/rewind` to abandon a path, `/btw` for side questions, `/compact <focus>` at natural breaks and `/context` when the session feels heavy.
7. The guards are the memory. They cost ~0 tokens when green, so don't re-explain history in chat.
8. Final replies to the owner give the result and any decisions needed, without narration (`/caveman lite` or `outputStyle: "Concise"` if you want it shorter). Never compress plans, briefs or reasoning. Expect caveman's big saving (~65%, its design target) on chat-style prose only: an independent test on agentic coding measured ~8.5% fewer output tokens with no quality change (JetBrains, 2026-07). The real levers are the rules above: context isolation, `/clear`, green guards and the default effort.
9. Install only the packs a project needs.
10. Watch context and cost for free. Run `/statusline show model, context used %, effort, prompt cache warm and minutes to expiry, 5-hour limit %` once and review the script it writes; the status line runs locally and uses no API tokens (a custom one hides some footer hints). Use `/usage` (alias `/cost`) for the cache-hit line, and `/insights` monthly for recurring failure patterns to turn into ledger rows. Avoid `npx` status lines and `npx ccusage@latest`: they fetch and run unpinned code, and ccusage reads every transcript and fetches pricing online.

**Published multiples:** agents use ≈4× the tokens of chat, agent teams ≈7× a standard session (teammates in plan mode), and Anthropic's multi-agent research system ≈15×. **Measured always-on cost per pack** (check with `claude plugin details <pack>`) **and for the memory files** (check with `/context`):

| Pack | Always-on | Install |
|------|-----------|---------|
| Memory files | `global/CLAUDE.md` ≈1.9k tokens + a project `CLAUDE.md` ≈0.8k | Loaded every session and into most subagents (not Explore, Plan or `omitClaudeMd` agents) |
| `base` | ≈2.9k tokens | Every machine and the account |
| `marketing` | ≈0.86k per `claude plugin details` (≈0.7k in context) | Where content work happens; on the account only where its MCP servers are acceptable in every signed-in session |
| `council` | ≈0.5k | Where decisions happen, and the account |
| `ecc` | ≈15.4k | Only in projects that need it; never on the account |

A skill with `disable-model-invocation: true` costs nothing always-on, and you can still run it yourself.

## 9. Where fix-once is enforced

| Enforcer | What it does | Where it runs |
|----------|--------------|---------------|
| **Guard runner** (`.claude/guards.sh` / `.ps1`) | Runs every named step and prints `OK <step>` or `ERROR <step>: <reason>`. It exits non-zero if any step fails and logs to `.claude/guards.log`. Its `ledger-integrity` step fails if a ledger row was removed, unless `ALLOW_GUARD_CHANGE=1` is set | Anywhere with a shell: local, cloud and CI |
| **`verify` Stop hook** | Runs the local `.claude/checks.*` wrapper whenever Claude tries to finish, and blocks while the guards are red, up to 3 times (Claude Code itself ends the turn after 8 consecutive blocks) | Local only, in projects listed in `~/.claude/verify-allowed.txt` |
| **`guard` PreToolUse hook** | **Asks** you only when an edit would change or remove an existing ledger row (`REGRESSIONS.md`), a guard runner (`.claude/guards.*`, `.claude/checks.*`: any edit counts) or a banned phrase (`brand/banned-phrases.txt`). Appends to the ledger or banned list pass | Local, once installed |
| **CI** (`templates/github/regression-guards.yml` → `.github/workflows/`) | Runs the guards on every PR and push, plus weekly, with zero model tokens | GitHub |
| **Reviewers** (`code-reviewer`, `content-editor`) | Grep the ledger for the areas a change touches and flag violations by ID | Code and Cowork |
| **`regression-guard` skill** (base) | The procedure: grep the rows, fix, guard, write the row, show the evidence line. In chat, it outputs the row for you to paste | Everywhere the base pack or its skill reaches |
| **`/goal` recipe** | A gate for sessions where user hooks don't run (cloud sessions, or Desktop without the hooks installed) | Code surfaces only, not chat or Cowork |
| **`plan-gate` Stop hook** (optional) | While `/implement-plan` runs, blocks finishing when the plan file still has open items (`- [ ]`, `Status: todo`, an AC row still `open`), up to 3 times, then shows a "plan NOT complete" warning. It reads only the plan files named in a marker that `/implement-plan` writes for the current session, and runs no project code, so it needs no allowlist | Local, once installed |
| **Guard steps `no-stubs` and `spec-integrity`** | Fail on stub markers, elisions and newly skipped tests added in the diff, and on an AC marked `met` without evidence or a feature list edited to pass | Wherever the template runner is copied: local, cloud and CI |
| **`review-gate` PreToolUse hook** (optional) | Denies `git commit` until a review (code-reviewer + ponytail, or the inline checklist for a tiny diff) is recorded for exactly the diff being committed; an edit after recording needs a new review. The record lives in a private temp dir, never in the repo. It proves the review step was taken and stated in the chat, not how good it was | Local and cloud, once installed (`--hooks review-gate`) |
| **`completion-auditor` agent** (base) | Read-only audit of every AC against its evidence, plus the changed files no AC asked for | Code surfaces |

All Stop hooks share Claude Code's cap of 8 consecutive continuations, which is why verify stops at 3 blocks, plan-gate at 3 and the opt-in prompt check (below) at 1.

**`/goal` recipe** (Code surfaces only: cloud sessions and Desktop without user hooks; not chat or Cowork). Switch out of Plan first, because `/goal` doesn't change the permission mode. You type the goal yourself. A small model checks the condition after each turn and reads only the conversation, so the condition has to name output that appears in the chat:

```text
/goal The conversation shows `bash .claude/guards.sh` run after the last edit with exit 0 and its summary line, and every REGRESSIONS.md row for the touched areas marked ✓ — or stop after 20 turns
```

For a spec or plan, the same recipe with the requirements added:

```text
/goal The conversation shows the requirements table with every AC met and its evidence, every plan item marked done or Status: blocked, and `bash .claude/guards.sh` run after the last edit with exit 0 and its summary line — or stop after 30 turns
```

**Opt-in soft check.** `.claude/settings.hooks.example.json` also documents `_optional_promptCompletionCheck`, a prompt-type Stop hook that asks a small model whether the last reply admits unfinished work ("next I would…", "left a TODO"). Register it per project in `.claude/settings.local.json` only: it costs a small-model call at every turn end (≈0.6–2k input tokens and 1–5 s).

**Not used, on purpose:** agent-type Stop hooks (experimental; up to 50 tool turns at every turn end, and they can run commands in any project, which bypasses verify's allowlist); "unfinished todo" gates built on TodoWrite or TaskCompleted (current models don't get the task tools unless `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`, so these gates silently do nothing; the plan file plus plan-gate is the checklist); and community hook packs installed with `npx …@latest` or `uv run` (the useful patterns are re-implemented in this repo's own hooks and guard steps).

## 10. Use it from anywhere

**Remote Control** is the one way to drive your full local config (L1 + L2) from a phone or the web. Set `"remoteControlAtStartup": true` in `~/.claude/settings.json`; it must be your *user* settings, because a project value is ignored. Alternatively, turn on the Remote Control toggle in the Desktop app. The machine has to stay on while you use it.

| Move | How |
|------|-----|
| CLI → Desktop | `/desktop` |
| Continue a CLI session in Desktop | `/resume` inside Desktop (it lists your CLI sessions) |
| Desktop local → cloud | **Continue in → Claude Code on the Web** |
| Terminal → new cloud session | `claude --cloud "<task>"`; push your branch first |
| Cloud → terminal | `claude --teleport`, or `/tp` |
| Cloud session → phone | Open it in the Claude app (Code). It's the same container, so the same packs and rules (L1c) |

Cloud sessions have no `/clear` (start a new session instead) and no `/plugin`.

## 11. Monthly upkeep

- Run **`/context`** in a fresh session and confirm the memory files, agents and skills load with no duplicates.
- Run **`/doctor`** and act on its findings. Decline its offers to make auto mode your default or to move Fix-once or Safety lines out of `CLAUDE.md` into skills.
- Run **`/doctor prompt-audit`** (v2.1.283+; on older builds, `/claude-api prompt-audit`) on this repo and on each active project. Accept diffs that drop CAPS emphasis, verification rituals, undocumented thinking keywords or dated settings. Decline any diff that deletes, moves out of always-on text, or softens a Fix-once, Safety or guard line, changes a `REGRESSIONS.md` row, or switches the plan-mode default. The `prompt-hygiene` guard step keeps this repo from drifting back.
- Run **`/insights`** and turn each recurring failure pattern into a ledger row with a guard.
- Run **`claude plugin details <pack>`** and compare the result with the §8 table. Drop any pack a project no longer uses.
- Ask *"audit my Claude setup"* (`setup-advisor`) in each active project. It checks what's installed against the project's stacks and roles, lists duplicates as optional cleanup and installs only what you tick. Refresh Anthropic's plugins first: `claude plugin marketplace update claude-plugins-official`, then `claude plugin update claude-code-setup@claude-plugins-official`.
- **Trim `CLAUDE.md`** to under 200 lines. Test each line with "Would removing this cause Claude to make mistakes?". Anything that fails the test goes; anything that must always happen becomes a hook or a `check:` step. Keep at most one "IMPORTANT".
- **Promote `review:` rows** to `test:` or `check:` wherever they can be automated; `review:` is the weakest guard.
- **When a pack's version is bumped,** run `claude plugin validate . --strict` and `claude plugin validate plugins/<pack> --strict`, then the pack evals: `claude plugin eval plugins/<pack> --max-cost-usd 10` (each pack's `evals/README.md` has its full command and cap).
- Check that the weekly CI guard run is green.

## 12. "My CLAUDE.md isn't applied" — troubleshooting

| ☐ Check | Why | Fix |
|---------|-----|-----|
| Did you edit it during the session? | Edits take effect only after `/clear`, `/compact` or a restart | Run `/clear` (in cloud, start a new session) |
| Is this a **cloud** session? | Cloud sessions don't load `~/.claude`: no global `CLAUDE.md`, no plugins, no user hooks | Add the L1c Setup script (`templates/cloud-setup.sh`, setup.md Quick start step 10) for your own sessions in every repo, or put project rules in the repo `CLAUDE.md` and commit the needed agents and skills to `.claude/`. Use the `/goal` recipe, or Remote Control for the full config |
| Is it a multi-repo cloud session? | Repo `.claude/settings.json` applies only in single-repo sessions | Use one repo per session |
| Is this **chat**? | Chat never reads `CLAUDE.md` | Use Instructions for Claude plus the Project's instructions and knowledge |
| Is this **Cowork**? | Cowork never reads `~/.claude` skills or plugins, and the docs don't say whether it reads a folder `CLAUDE.md` | Rely on Instructions for Claude and the account plugins. Verify by asking it to list its instruction sources |
| Is `~/.claude/CLAUDE.md` a symlink? | Cowork skips a symlinked file, and also skips imports from outside the folder | Copy `global/CLAUDE.md`; never symlink it |
| Are the missing rules pulled in by `@import`? | Imports load at launch and follow at most 4 hops | Keep imports shallow, and never @-import a file that keeps growing |
| Is a per-area `CLAUDE.md` being ignored? | It loads when Claude **reads** a file in that folder (writing or creating one doesn't count), and it's dropped at `/compact` | Have Claude read a file there first. Rules that must always hold go in the root `CLAUDE.md` |
| Is a `.claude/rules/*.md` file being ignored? | A rule file with `paths:` loads only when a matching file is read | Remove `paths:` to make the rule always on |
| Is the text inside `<!-- -->`? | HTML block comments are stripped before loading | Move the text out of the comment |
| Was working context (files touched, R-IDs) lost at `/compact`? | Compaction summarises the conversation | Add a "Compact instructions" section to `CLAUDE.md` that names what to keep |
| Did a subagent ignore a rule? | The built-in Explore and Plan agents skip `CLAUDE.md`, and no subagent except a fork sees the conversation | Restate the rule and the matching ledger rows in the brief, or use a pack agent |
| Is a correction missing on another machine? | Auto memory (`MEMORY.md`) is local to each machine and doesn't reach subagents | Record the correction as a row in the committed `REGRESSIONS.md` |
| Is a rule still skipped even though it's loaded? | Long files get ignored, and `CLAUDE.md` is advisory | Keep the file under 200 lines (`/doctor` helps), and turn the rule into a hook or `check:` step |
| Did the session not start in Plan mode? | VS Code ignores `defaultMode`, and Desktop's per-folder pick overrides it | VS Code: set `claudeCode.initialPermissionMode: "plan"`. Desktop: pick Plan at the start of each session there (it lasts one session and doesn't clear the folder's remembered mode; how to reset that isn't documented, so verify) |
| Is a pack agent missing, or does it have odd tools? | If a plugin agent's frontmatter fails to parse, the agent loads with every field ignored | Run `claude plugin validate plugins/<pack> --strict` and update the pack |
| Are the packs missing in Desktop? | Desktop's UI has no documented way to add a custom marketplace | Run `claude plugin marketplace add <owner>/claude-md` in a terminal, or merge `templates/user-settings.plugins.json`, then restart |
| Do the network researchers have no tools or no keys? | Plugin MCP tools are named `mcp__plugin_marketing_<server>__…`, and Desktop doesn't read shell exports | Update `marketing` (1.1.0+). Set the keys in Desktop's Local environment editor |
| Do a pack's MCP servers show up where you never installed it? | Plugins enabled on your claude.ai account load in every signed-in Claude Code session as `<name>@synced`, MCP servers included | Keep `marketing` off the account, or opt this machine out: `"marketing@synced": false` under `enabledPlugins`, or `claude plugin disable marketing@synced`. Confirm with `claude plugin list` |
| Is this another Claude app (Chrome, Excel, PowerPoint, Slack)? | Those apps use the account layer (Instructions for Claude plus account plugins and skills), not `CLAUDE.md` or `~/.claude` | Put the rule in Instructions for Claude or an account plugin, then check in that app what it loads |
