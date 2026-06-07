# Claude Code Configuration — polyglot, security-vetted

A lean, layered, **stack- and OS-agnostic** configuration for [Claude Code](https://claude.com/claude-code): a global agent team plus per-project memory that adapts to whatever language, framework, package manager, and build tool a project actually uses. The agents install once and are reused across every project; each project gets its own `CLAUDE.md`.

Every file in this repo was produced through a full multi-dimension security audit (prompt-injection, permissions/blast-radius, secret exposure, context leakage, network/exfiltration, supply chain, provenance, and cross-file combination risks) with each finding independently verified. See [`setup.md`](setup.md) to install.

## What's inside

```
.
├── CLAUDE.md                     # project-root template (copy one into each project)
├── setup.md                      # install guide — Windows (PowerShell) + Ubuntu (bash)
├── council-and-network-config.md # LLM council + opt-in network connector (setup + security model)
├── .gitignore
├── templates/CLAUDE.package.md   # per-package / per-subsystem template (loads on demand)
├── managed/managed-settings.json # optional admin policy — unbreakable bypass-disable + core secret denies
└── .claude/
    ├── settings.json             # security baseline — install at USER scope (~/.claude/)
    ├── skills/council/SKILL.md    # /council — convene the decision council
    ├── hooks/
    │   ├── guard.ps1  / guard.sh    # optional: block secret-read/egress + over-privileged agent generation
    │   ├── format.ps1 / format.sh   # optional PostToolUse: auto-format the edited file (project-local tools)
    │   └── verify.ps1 / verify.sh    # optional Stop: run the project's allowlisted checks before finishing
    └── agents/                   # 35 agents: 22 engineering · 7 marketing/content · 6 council
```

## Design principles

- **Stack-agnostic + dynamic.** Universal specialists handle any ecosystem; `project-analyst` detects the stack, `team-configurator` prefers a framework-specific agent and generates a `<framework>-expert` on demand. Curated experts ship for the recurring stacks (Laravel, React+Tailwind/shadcn, Frappe, n8n).
- **Least privilege, no network by default.** Every agent declares an explicit minimal `tools` list. **33 of 35 agents have zero network tools.** Network is opt-in, per-agent, and never inherited (see the connector below).
- **OS-agnostic, layered & lean, self-improving.** Identical files across Windows/macOS/Linux; a small root `CLAUDE.md` points to on-demand per-package files; agents update `CLAUDE.md` when corrected.

## The agent team (35)

**Engineering (22).** Planning/review on `opus` (`tech-lead-orchestrator`, `api-architect`, `security-auditor`, `code-reviewer`); execution/analysis on `sonnet` (`project-analyst`, `team-configurator`, `backend-developer`, `frontend-developer`, `database-expert`, `ui-ux-designer`, `test-engineer`, `debugger`, `devops-troubleshooter`, `performance-optimizer`, `dependency-manager`, `deployment-engineer`, `code-archaeologist`); curated stack experts (`laravel-expert`, `react-tailwind-expert`, `frappe-expert`, `n8n-expert`); docs on `haiku` (`documentation-specialist`).

**Marketing & content (7).** Draft/strategy, no network: `conversion-copywriter`, `content-writer`, `content-editor` (haiku), `email-campaign-writer`, `growth-strategist` (opus). 🌐 **Network-enabled (opt-in, read-only):** `content-researcher` (Tavily web search) and `seo-rank-monitor` (DataForSEO SEO metrics) — the **only** two agents with any network access.

**Decision council (6).** Pure reasoners (no network, no `Agent` tool): `council-optimist`, `council-pessimist`, `council-out-of-the-box` (opus), `council-skeptic`, `council-pragmatist`, `council-chair` (opus). Run them with **`/council <question>`** (the skill has the main session fan out the seats and synthesize via the chair). Pattern adapted from Karpathy's `llm-council` + persona councils.

## Security posture

- `settings.json` denies reading secrets/credentials across ecosystems, build/vendor output, network-egress + destructive Bash, **and the built-in `WebFetch`/`WebSearch`** (so the only network path is the scoped MCP connector).
- `defaultMode: "plan"` + `disableBypassPermissionsMode: "disable"`; `--dangerously-skip-permissions` is off by design.
- **Scoped network connector (deliberate, documented deviation):** only `content-researcher` and `seo-rank-monitor` get network, via inline MCP servers in their own frontmatter (never inherited). Both are **read-only on files** — no agent has both write and network. The secret deny-list, untrusted-fetched-content rule, and per-agent scoping keep the exfiltration surface minimal. Full model + setup in [`council-and-network-config.md`](council-and-network-config.md).
- **Optional hooks** (`guard` hardens posture; `format`/`verify` are convenience, allowlist-gated) and an **optional managed policy** for unbreakable enforcement. See [`setup.md`](setup.md).

## Install

See **[`setup.md`](setup.md)** (Windows + Ubuntu) for the agents, settings, hooks, council skill, and the managed policy; and **[`council-and-network-config.md`](council-and-network-config.md)** for the council and the network connector.

## Acknowledgements

The engineering team structure follows patterns popularized by the open-source Claude Code community (the "AI Team" / `awesome-claude-agents`, wshobson/agents, VoltAgent collections). The council adapts Karpathy's `llm-council` and persona-council projects. **All agent prompts here are independently written** for a least-privilege, security-reviewed threat model; no third-party agent text is reproduced verbatim.

## License

[MIT](LICENSE).
