<!--
TEMPLATE (claude-md/templates/PROGRESS.md) — multi-session handoff. Copy to the project root only for work that spans sessions or apps
(terminal → Desktop → cloud); single-session tasks don't need it.
- Session start: read this file and `git log --oneline -10`, then run the guards once as a baseline (so pre-existing failures aren't blamed on new work).
- Session end (and before /clear, /compact or switching apps): update every section, then commit it with the work so any surface can pick it up.
- One item "In progress" at a time. "Done" needs evidence: the command run, its exit status and the runner's summary line — a claim is not proof.
- Record failed approaches and why, so the next session doesn't retry the same dead end.
- This file is in-flight state and disposable. A fixed bug or owner correction graduates into REGRESSIONS.md (row + guard) — the ledger
  is the permanent memory, not this file. Delete or archive PROGRESS.md when the work ships.
- Read it on demand; never `@`-import it from CLAUDE.md. Public-safe: no secrets, hosts, IPs or client names.
-->
# Progress: <task / feature name>

**Goal:** <the outcome, and the test/check that proves it's done>
**Plan:** `<path to plan file, if any>` · **Branch:** `<branch>` · **Updated:** YYYY-MM-DD

## Done (with guard evidence)

| Item | Evidence (command → exit, summary line) | Ledger |
|------|------------------------------------------|--------|
| <item> | `bash .claude/guards.sh` → exit 0, `<summary line>` | <R-00x if a fix/correction graduated, else —> |

## In progress (one at a time)

- <item> — <current state> — <next concrete step>

## Next

1. <item> — <how it will be verified>

## Failed attempts (and why) — don't retry without new information

- YYYY-MM-DD — <approach> — <why it failed / what it broke>

## Decisions

- YYYY-MM-DD — <decision> — <reason> — <approved by>

## Open questions / known limits

- <question or limit> — <who can answer>
