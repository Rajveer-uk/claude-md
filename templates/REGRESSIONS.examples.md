# REGRESSIONS — example rows (reference only — never copy this file into a project)

These examples live outside `templates/REGRESSIONS.md` on purpose: a project's ledger is read with
`grep -i "<area tag>" REGRESSIONS.md`, and an inactive example inside that file would be returned as if it
were a live rule (a live headless test cited a non-existent "R-002" that way).

**To adopt one:** copy the row under the table header in your project's `REGRESSIONS.md`, change its `EX-` ID to
your next free `R-` ID, drop the `_(example…)_` marker, and create its guard first (the test, or the `check:`
step in `.claude/guards.sh` and `.claude/guards.ps1`).

- EX-001 to EX-004 show one row per area type.
- EX-005 to EX-007 come from a data-pipeline project — in that project copy all three and add the two `check:`
  steps they name (`mysql-binlog-expiry`, `worker-topology`; commented out at the bottom of `templates/guards.sh`
  and `.ps1`); EX-006 stays a `review:` row until the throughput balance can be asserted from config.
- EX-008 and EX-009 cite built-in steps of `templates/guards.sh` / `.ps1` (`no-stubs`, `spec-integrity`), so there
  is no step to write; give each row your own area tag.

| ID | Area | Rule (must stay true) | Guard | Added |
|----|------|-----------------------|-------|-------|
| EX-001 | code/api | _(example)_ Invoice totals round half-up to 2 decimal places (bug: 0.005 rounded down). | test: tests/test_invoice.py::test_total_rounds_half_up | 2026-01-15 |
| EX-002 | mkt/email | _(example)_ Email copy never says "game-changer" (owner correction; the phrase is in `brand/banned-phrases.txt`). | check: content-lint | 2026-01-20 |
| EX-003 | docs/setup | _(example)_ Every shell command in `docs/install.md` has a Windows PowerShell equivalent. | check: docs-windows-parity | 2026-02-02 |
| EX-004 | biz/pricing | _(example)_ Quotes and proposals use only prices from `pricing/price-list.md`; no discount without owner OK. | review: every price in the draft equals the price-list figure and no unapproved discount appears | 2026-02-10 |
| EX-005 | ops/mysql | _(example from a data-pipeline project)_ MySQL binlog expiry stays at 1 day (`binlog_expire_logs_seconds=86400`) — 1.1GB binlogs have filled the disk before. | check: mysql-binlog-expiry | 2026-09-25 |
| EX-006 | ops/queue | _(example from a data-pipeline project)_ Stream-worker vs queue-worker throughput stays balanced so the `jobs` table doesn't refill (past incident: 30M rows). | review: any change to stream-worker or queue-worker rate, batch size, concurrency or schedule states jobs/min produced vs consumed, and consumed ≥ produced | 2026-09-25 |
| EX-007 | ops/workers | _(example from a data-pipeline project)_ Topology stays six stream workers (companies, officers, charges, psc, insolvency, filings) + one queue worker. | check: worker-topology | 2026-09-25 |
| EX-008 | code/api | _(example)_ No added line carries a TODO/FIXME/XXX/HACK without a ticket ref (`TODO(#123)`), a not-implemented stub, an elision comment ("... rest of code unchanged"), a stub or placeholder comment, a newly skipped test or a conflict marker, unless the line says `stub-ok: <reason>` (past incident: "tests pass" hid a stubbed handler). | check: no-stubs | 2026-09-27 |
| EX-009 | docs/specs | _(example)_ A spec AC marked `met` cites evidence (file:line, test name, or command + exit code) and every `test:` path it names exists; `specs/*.features.json` entries are never removed, their description/verify change only with owner OK, and `passes: true` carries evidence. | check: spec-integrity | 2026-09-27 |

Public-safe: committed with the config repo — no secrets, hosts, IPs or client names in any row.
