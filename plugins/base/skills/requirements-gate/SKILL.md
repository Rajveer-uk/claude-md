---
name: requirements-gate
description: Use before implementing any feature or change request that is short or vague, spans more than one file, or implies unstated follow-on work (tests, other callers, docs, config) — from a prompt, issue, ticket, PR or review comment, TODO or plan item. Lists AC1…ACn (asked + implied), asks only where readings change the work, and maps every AC to evidence before done. Skip one-line edits, questions and reviews.
---

# Requirements gate — say what done means, then prove it

A short request often hides the test, the other caller, the `.ps1` twin, the doc line; built literally, that half never happens. Make the whole intent explicit before the first edit and prove each part before "done". No extra scope: every AC is asked for or implied, and the change stays the smallest one that meets them all.

## 1. Skip
No AC list and no questions when the diff fits one sentence (a rename, a typo, one config value) or the ask is a question, an explanation or a review.

## 2. Extract
- Read the relevant sources first: the touched files, their callers and tests, the linked issue or thread, and the matching rows of `grep -i "<area tag>" REGRESSIONS.md`.
- Restate the request as `AC1…ACn`, one observable behaviour each: "When <trigger>, <component> shall <result>" (or Given/When/Then), tagged `asked` or `implied: <why>`, with a verify-by: `test: <path>::<name>` · `check: <guard step>` · `cmd: <command>` · `manual: <observable outcome>`.
- Walk `references/implied-work.md` for the domain; each item that applies becomes an `implied` AC.
- Add `Out of scope:` and `Assumptions:` (defaults you picked).
- PR or review comments → one AC per unresolved thread.

## 3. Clarify gate
Per gap:
- Answerable from the repo (pattern, config, test, docs) → look it up; don't ask.
- Low impact → choose a default and list it under Assumptions.
- Readings lead to materially different work → AskUserQuestion pop-up, batched: 1–4 questions per call, 2–4 options each, the recommended option first with " (Recommended)" at the end of its label, `header` ≤12 chars. One round; a second only if an answer opens a new fork.
- Owner says "you decide" → state the pick in one line and get a yes.
- No pop-up here (claude.ai chat, headless, `dontAsk`) → numbered questions at the top of the reply, each with your default; build only what no answer changes.
- Running as a subagent → return `NEEDS_CONTEXT: <questions>` as the first line instead of guessing; the main thread asks.

This skill requires the gate, so auto mode still asks when a fork is material.

## 4. Persist
- Small task: the AC list is the first block of the plan or reply.
- Multi-file feature or vague request: `/spec` writes `specs/<slug>.md` with every AC `open`, then `/implement-plan specs/<slug>.md`.
- Never delete or reword an AC to make it pass. Dropping or deferring one needs the owner's OK: `deferred (owner OK)`.

## 5. Build
Smallest change that meets every AC. Subagent briefs carry their ACs verbatim. Commits may carry a trailer: `Refs: AC2, AC5`.

## 6. Audit before done
After the guard run, one table:

| AC | Source | Status | Evidence |
|----|--------|--------|----------|
| AC1 | asked | met | `app/export.py:42`; `pytest tests/test_export.py::test_csv_header` → exit 0 |
| AC2 | implied: CSV must match the page filter | met | `pytest tests/test_export.py::test_csv_respects_status` → exit 0 |

- Status: `met` · `partial` · `not met` · `deferred (owner OK)`. Evidence: `file:line`, a test name, or a command and its exit code; no evidence found = `not met`.
- `Unrequested changes:` each changed file (`git diff --stat`) that maps to no AC — justify it in one line or revert it.
- Any AC not met → not done: finish it or ask.
- Multi-file work: hand the spec or plan path, this table and the `git diff --stat` summary to the `completion-auditor` agent and report its verdicts.

## 7. Report
Line 1: the `Guards: …` line from `regression-guard`. Line 2: `Requirements: 5/5 met` or `Requirements: 4/5 — AC3 partial: <reason>`. Then the table, then `Assumptions:` — every default you picked that the owner hasn't confirmed — so the owner sees them in the done report, not only in the first reply. No edits possible (chat, repo not in the workspace)? The same table and Assumptions go with the code you hand over.

## 8. Fix once
- Owner says "you missed X" → owner correction → `regression-guard` (guard for X + ledger row).
- A missed category (say, the `.ps1` twin of a `.sh` change) → propose one line for `references/implied-work.md`, or better a `check:` step; apply on the owner's OK.
