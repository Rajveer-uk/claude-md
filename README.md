# Claude Code Configuration — polyglot, security-vetted

A lean, layered, **stack- and OS-agnostic** configuration for [Claude Code](https://claude.com/claude-code): a global agent team plus per-project memory that adapts to whatever language, framework, package manager, and build tool a project actually uses. The agents install once and are reused across every project; each project gets its own `CLAUDE.md`.

Every file in this repo was produced through a full multi-dimension security audit (prompt-injection, permissions/blast-radius, secret exposure, context leakage, network/exfiltration, supply chain, provenance, and cross-file combination risks) with each finding independently verified. See [`setup.md`](setup.md) to install.

## What's inside

```
.
├── CLAUDE.md                     # project-root template (copy one into each project)
├── setup.md                      # install guide — Windows (PowerShell) + Ubuntu (bash)
├── .gitignore                    # keeps secrets & local Claude state out of git
├── templates/
│   └── CLAUDE.package.md         # per-package / per-subsystem template (loads on demand)
├── managed/
│   └── managed-settings.json     # optional admin policy — unbreakable bypass-disable + core secret denies
└── .claude/
    ├── settings.json             # security baseline — install at USER scope (~/.claude/)
    ├── hooks/
    │   ├── guard.ps1  / guard.sh   # optional: block secret-read/egress + over-privileged agent generation
    │   ├── format.ps1 / format.sh  # optional PostToolUse: auto-format the edited file with local formatters
    │   └── verify.ps1 / verify.sh  # optional Stop: run the project's .claude/checks.* before finishing
    └── agents/                   # 22 stack-agnostic specialists (+ curated stack experts)
```

## Design principles

- **Stack-agnostic + dynamic.** Universal specialists handle any ecosystem (Node, Python, PHP, Go, Rust, Java/Kotlin, .NET, Ruby, mobile, …). `project-analyst` detects the real stack; `team-configurator` prefers a framework-specific agent, falls back to a universal one, and **generates a `<framework>-expert` on demand** for stacks without a curated specialist.
- **Curated experts for recurring stacks.** Ships first-class `laravel-expert`, `react-tailwind-expert`, `frappe-expert`, and `n8n-expert` — preferred over the generic agents for those stacks; generation covers the long tail.
- **OS-agnostic.** Files are identical on Windows, macOS, and Linux — only install paths and the hook script (`.ps1` vs `.sh`) differ.
- **Layered & lean.** A small root `CLAUDE.md` points to per-package `CLAUDE.md` files that load **on demand**. Pointers, not prose.
- **Least privilege.** Every agent declares an explicit, minimal `tools` list and a model tier matched to its job. No agent has network tools; read-only roles can't write or run commands.
- **Self-improving.** When you correct an agent, it updates the relevant `CLAUDE.md` so the mistake doesn't recur.

## The agent team (22)

| Tier | Agents |
|------|--------|
| **Planning / review (`opus`)** | `tech-lead-orchestrator` · `api-architect` · `security-auditor` · `code-reviewer` |
| **Execution / analysis (`sonnet`)** | `project-analyst` · `team-configurator` · `backend-developer` · `frontend-developer` · `database-expert` · `ui-ux-designer` · `test-engineer` · `debugger` · `devops-troubleshooter` · `performance-optimizer` · `dependency-manager` · `deployment-engineer` · `code-archaeologist` |
| **Curated stack experts (`sonnet`)** | `laravel-expert` · `react-tailwind-expert` · `frappe-expert` · `n8n-expert` |
| **Docs (`haiku`)** | `documentation-specialist` |

`tech-lead-orchestrator` plans and routes (bugs → `debugger` first) but never writes code; `code-reviewer` runs last. The orchestrator, analyst, reviewer, auditor, archaeologist, and devops-troubleshooter are read-only / read-mostly. Roster validated against the popular community collections (wshobson, VoltAgent, vijaythecoder, …) — the universal core is fully covered.

## Security posture

- `settings.json` denies reading secrets and credentials across ecosystems (`.env*`, SSH/cloud/DB keys, `*.tfstate`/`*.tfvars`, etc.) and build/vendor output, plus a Bash deny layer for network-egress and destructive commands.
- `defaultMode: "plan"` and `disableBypassPermissionsMode: "disable"` — sessions start gated; `--dangerously-skip-permissions` is off by design.
- No agent holds `WebFetch`/`WebSearch`; the only egress channel is `Bash`, gated by plan-mode + per-command approval and, optionally, the `guard` hook.
- **Optional hooks** (under `.claude/hooks/`): `guard` mechanically blocks shell secret-reads and over-privileged agent generation; `format` auto-formats edited files with project-local tools; `verify` runs the project's own checks before the agent finishes (gated by a user-authored `~/.claude/verify-allowed.txt` allowlist, so a cloned repo can't auto-run code). `format`/`verify` run project-local tooling automatically — enable them only on trusted repos (see `setup.md`).
- **Optional managed policy** (`managed/managed-settings.json`) makes bypass-disable + core secret denies **unbreakable** (highest settings tier).
- The `Read` deny-list does **not** cover shell reads — that's why the hooks and plan-mode gate exist. See the residual-risk notes in [`setup.md`](setup.md).

## Install

See **[`setup.md`](setup.md)** for step-by-step instructions on Windows and Ubuntu, including the optional hooks, the optional managed policy, and per-project setup.

Quick start, once installed:

```text
claude --permission-mode plan
> Use project-analyst to detect the stack, then team-configurator to write the
> AI Team Configuration table into CLAUDE.md.
```

## Customizing

- Per project: copy `CLAUDE.md` into the root and `templates/CLAUDE.package.md` into each subsystem, then fill in the commands.
- Personal overrides: `~/.claude/settings.local.json` (auto-gitignored) merges over the baseline.
- Skip packages you never work in with `claudeMdExcludes`.

## Acknowledgements

The team structure here — an orchestrator that routes to specialists, a `project-analyst` for stack detection, a `team-configurator` that writes an "AI Team Configuration" table, and a roster of universal specialists — follows a pattern popularized by the open-source Claude Code community (e.g. the "AI Team" / `awesome-claude-agents`, wshobson/agents, and VoltAgent collections). **All agent prompts in this repository are independently written** for a specific least-privilege, security-reviewed threat model; no third-party agent text is reproduced verbatim.

## License

[MIT](LICENSE).
