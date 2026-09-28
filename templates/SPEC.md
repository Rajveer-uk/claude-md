<!--
TEMPLATE (claude-md/templates/SPEC.md) — the spec for one multi-file feature or vague request. `/spec <request>` fills it
(explore → interview → specs/<slug>.md); a root SPEC.md is accepted too. Then: approve, /clear, /implement-plan specs/<slug>.md.
- Size: ≤1.3k tokens when filled. Cut prose, not ACs. Replace every <placeholder>; drop guidance lines you don't need.
- IDs: AC1, AC2, … — never R-… (that prefix belongs to REGRESSIONS.md rows). An AC is never deleted or reworded to make it
  pass; dropping or deferring one needs the owner's OK and is recorded as "deferred (owner OK)".
- Requirement: "When <trigger>, <component> shall <result>", or Given/When/Then. One observable behaviour per row.
- Source: asked, or implied: <why> (requirements-gate skill, references/implied-work.md).
- Verify: test: <path>::<name> · check: <guard step> · cmd: <command> · manual: <observable outcome>.
- Status: every row starts open → met · partial · not met · deferred (owner OK). "No evidence found" counts as not met.
  Evidence: file:line, a test name, or a command and its exit code — never a bare claim. The spec-integrity guard step
  fails a met row with an empty Evidence cell or a test: path that doesn't exist; it never fails an open row.
- Plan: each task has its own status line (todo → done, or blocked — <reason>) and a Covers line naming its ACs.
  Every AC has at least one task, every task at least one AC. The plan-gate Stop hook reads these formats; keep them.
- Multi-session work (days, or more than ~15 ACs): also copy templates/features.json to specs/<slug>.features.json.
- Public-safe: no secrets, hosts, IPs or client names — use placeholders such as <APP_NAME>.
-->
# Spec: <feature name>

**Goal:** <one or two sentences: the outcome, and who it is for>
**Source:** <request, issue or thread> · **Approver:** <owner> · **Updated:** YYYY-MM-DD

## Requirements

| AC | Requirement | Source | Verify | Status | Evidence |
|----|-------------|--------|--------|--------|----------|
| AC1 | When <trigger>, <component> shall <result> | asked | test: <path>::<name> | open | |

## Out of scope
- <what a reader might expect that this work won't do>

## Boundaries
- **Always:** <rules every task keeps: matching REGRESSIONS.md rows, existing contracts, style>
- **Never:** <what no task may do without the owner's OK>

## Files & interfaces
- `<path>` — <what changes>; <endpoint, function or schema and its shape>

## Assumptions
- <default chosen> — <why> — confirmed by <owner, or "not yet">

## Clarifications
- <question> → <answer> (YYYY-MM-DD)

## Open questions
- <question still blocking an AC, or "none">

## End-to-end verification
- <one command or manual walk-through that shows the whole feature working>

## Plan

### 1. <task>
Status: todo
Covers: AC1
Agent: <pack agent> · Files: `<path>`

## Evidence
<!-- One line per AC, appended when proven: AC1 — <file:line | test name | command → exit 0> (commit <hash>) -->
