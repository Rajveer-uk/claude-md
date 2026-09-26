---
name: brand-voice
description: Applies the project brand voice (brand/voice.md) to drafts and reviews, and logs each owner correction so it holds for every writer. Use when writing, editing or reviewing on-brand copy.
---

# Brand voice — apply it, keep it current

One voice source per project: `brand/voice.md`. This skill applies it; `ai-writing-tells` (generic tells) and `brand/banned-phrases.txt` (project wording bans) stay the ban lists — don't restate them. This file is self-contained; `references/` holds the profile skeleton and the long-form checklist for when you build a profile or want the full list.

## 1. Find the profile

Stop at the first hit:
1. `brand/voice.md` in the project or working folder. In Cowork, resolve it against the user's folder, not the plugin directory.
2. A brand-voice knowledge file in the chat Project.
3. Neither → don't invent a voice. Write plain, specific prose, say "No voice profile found" in your result, and suggest building one from 3 approved samples (skeleton: `references/voice-profile-template.md`, or `templates/brand-voice.md` in the claude-md repo).

## 2. Apply it while drafting

- **Voice is constant.** Honour every row of the We are / We are not table. Show the 2–3 "We are" attributes that fit this piece; never cross a "We are not" boundary.
- **Tone flexes by channel.** Set formality, energy and technical depth from the channel row. Channel missing → use the nearest row and say which.
- **Terminology.** Product and feature names exactly as the Use column writes them; never a Not term.
- **Claims.** Every figure, rate, fee, price, discount, percentage, guarantee, comparison, quote or testimonial traces to supplied material. Missing → write `[VERIFY: what is needed]`, never a guessed value. Words the profile lists as needing conditions carry them in the same sentence. These flags add to an agent's truthfulness guardrail; they never replace it.
- **Ledger.** Matching `mkt/` rows in `REGRESSIONS.md` are hard constraints.

## 3. Review mode

Check in this order:
1. Matching `mkt/` rows (cite the ID), `brand/banned-phrases.txt` phrases (case-insensitive), `ai-writing-tells` patterns.
2. Voice: no "We are not" crossed; the fitting "We are" attributes visible.
3. Tone for the channel; one primary CTA where the channel needs one.
4. Terminology and house style.
5. Claims, attribution and required disclaimers — always, with or without a profile; list every open `[VERIFY: …]`.

Return a table `| Issue | Location | Severity | Fix |`, sorted High → Low, then before/after rewrites for the top 3 and a separate **Claims & compliance** list. Severity comes from the profile's severity table; without one: **High** = crosses a "We are not", breaks a `mkt/` row or banned phrase, or carries an unsupported or non-compliant claim · **Medium** = wrong tone for the channel or wrong terminology · **Low** = style polish. Review only means the file stays unchanged unless the owner asks for fixes.

## 4. When the owner corrects the voice

Record it once so it holds for every writer and every later piece:

1. Apply the correction to the current piece.
2. Append one line to the Updated log at the end of `brand/voice.md` — never rewrite earlier lines:
   `Updated: YYYY-MM-DD — <rule> — <reason>`
3. If the correction bans wording, add the exact phrase as a new line in `brand/banned-phrases.txt`; the guards `content-lint` step enforces it from then on.
4. Add one row to `REGRESSIONS.md` with the next unused ID (the base `regression-guard` skill owns the format):
   `| R-0nn | mkt/<channel-or-topic> | <rule that must stay true> | check: content-lint | YYYY-MM-DD |`
   For a correction a phrase list can't catch (tone, structure), the Guard is `review: <observable outcome two reviewers would judge the same way>`.
5. Tell the owner in one line what was recorded where.

No write access, or working in chat? Output the voice-log line, the phrase and the ledger row for the owner to paste. Removing a banned phrase or ledger row needs the owner's explicit OK.
