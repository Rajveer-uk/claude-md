# Attribution & provenance

This pack (`plugins/ecc`) is a **curated, security-audited subset** of the
**ECC** project, vendored into this repository.

- **Upstream:** [affaan-m/ECC](https://github.com/affaan-m/ECC) — "Everything Claude Code"
- **Author:** Affaan Mustafa (<https://ecc.tools>)
- **License:** MIT (full text below)
- **Snapshot commit:** `81af40761939056ab3dc54732fd4f562a27309d0`
- **Vendored:** shallow snapshot of ECC's `agents/`, `skills/`, and `commands/` directories only.

## What was included

From 435 upstream items evaluated, **193 were vendored**: **42 agents, 117 skills, 34 commands**. This landed in three passes:

1. **Curated engineering core (171).** Broadly useful agents/skills/commands, dropping duplicates of our `base`/`marketing`/`council` packs, niche domains, and unresolved security risks.
2. **Duplicates re-evaluated (+12).** See below.
3. **ECC harness / meta-tooling (added +133, then trimmed to +10).** ECC's harness layer was vendored on request and adapted, then cut back to 10 standalone agent-engineering knowledge skills for token economy — see below.

A second, independent security-verify pass excluded `canary-watch`, `flox-environments`, and `jira-integration` (hard network dependencies, writes outside the workspace, or live-token requirements). ~242 upstream items remain un-vendored (the ECC harness/command machinery, niche domains, and skills that need an external MCP the baseline blocks).

A later duplication audit removed `agents/architect.md` (covered by `code-architect` + base `tech-lead-orchestrator`) and `skills/security-bounty-hunter/` (covered by base `security-auditor` + `secure-code-reviewer`), and renamed `build-error-resolver` → `typescript-build-resolver` and `pytorch-build-resolver` → `pytorch-runtime-debugger` to match what they actually do. **Current totals: 41 agents, 116 skills, 34 commands.**

## Duplicates re-evaluated

The initial pass skipped items overlapping our `base`/`marketing`/`council` packs. Those overlaps
were then re-examined **head-to-head** (each ECC item read against our version). No ECC agent beat
ours, but **12 ECC skills/commands were added back** because they add distinct, self-contained value
our agents don't carry: skills `api-design`, `deployment-patterns`, `fastapi-patterns`,
`postgres-patterns`, `laravel-security`, `laravel-verification`, `market-research`, `seo`; commands
`fastapi-review`, `update-codemaps`, `update-docs`, `prp-plan`. Three further comparisons kept our
version but grafted one small ECC improvement into it (those edits are in the `base`/`marketing`
packs, not here).

## ECC harness / meta-tooling — added, then trimmed

On request, ECC's **harness / meta-tooling layer** (133 items — 7 agents, 75 skills, 51 commands: agent-eval / `gan-*`, `orch-*`, `hookify*`, `instinct-*`, `multi-*`, `epic-*`, session/skill management, `configure-ecc`, etc.) was vendored, audited, and adapted — every file got a provenance note, **48 bundled script/config files were stripped** from 9 skills to keep the pack markdown-only, dead refs were retargeted, and an injection/exfil scan came back clean (only benign documentation, e.g. a security scanner that *names* exfiltration as a thing to detect).

It was then **trimmed for token economy**: the machinery is **inert here without ECC's own runtime/hooks/instinct store**, so all 7 harness agents, all 51 harness commands, and 65 of the 75 skills were removed (≈197K tokens, together with the `angular-developer` reference deep-dive). **10 standalone agent-engineering knowledge skills were kept** — they read as useful docs on their own: `agent-harness-construction`, `agent-architecture-audit`, `agent-introspection-debugging`, `agentic-engineering`, `ai-first-engineering`, `autonomous-loops`, `iterative-retrieval`, `eval-harness`, `recursive-decision-ledger`, `agentic-os`. These retain the provenance note.

## What was deliberately NOT vendored

To preserve this repo's least-privilege, no-network posture, ECC's **runtime wiring** was **excluded
entirely** even where its harness *content* was vendored: `install.sh` / `install.ps1` / `npx ecc-install`,
the repo-level `hooks/` and `rules/`, MCP configs, and all cross-harness directories (`.codex`, `.cursor`,
`.gemini`, `.zed`, `.opencode`, etc.). **Every vendored skill is pure markdown — all bundled
shell/python/js/powershell scripts were stripped.**

## Modifications made during the security audit

The following files were edited from their upstream form (minimal, surgical changes only):

| File | Change |
|------|--------|
| `agents/code-architect.md` | Normalized malformed `tools:` to a quoted JSON array |
| `agents/code-simplifier.md` | Normalized `tools:` to a quoted JSON array |
| `agents/comment-analyzer.md` | Normalized `tools:` to a quoted JSON array |
| `agents/pr-test-analyzer.md` | Fixed malformed unquoted `tools:` array |
| `agents/silent-failure-hunter.md` | Fixed `tools:` array; dropped unused `Bash` (pure static reviewer) |
| `agents/type-design-analyzer.md` | Fixed malformed unquoted `tools:` array |
| `agents/tdd-guide.md` | Fixed `tools:`; removed ECC-specific eval-harness addendum |
| `skills/data-throughput-accelerator/SKILL.md` | Normalized scalar `tools:` to a JSON array |
| `skills/benchmark-optimization-loop/SKILL.md` | Normalized scalar `tools:` to a JSON array |
| `skills/latency-critical-systems/SKILL.md` | Fixed `tools:` array; dropped `Write` |
| `skills/mcp-server-patterns/SKILL.md` | Removed a broken ECC relative-doc cross-reference |
| `skills/mle-workflow/SKILL.md` | Trimmed ECC-specific install/surface references |
| `skills/search-first/SKILL.md` | Trimmed ECC/Codex-specific references (harness-agnostic) |
| `skills/tdd-workflow/SKILL.md` | Replaced an ECC-internal setup-script reference with generic guidance |
| `skills/postgres-patterns/SKILL.md` | Retargeted `database-reviewer` refs → `database-expert` |
| `skills/laravel-security/SKILL.md` | Modernized middleware/CSRF wiring to the Laravel 11/12 slim skeleton |
| `commands/fastapi-review.md` | Dropped a dangling `security-scan` skill reference |
| (pack-wide) | Retargeted dangling cross-refs: `security-reviewer`→`security-auditor`, `database-reviewer`→`database-expert`, `code-explorer`→`code-archaeologist`; removed leftover `security-scan` refs |
| (harness pass — 133 files) | Added a provenance/limitation admonition to every vendored harness agent/skill/command |
| (9 harness skills) | Stripped 48 bundled script/config files to keep the pack markdown-only |
| `agents/conversation-analyzer.md` | Normalized unquoted `tools:` array to JSON |
| `skills/security-scan/SKILL.md` | Retargeted `everything-claude-code:security-reviewer` → `security-auditor` (later removed in the trim) |
| (token-optimization trim) | Removed the inert ECC harness machinery — 7 agents, 51 commands, 65 skills — plus `angular-developer/references/`; kept 10 standalone knowledge skills (≈197K tokens saved) |

## Notes for users

- The repo's `settings.json` baseline still governs the network: `WebFetch`/`WebSearch` and network
  Bash (`curl`/`wget`/`Invoke-WebRequest`) are denied session-wide, so any skill that assumes web
  access is blocked by default.
- `skills/github-ops` operates via the authenticated `gh` CLI (GitHub's own API), not raw web fetches;
  it needs `gh` installed and logged in.
- `skills/inherit-legacy-style` can optionally install a user-gated `PreToolUse` hook into
  `settings.json` — review before accepting that prompt.

---

## MIT License (upstream ECC)

```
MIT License

Copyright (c) 2026 Affaan Mustafa

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
