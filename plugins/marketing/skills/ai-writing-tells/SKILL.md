---
name: ai-writing-tells
description: Shared ban list of AI-writing tells for all marketing copy, preloaded by the marketing writers and content-editor. Use when drafting or editing marketing copy to strip generic AI patterns.
---

# AI-writing tells — the shared ban list

One list, one owner. The marketing writing agents (`content-writer`, `conversion-copywriter`, `email-campaign-writer`) apply it while drafting; `content-editor` enforces it on existing drafts — all four preload it through their `skills:` field. Don't restate this list in agent prompts — reference this skill.

## Banned outright (delete or rewrite on sight)

- **Throat-clearing openers:** "In today's rapidly evolving landscape…", "In today's competitive landscape…", "In today's world…", "Now more than ever…"
- **Hype adjectives:** "game-changer / game-changing", "cutting-edge", "revolutionary", "world-class", "next-level", "seamless", "robust" (as filler)
- **Empty bridges:** "Here's why this matters", "Let's dive in", "But that's not all"
- **Engagement bait:** closing questions fishing for comments, fake vulnerability arcs, manufactured urgency
- **Generic filler:** bio padding, hedging ("arguably", "it could be said"), over-listing where prose reads better
- **Hollow conversions:** generic CTAs ("learn more", "click here"), hollow social proof, unearned superlatives

## The test

If a line could drop unchanged into a competitor's campaign — or any article on the topic — rewrite it with something specific: an artifact, an example, a number, a named mechanism.

## What replaces the tells

- Lead with the concrete thing, then explain; proof over adjectives.
- Specific, active prose in the brand voice; claims backed by supplied material only.
- One specific, earned CTA per piece.

## Project additions

A project's `brand/banned-phrases.txt` extends this list: one phrase per line, `#` lines and blank lines ignored, matched case-insensitively. Treat every phrase in it as banned outright. The guards `content-lint` step enforces that file mechanically on every guard run, so an owner's wording correction goes into that file (it then holds for every writer) rather than into this skill.
