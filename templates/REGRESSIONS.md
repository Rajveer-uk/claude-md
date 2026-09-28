<!--
TEMPLATE (claude-md/templates/REGRESSIONS.md) — the fix-once ledger. Copy to the project/folder root as REGRESSIONS.md.
In a claude.ai Project (chat), upload it as a knowledge file instead.

How it is used (regression-guard skill; root CLAUDE.md "Fix-once ledger"):
- Before editing an area: grep -i "<area tag>" REGRESSIONS.md → read only the matching rows; paste them into any subagent hand-off.
  Never @-import this file: imports load in full every session and the ledger only grows.
- Every bug fix or owner correction: reproduce (code: a test that fails for the expected reason; content: name the exact rule broken)
  → fix the code/content, never the test → add the strongest guard → add one row here.
- Before "done": run the full guard set once — bash .claude/guards.sh (Windows: powershell -NoProfile -ExecutionPolicy Bypass -File .claude\guards.ps1).
  Report "Guards: <command> → exit 0, <summary line>; R-00x ✓" — or "Guards: RED — <step>: <reason>" and don't claim done.

Format — one row per rule: | ID | Area | Rule (must stay true) | Guard | Added |
- ID: R-001, R-002, … in order. IDs are never reused; gaps are fine.
- Rows are never deleted. To retire a rule, keep the row and prefix its Rule with "retired: YYYY-MM-DD <reason> —" (owner OK only).
- Area: one lowercase tag — code/<area>, mkt/<channel-or-topic>, ops/<system>, docs/<area>, biz/<area>.
  Use the Ledger tag from the root CLAUDE.md package map for code areas.
- Rule: one present-tense statement that must stay true. No "|" characters inside a cell.
- Guard, strongest first — use the strongest one that fits:
    test: <path>::<name>   an automated test (path relative to the repo root; the name must appear in that file)
    check: <step-name>     a named step in .claude/guards.sh and .claude/guards.ps1
    review: <outcome>      last resort — an observable outcome two reviewers would judge the same way
  Wording corrections go into brand/banned-phrases.txt and use "check: content-lint", not review:.
- Added: YYYY-MM-DD.
- The guards' ledger-integrity step fails when a test: path or name is missing, a check: step doesn't exist in the runner,
  an ID repeats, or a committed row has disappeared or changed — vs HEAD and, when the branch has an upstream, vs its fork
  point, so an unpushed commit can't drop a row either (CI: the PR base or the pre-push commit; ALLOW_GUARD_CHANGE=1 only with the owner's OK).
- A live test: row makes the tests step fail while TEST_CMD is unset, and a live "check: content-lint" row makes content-lint fail
  while brand/banned-phrases.txt is missing or empty — configure the step before you add the row.
- The guard hook asks before any edit that would change or remove an existing row (appending new rows passes). Never delete, skip or weaken a guard without the owner's OK.

Example rows (incl. the data-pipeline binlog / jobs-table / worker-topology rows) live in claude-md/templates/REGRESSIONS.examples.md —
never in this file, because `grep -i "<area tag>" REGRESSIONS.md` would return an inactive example as if it were a live rule.
A fresh copy of this file is header-only and starts green.

Public-safe: this file is committed — no secrets, hosts, IPs or client names in any row.
-->
# REGRESSIONS — fix-once ledger

Every row must stay true. Grep by Area tag before editing; run the full guards before calling work done.

| ID | Area | Rule (must stay true) | Guard | Added |
|----|------|-----------------------|-------|-------|
