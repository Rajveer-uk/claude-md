---
name: regression-guard
description: Bug fix, regression or owner correction ("that's wrong", "again")? Guards it once in REGRESSIONS.md; before editing an area and before saying done, verifies nothing broke. Not for brainstorming.
---

# Regression guard — fix once, never twice

The ledger `REGRESSIONS.md` (project/folder root) is the durable memory: one row per fix, each pointing at a guard that fails if the fix regresses. Green guards cost ~0 tokens, so don't re-explain history in chat.

**Row:** `| ID | Area | Rule (must stay true) | Guard | Added |`
- **ID** `R-001`… never reused. Rows are never deleted — retire one by prefixing its Rule with `retired: <date> <reason> —`, owner OK only.
- **Area** one lowercase tag: `code/<area>`, `mkt/<channel-or-topic>`, `ops/<system>`, `docs/<area>`, `biz/<area>`.
- **Guard**, strongest that fits: `test: <path>::<name>` > `check: <step-name>` (a step in `.claude/guards.sh`) > `review: <observable outcome two reviewers would judge the same way>` (last resort).
- **Added** `YYYY-MM-DD`. No ledger yet → create it with that header row.

## On a bug fix or owner correction
1. Reproduce: code → a failing test that fails for the expected reason; content → name the exact rule broken.
2. Fix the code or content, not the test or guard.
3. Add the strongest guard (ladder above). A wording correction → a line in `brand/banned-phrases.txt` + `check: content-lint`.
4. Append one ledger row with the next free ID.
5. General lesson? Propose a one-line diff to `~/.claude/CLAUDE.md` that passes "Would removing this cause mistakes?" — apply only on approval. If a script can check it, make it a `check:` step instead.
6. Can't write files or run the test here (no workspace, read-only surface, a snippet pasted in chat, or the run is denied/blocked)? Attempt a run at most once; if it's denied, never try it again (not via another command either). Still show both in the reply: the regression test in a code block (it must fail before the fix) and the ledger row to paste in the exact format `| R-0xx | <area tag> | <rule that must stay true> | test: <file>::<test name> | YYYY-MM-DD |`, and say "test not run (denied)" where that applies.

## Before editing an area
- `grep -i "<area tag>" REGRESSIONS.md` → read only the matching rows, never the whole ledger.
- Subagents don't see this conversation: paste the matching rows into every hand-off brief.
- Multi-file work: run the guards once first as a baseline; report pre-existing failures up front instead of blaming them on the change.

## Before "done"
- Run the full guard set once, yourself, in the main thread (a subagent's summary hides the detail): `bash .claude/guards.sh` — Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File .claude\guards.ps1`. `--fast` / `-Fast` is for mid-task loops only.
- Check each matching `review:` row against the actual output.
- First line of the report, exactly one of:
  - `Guards: <command> → exit 0, <summary line>; R-00x ✓ R-00y ✓`
  - `Guards: RED — <step>: <reason>` — then say what's left; don't claim done.
- Task has an AC list (`requirements-gate`)? Line 2 is `Requirements: n/m met`; an unmet AC means not done, like RED.
- No runner in this project yet → run its test + lint commands, report them in the same format, and offer to add `.claude/guards.sh` (template `templates/guards.sh` in the claude-md repo).
- No verify hook on this surface (cloud session, Desktop without user hooks) → suggest the owner types:
  `/goal The conversation shows bash .claude/guards.sh run after the last edit with exit 0 and its summary line, and every REGRESSIONS.md row for the touched areas marked ✓ — or stop after 20 turns` (switch out of Plan first — `/goal` doesn't change the permission mode)

## Never
- Delete, skip, loosen or rename a guard, test, check step or banned phrase, or edit a ledger row, without the owner's explicit OK. `ALLOW_GUARD_CHANGE=1` is the owner's switch, not yours.
- Make a red guard green by changing the guard. If a guard itself is wrong, stop and say why.

## Detail — read only the one that applies
- Code, config or ops work → `references/code.md`
- Marketing, docs or other content → `references/content.md`
- No shell (claude.ai chat, Projects, Cowork without a terminal) → `references/chat.md`
