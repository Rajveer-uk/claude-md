<!--
claude-md's OWN fix-once ledger: this repo eats its own dog food. Format and rules: templates/REGRESSIONS.md.
Every row is enforced by a named step in .claude/guards.sh ("check: <step>"); CI runs it on every push and PR
(.github/workflows/guards.yml). Run before calling any change here done:  bash .claude/guards.sh
- "Never shrink" rows compare the working tree with GUARD_BASE_REF (default: HEAD plus, when the branch has an upstream,
  its fork point, so an unpushed commit can't drop anything either; CI: the PR's base branch, or the pre-push commit on pushes).
- ALLOW_GUARD_CHANGE=1 (CI: PR label guard-change-approved) = the owner's explicit OK for a deliberate change
  to a base-ref comparison or a ledger row. Absolute rules (plan default, bypass-disable, WebFetch/WebSearch
  denied, network scoping, parsing) still fail; changing one means editing .claude/guards.sh with owner OK.
- Rows are never deleted; retire one by prefixing its Rule with "retired: YYYY-MM-DD <reason> —" (owner OK only).
- No "|" inside a cell. Public-safe: no secrets, hosts, IPs or client names in any row.
-->
# REGRESSIONS — fix-once ledger (this repo)

Every row must stay true. Grep by Area tag before editing; run `bash .claude/guards.sh` before calling work done.

| ID | Area | Rule (must stay true) | Guard | Added |
|----|------|-----------------------|-------|-------|
| R-001 | ops/security | `.claude/settings.json` keeps `permissions.defaultMode: "plan"` and `permissions.disableBypassPermissionsMode: "disable"`. | check: settings-baseline | 2026-09-25 |
| R-002 | ops/security | `.claude/settings.json` `permissions.deny` (and `ask`) never loses an entry that exists at the base ref, and `deny` always contains `WebFetch` and `WebSearch`. | check: settings-deny | 2026-09-25 |
| R-003 | ops/security | `managed/managed-settings.json` keeps `permissions.disableBypassPermissionsMode: "disable"` and never loses a `deny` (or `ask`) entry that exists at the base ref. | check: managed-settings | 2026-09-25 |
| R-004 | code/agents | Network tools (`WebFetch`, `WebSearch`, `mcp__*`, inline `mcpServers`) appear only in `content-researcher` and `seo-rank-monitor`; those two list every MCP tool under both its classic `mcp__<server>__<tool>` name and its plugin-scoped `mcp__plugin_marketing_<server>__<tool>` name. Every other agent keeps a parseable `tools:` list. | check: network-agents | 2026-09-25 |
| R-005 | code/agents | An agent that is read-only at the base ref (its `tools:` has no `Write`, `Edit` or `Bash`) never gains a write or shell tool, never loses its `tools:` list and never gets a `memory:` field. | check: readonly-agents | 2026-09-25 |
| R-006 | code/agents | No agent's `tools:` list grows a network tool vs the base ref (the plugin-scoped twin of an MCP tool it already had is not growth); a new agent starts with none. | check: agent-network-growth | 2026-09-25 |
| R-007 | code/hooks | `.claude/hooks/verify.sh` and `verify.ps1` keep the `verify-allowed.txt` allowlist gate in their code. | check: verify-gate | 2026-09-25 |
| R-008 | code/hooks | In `.claude/settings.hooks.example.json` the guard hook's PreToolUse matcher covers `Bash`, `PowerShell`, `Monitor`, `Write` and `Edit`. | check: guard-matcher | 2026-09-25 |
| R-009 | code/plugins | `plugins/base/hooks/hooks.json` has a top-level `description` and only a `SessionStart` hook (matcher: startup, clear, compact) whose command is one single-quoted ASCII `echo` of plain text that names `REGRESSIONS.md` and `regression-guard`. | check: base-hook | 2026-09-25 |
| R-010 | docs/claude-md | `global/CLAUDE.md` stays at ≤70 and root `CLAUDE.md` at ≤60 loaded lines (HTML comments excluded). | check: line-budgets | 2026-09-25 |
| R-011 | code/plugins | Every `.json` file in the repo parses (UTF-8, no BOM, no duplicate keys). | check: json-parse | 2026-09-25 |
| R-012 | code/plugins | Every agent, skill and command file has parseable frontmatter: a `---` block, `name` and `description` for agents and skills, no unquoted value containing `: ` (else Claude Code ignores every field, incl. `tools`). | check: frontmatter | 2026-09-25 |
| R-013 | docs/public | No email address, IPv4 literal or secret-token pattern in committed text files, except the placeholder allow-list in `.claude/guards.sh`. | check: public-safe | 2026-09-25 |
| R-014 | docs/readme | The README agents badge equals the number of `plugins/*/agents/*.md` files. | check: readme-agent-badge | 2026-09-25 |
| R-015 | code/plugins | `claude plugin validate --strict` passes on the marketplace and on every plugin directory (SKIP where the `claude` CLI isn't installed). | check: plugin-validate | 2026-09-25 |
| R-016 | ops/guards | Ledger integrity: every `test:` path and name and every `check:` step exists, IDs are unique, and no row present at the base ref disappears or changes without `ALLOW_GUARD_CHANGE=1`. | check: ledger-integrity | 2026-09-25 |
| R-017 | code/plugins | No agent, skill, command, eval, plugin manifest, hook script, template, settings file or marketplace plugin entry present at the base ref is removed. | check: inventory | 2026-09-25 |
| R-018 | code/hooks | `.claude/settings.hooks.example.json` still registers the guard (PreToolUse), format (PostToolUse) and verify (Stop) hooks and keeps the opt-in per-prompt `UserPromptSubmit` snippet. | check: hook-registrations | 2026-09-25 |
| R-019 | code/hooks | `.claude/settings.hooks.example.json` keeps the opt-in per-prompt delegation directive under `_optional_perPromptDelegationReminder` and registers verify on `UserPromptSubmit` (turn-start marker, so review-only turns are not blocked). | check: hook-optin-snippet | 2026-09-26 |
| R-020 | docs/prompts | Model-loaded prompt files (global and root `CLAUDE.md`, `claude-ai/`, `templates/CLAUDE.package.md` and `SPEC.md`, base/marketing/council agents, skills and commands, the base hook) never gain all-caps emphasis words (MUST, NEVER, ALWAYS, IMPORTANT, CRITICAL outside severity tags) or verification/thinking rituals vs the base ref; HTML comments excluded. | check: prompt-hygiene | 2026-09-27 |
| R-021 | code/hooks | `.claude/hooks/plan-gate.sh` and `.ps1` exit 0 in plan mode, act only on a `.claude/plan-gate.local.json` marker for their own session, stop blocking after `CLAUDE_PLAN_GATE_MAX_BLOCKS`, and stay registered on Stop in `.claude/settings.hooks.example.json`. | check: plan-gate-bounds | 2026-09-27 |
| R-022 | code/plugins | The completeness chain stays intact: `requirements-gate` (AC list, AskUserQuestion gate, `Requirements:` line), `/spec`, read-only `completion-auditor`, `/implement-plan` (audit step, `Requirements:` line, plan-gate marker, NEEDS_CONTEXT, `--strict`, features file), `templates/SPEC.md`, and the scope line in global and root `CLAUDE.md`. | check: completeness-chain | 2026-09-27 |
| R-023 | ops/guards | `templates/guards.sh` and `templates/guards.ps1` define the same steps, including `ledger-integrity`, `content-lint`, `lint`, `tests`, `no-stubs` and `spec-integrity`, and never lose a step that exists at the base ref. | check: template-guard-steps | 2026-09-27 |
| R-024 | code/plugins | The `requirements-gate` skill triggers on a short, vague multi-file feature request and its final reply carries the AC list with implied ACs and the Assumptions: `claude plugin eval plugins/base --case requirements-gate-vague-request --ablation none` passes every grader, and `--case one-line-edit-no-gate` stays at 0 pop-ups, before any `base` release or edit to the skill's description (paid run, so not in CI). | review: both requirements-gate eval cases pass all graders on the release candidate | 2026-09-27 |
| R-025 | ops/install | `scripts/install-user-config.sh` only ever adds to `~/.claude/settings.json` (every other key, hook and deny entry kept; baseline deny and ask added once; a non-plan mode kept; backup first), keeps an owner's own `CLAUDE.md`, sets no Plan default with `--cloud`, leaves an unparseable file untouched with exit 1; `templates/cloud-setup.sh` runs it with `--cloud` and always exits 0. | check: user-installer | 2026-09-27 |
| R-026 | ops/security | `.claude/hooks/guard.sh` and `guard.ps1` treat every command that can dump a file's content (sort, uniq, tac, diff, tr, hexdump, openssl, tee, editors and the rest of the fixture list) as a reader, so reading a protected secret path with it is denied; the twins list the same readers. | check: guard-readers | 2026-09-27 |
