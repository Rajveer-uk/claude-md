---
description: "'what should I install' triggers setup-advisor; the reply recommends trusted, stack-matched installs with exact commands, proposes Anthropic's claude-code-setup, and never proposes removing anything."
expected_outcome: "Skill setup-advisor fires; reply includes claude-code-setup@claude-plugins-official, a TypeScript or Python LSP plugin, no uninstall/disable/remove command, and ≈15k tokens stated if ecc is suggested."
tags: [skill-trigger, setup-advisor, smoke]
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

What should I install for Claude on this project? The repo isn't in this workspace, so here is what's in it:

- A Next.js web app in TypeScript: `package.json` lists `next`, `react` and `typescript`, and `tsconfig.json` sits at the root.
- A small Python worker in `worker/` with its own `pyproject.toml`.
- `REGRESSIONS.md` has rows tagged `code/web`, `code/worker` and `mkt/blog`, and there is a `content/blog/` folder of posts.
- The only plugin installed on this machine is `base@claude-md-packs`.

Give me your top picks with the exact install commands.
