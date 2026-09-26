# Regression guard — code, config and ops

## Bug fix → test guard
1. Write the test first and run it. It must fail **for the expected reason** — the assertion about the bug, not an import error, typo, missing fixture or wrong path. Quote the failing line.
2. Fix the code, not the test. The new test passes and the rest of the suite stays green.
3. Tag it with the ledger ID so `grep -rn R-012` finds the guard: a comment on the line above (`# R-012: last page must include the final item`) or, for frameworks with string titles, in the title (`it('R-012 last page includes final item')`).
4. Row: `| R-012 | code/api | paginate() returns the final item on the last page | test: tests/test_paginate.py::test_last_page_includes_final_item | 2026-09-25 |`
   - `<path>` is relative to the project root; `<name>` must appear literally in that file. Class or parameter forms are fine (`path::TestX::test_y`, `test_y[case]`) — the runner looks for the last segment without `[…]`.
5. Flaky or slow to reproduce? Say so; don't retry until green and don't mark the test skip/xfail.

## Config / ops / data invariant → `check:` step
Use one when a unit test can't see the rule (server config, worker topology, migrations, CI settings, retention).
1. Add a named step to `.claude/guards.sh` **and** `.claude/guards.ps1` (same name — ledger-integrity fails if one runner lacks it). The templates carry commented examples (`mysql-binlog-expiry`, `worker-topology`):
   ```bash
   check_mysql_binlog_expiry() {
     grep -Eq '^[[:space:]]*binlog_expire_logs_seconds[[:space:]]*=[[:space:]]*86400[[:space:]]*$' infra/mysql/my.cnf \
       || { echo "ERROR: infra/mysql/my.cnf must set binlog_expire_logs_seconds=86400 (1 day)"; return 1; }
   }
   step mysql-binlog-expiry -- check_mysql_binlog_expiry
   ```
2. Prove it bites: run it once against a known-bad copy of the file and see `ERROR <step>: …`, then restore. Never break live systems to test a check.
3. Steps read files in the repo only — no network calls, no secrets, no production hosts, nothing fetched and executed.
4. Row: `| R-013 | ops/mysql | Binlog expiry stays 1 day (binlog_expire_logs_seconds=86400) | check: mysql-binlog-expiry | 2026-09-25 |`
5. Mark slow steps `slow` (`step <name> slow -- …` / `Step '<name>' -Slow { … }`) so `--fast` can skip them mid-task.

## The runner (`.claude/guards.sh`, `.claude/guards.ps1`)
- Output: one line per step — `OK <step>`, `ERROR <step>: <reason>`, `SKIP <step>: <reason>` — then `guards: PASS|FAIL - …` (that's the `<summary line>` in the evidence line). Full output goes to `.claude/guards.log` (gitignored); read only the failing step's section at the end of that log.
- `SKIP tests: not configured` means `TEST_CMD` / `$TestCmd` at the top of the runner is empty — set it (and `LINT_CMD`) when adding the runner to a project; a SKIP is not a pass for that step.
- **ledger-integrity** (guard of guards) fails when: an ID repeats · a `test:` file or name is missing · a `check:` step is missing from either runner · a row committed at `GUARD_BASE_REF` (default `HEAD`) is gone or changed — the ledger is append-only. Retiring a row is a change: it needs the owner's OK, given as `ALLOW_GUARD_CHANGE=1` (owner runs it) or the PR label `guard-change-approved` in CI.
- The guard hook asks before any edit that would change or remove an existing `REGRESSIONS.md` row or banned phrase, and before any edit to `.claude/guards.*` / `.claude/checks.*` (appending new rows passes) — that prompt is for the owner; don't work around it.
- `.claude/checks.sh` / `.claude/checks.cmd` are the owner's local, gitignored one-line triggers for the verify Stop hook (allowlisted projects only). Don't create or edit them unless asked.

## CI
- Copy `templates/github/regression-guards.yml` (claude-md repo) to `.github/workflows/`: runs the same runner on every PR, push to main and weekly, zero model tokens. Make the `guards` job a required check.
- Red CI on a PR → reproduce locally with `GUARD_BASE_REF=origin/<base> bash .claude/guards.sh`.
