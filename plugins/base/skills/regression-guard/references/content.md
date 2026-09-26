# Regression guard — marketing, docs and other content

Files at the folder root: `REGRESSIONS.md` (rows tagged `mkt/…`, `docs/…`, `biz/…`), `brand/banned-phrases.txt`, `brand/voice.md`, `.claude/guards.sh`. In a content-only folder `tests`/`lint` print SKIP; `content-lint` and `ledger-integrity` still run.

## Wording correction → banned phrase (automated)
- "Don't say X" → append `X` as one line to `brand/banned-phrases.txt` (plain text, case-insensitive; `#` lines are comments) and add a row with `check: content-lint`:
  `| R-021 | mkt/email | Email copy never says "game-changer" | check: content-lint | 2026-09-25 |`
- Prefer this over a `review:` row whenever the rule is a literal phrase — the runner enforces it on every run at zero tokens.
- **Negative example first:** ban the narrowest phrase that catches the problem. Before adding a line, grep the content folders for it: banning `best` would also flag "best practice" and "best regards" — ban `best-in-class` instead. If a legitimate use remains, make the phrase longer or use a `review:` row.
- The content-lint step scans `CONTENT_DIRS` (top of `.claude/guards.sh`); `brand/` and `REGRESSIONS.md` are never scanned. Keep `CONTENT_DIRS` in sync with `.claude/rules/content.md` paths.
- Removing or loosening a banned phrase needs the owner's explicit OK.

## Voice or tone correction → `brand/voice.md`
- Not a single phrase (tone, structure, audience, claims style) → append to `brand/voice.md`:
  `Updated: 2026-09-25 — <rule> — <reason>` (the brand-voice skill applies this file), plus a ledger row whose guard is a `review:` outcome.
- Never rewrite or delete earlier `Updated:` lines; a newer line supersedes an older one.
- Say so: "Noted in the voice profile and the ledger so it won't come back."

## `review:` rows must be objective
- Phrase the outcome as something visible in the output, not a process:
  - ✓ `review: every price in the draft states "incl. VAT"`
  - ✗ `review: be careful with pricing`
- Two reviewers must reach the same pass/fail verdict. If you can't phrase it that way, it belongs in `brand/voice.md`, not the ledger.
- Promote when you can: literal phrase → `brand/banned-phrases.txt`; length, format or required-disclaimer rules → a `check:` step in `.claude/guards.sh` (see `code.md`).
- Before done, list each matching `review:` row with its evidence: `R-021 ✓ (pricing.md:14 "£49 incl. VAT")`.

## Facts and claims
- Any figure, statistic, quote, price, date or claim without a source in the brief → leave `[VERIFY: <what to check>]` inline; never invent a source.
- To stop unresolved markers shipping, add `[VERIFY:` to `brand/banned-phrases.txt` — only when `CONTENT_DIRS` covers publish-ready folders, not drafts.
