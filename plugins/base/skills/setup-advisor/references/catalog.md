# Setup advisor — trusted catalog

The only sources the skill may suggest. "Always-on" is the `claude plugin details <name>` figure, measured September 2026; re-measure after an install, because releases change it. Every pick still needs evidence from the project.

## 1. claude-md packs — marketplace `claude-md-packs`

| Pack | Pick when | Always-on | Install |
|------|-----------|-----------|---------|
| `base` | Not installed. It is the main team; the other packs assume it | ≈2.9k | `claude plugin install base@claude-md-packs` |
| `marketing` | `mkt/` ledger rows, `content/`, `blog/` or `brand/` dirs, a marketing or content role | ≈0.86k (≈0.7k in context). Starts the Tavily and DataForSEO MCP servers (keys from env) | `claude plugin install marketing@claude-md-packs --scope local`; user scope only on marketing machines |
| `council` | `biz/` rows; pricing, hiring, architecture or positioning decisions | ≈0.5k | `claude plugin install council@claude-md-packs` |
| `ecc` | The project uses a stack ecc covers (Go, Rust, Java, Kotlin, Swift, C#, C++, Dart/Flutter, Python, TypeScript, React, Vue, Django, FastAPI, PHP) and base's agents don't already cover the need | **≈15.4k. Always state it** | `claude plugin install ecc@claude-md-packs --scope local`. Per project only: never user-wide, never on the account |

Marketplace missing from `claude plugin marketplace list` → `claude plugin marketplace add <owner>/claude-md`. Ask the owner for `<owner>`; never guess it.

## 2. Anthropic's official marketplace — `claude-plugins-official`

Source `anthropics/claude-plugins-official`. Claude Code normally registers it on its own at the first interactive terminal session; the `claude plugin` commands never do. Missing from `claude plugin marketplace list` → `claude plugin marketplace add anthropics/claude-plugins-official`.

**Anthropic-authored plugins only.** The same marketplace also lists partner plugins that live in other vendors' repos (MCP integrations, SaaS connectors). Treat those as third-party and never suggest them.

| Plugin | Pick when | Always-on | Notes |
|--------|-----------|-----------|-------|
| `claude-code-setup` | Not installed | ≈0.14k | Read-only automation recommender (`claude-automation-recommender`); step 2 of this skill uses it |
| `session-report` | The owner asks where tokens go; heavy subagent use | ≈0.07k | Local HTML report built from `~/.claude/projects`; nothing is uploaded |
| `claude-md-management` | A long or drifting `CLAUDE.md` | ≈0.18k | Proposes edits and applies only approved ones |
| `skill-creator` | The owner writes or tunes skills | ≈0.11k | Skip it if `anthropic-skills:skill-creator` is already on the account |
| `frontend-design` | React, Vue, Svelte or plain HTML/CSS UI work | ≈0.08k | |
| `commit-commands` | The owner wants commit and PR shortcuts | ≈0.10k | |
| `hookify` | Repeated owner corrections about tool actions ("never run X") | ≈0.29k + 4 hooks | Rules sit in gitignored `.claude/hookify.*.local.md`, so cloud sessions never see them; committed enforcement belongs in `.claude/guards.sh`. Needs Python 3.7+ |
| `security-guidance` | Auth, payments, input handling or secrets code | ≈0 + 5 hooks | Its Stop-hook and commit reviews send diffs to a model endpoint, which breaks base's zero-network posture: suggest `ENABLE_CODE_SECURITY_REVIEW=0` (pattern warnings only). Needs Python 3.8+ and Claude Code v2.1.144+. base's `security-auditor` and `secure-code-reviewer` already review |
| `plugin-dev` | The project is a Claude Code plugin or marketplace | ≈2.3k | Per project (`--scope local`) |
| `mcp-server-dev` | The project builds an MCP server | ≈0.5k | Per project |
| `agent-sdk-dev` | The project uses the Claude Agent SDK | measure | Per project |
| `code-review` · `feature-dev` · `pr-review-toolkit` · `code-simplifier` · `claude-security` | Only when the owner asks for that exact workflow | ≈0.02k · ≈0.24k · ≈2.0k · ≈0.06k · ≈0.69k + 3 hooks | They overlap base's `code-reviewer`, `tech-lead-orchestrator`, `ponytail` and `security-auditor`; prefer base |

**LSP code intelligence, one per detected language.** 0 always-on tokens, but each runs a language server that indexes the project (CPU and RAM on big repos). Install per project: `claude plugin install <plugin>@claude-plugins-official --scope local`. The server binary must be on `PATH`. It is a machine dependency: name it, and install it only on the owner's separate approval.

| Evidence | Plugin | Binary on `PATH` |
|----------|--------|------------------|
| `package.json`, `tsconfig.json`, `.ts` `.tsx` `.js` `.jsx` | `typescript-lsp` | `typescript-language-server` + `typescript` |
| `pyproject.toml`, `requirements*.txt`, `.py` | `pyright-lsp` | `pyright` |
| `go.mod` | `gopls-lsp` | `gopls` |
| `Cargo.toml` | `rust-analyzer-lsp` | `rust-analyzer` |
| `pom.xml`, `build.gradle`, `.java` | `jdtls-lsp` | `jdtls` |
| `.kt`, `.kts` | `kotlin-lsp` | `kotlin-lsp` |
| `*.csproj`, `.cs` | `csharp-lsp` | `csharp-ls` |
| `CMakeLists.txt`, `.c` `.cpp` `.h` | `clangd-lsp` | `clangd` |
| `composer.json`, `.php` | `php-lsp` | `intelephense` |
| `Gemfile`, `.rb` | `ruby-lsp` | `ruby-lsp` |
| `Package.swift`, `.swift` | `swift-lsp` | `sourcekit-lsp` |
| `.lua` | `lua-lsp` | `lua-language-server` |

## 3. Skills already on the owner's account

Listed as `anthropic-skills:<name>` in this session's skills (`/skills` shows a claude.ai sync group). Nothing to install. When the evidence fits, recommend using one, e.g. `docx`, `xlsx`, `pptx` or `pdf` for a docs or strategy role. Install column: `already on account — /anthropic-skills:<name>`. Its always-on cost is already paid.

**Duplicates → Optional cleanup — owner decides** (never a table row, never a removal command):
- `anthropic-skills:<x>` next to a pack skill `<x>` (e.g. `caveman`, `regression-guard`): two listings, two near-identical triggers.
- A pack skill or agent also copied into `~/.claude/skills|agents` or the project's `.claude/`.
- Not a duplicate: a pack installed locally and also present as `<name>@synced`. The local copy wins and the synced one shows as not loaded.

## Never suggest

Anything outside sections 1–3: partner or community plugins, MCP servers from other vendors (including ones Anthropic's recommender names), GitHub repos, package-registry skills. Never `ecc` user-wide or on the account. Never `marketing` on the claude.ai account unless the owner accepts its MCP servers starting in every signed-in Claude Code session.
