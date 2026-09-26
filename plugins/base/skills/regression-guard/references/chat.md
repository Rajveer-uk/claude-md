# Regression guard — chat (no shell)

Applies in claude.ai chat, Desktop chat, claude.ai Projects, mobile, and any session that can't run `.claude/guards.sh`. You can't edit the ledger here, so the owner pastes what you produce.

## Where the ledger lives
- A claude.ai Project for the role holds `REGRESSIONS.md` as a knowledge file (plus `brand/voice.md` and `brand/banned-phrases.txt` for content work).
- No Project, or the file isn't attached → ask the owner to paste the rows for the area you're working on.

## Before drafting
- Find the rows whose Area matches the task (for example `mkt/email`, `biz/pricing`) and treat each Rule as a hard constraint.
- Content: apply every line of `banned-phrases.txt` and the latest `Updated:` lines in `voice.md`.

## Before handing over
- Check the draft against each matching row and each banned phrase, then put the result on the first line:
  - `Guards: manual check (no shell) → R-004 ✓ R-009 ✓; banned phrases: none found`
  - `Guards: RED — R-009: <reason>` — then fix it, or say what's blocking. Don't call it done while red.
- Give evidence for `review:` rows: `R-004 ✓ (para 2: "£49 incl. VAT")`.

## When the owner corrects you
1. Apply the fix to the draft.
2. Output the new ledger row in a code block for the owner to paste into the knowledge file:
   `| R-0xx | <area> | <rule that must stay true> | <guard> | YYYY-MM-DD |`
   Next ID = highest ID you can see + 1; if you can't see the whole ledger, write `R-???` and ask the owner to number it.
3. Wording correction → also output the line for `banned-phrases.txt`, with guard `check: content-lint`. Voice correction → also output `Updated: YYYY-MM-DD — <rule> — <reason>` for `voice.md`, with a `review:` guard.
4. Say where each line goes ("add to the Project knowledge files so every future chat applies it"). Never claim it is saved.
5. A lesson for every chat, not just this area → propose one line for Settings → General → "Instructions for Claude"; the owner applies it.

## End of session
- Offer: "Here are this session's corrections as REGRESSIONS rows" — rows only, ready to paste.
