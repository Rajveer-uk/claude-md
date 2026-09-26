---
# TEMPLATE (claude-md/templates/rules/content.md) -> copy to <project>/.claude/rules/content.md (optional, for repos with content).
# Loads only when Claude reads a file matching `paths` (dropped at /compact, reloads on the next matching read).
# Frontmatter, including these YAML comments, is removed before loading (zero tokens). Edit the globs to match your
# content dirs and keep them in sync with CONTENT_DIRS in .claude/guards.sh. In a content-only repo add "**/*.md".
paths:
  - "content/**"
  - "blog/**"
  - "posts/**"
  - "copy/**"
  - "marketing/**"
  - "emails/**"
  - "newsletters/**"
  - "social/**"
  - "landing-pages/**"
  - "brand/**"
  - "**/*.mdx"
---
# Content rules

- Before editing: `grep -i "mkt/" REGRESSIONS.md` and follow every matching row; pass those rows into any writer or editor hand-off.
- Voice: apply `brand/voice.md` (brand-voice skill) and the ai-writing-tells skill to every draft and edit.
- Never use a phrase from `brand/banned-phrases.txt`. A wording correction adds a line there plus a ledger row with `check: content-lint`; a voice correction appends `Updated: <date> — <rule> — <reason>` to `brand/voice.md` plus a row.
- Any figure, statistic, quote or claim without a source in the brief → `[VERIFY: <what to check>]`; never invent a source.
- Before done: run the full guards (`bash .claude/guards.sh`; Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File .claude\guards.ps1`) — `content-lint` must pass; put the `Guards:` line first in the report.
