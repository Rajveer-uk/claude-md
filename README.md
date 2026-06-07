# Claude Code Configuration — polyglot, security-vetted

A lean, layered, **stack- and OS-agnostic** configuration for [Claude Code](https://claude.com/claude-code): a small global agent team plus per-project memory that adapts to whatever language, framework, package manager, and build tool a project actually uses. The agents install once and are reused across every project; each project gets its own `CLAUDE.md`.

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
    │   ├── guard.ps1             # optional PreToolUse hook (Windows / PowerShell)
    │   └── guard.sh              # optional PreToolUse hook (Linux / macOS, bash + jq)
    └── agents/                   # 16 universal, stack-agnostic specialists
```

## Design principles

- **Stack-agnostic.** One team handles any ecosystem (Node, Python, PHP, Go, Rust, Java/Kotlin, .NET, Ruby, mobile, …). `project-analyst` detects the real stack; `team-configurator` routes to a framework-specific agent when one exists, a universal specialist otherwise, and **generates a `<framework>-expert` on the fly** when a stack warrants it.
- **OS-agnostic.** The files are identical on Windows, macOS, and Linux — only install paths and the hook script differ.
- **Layered & lean.** A small root `CLAUDE.md` (description, package map, conventions) points to per-package `CLAUDE.md` files that load **on demand** when you touch that directory. Pointers, not prose.
- **Least privilege.** Every agent declares an explicit, minimal `tools` list and a model tier matched to its job. No agent has network tools; read-only roles can't write or run commands.
- **Self-improving.** When you correct an agent, it updates the relevant `CLAUDE.md` so the mistake doesn't recur.

## The agent team

| Tier | Agents |
|------|--------|
| **Planning / review (`opus`)** | `tech-lead-orchestrator` · `api-architect` · `security-auditor` · `code-reviewer` |
| **Execution / analysis (`sonnet`)** | `project-analyst` · `team-configurator` · `backend-developer` · `frontend-developer` · `database-expert` · `ui-ux-designer` · `test-engineer` · `performance-optimizer` · `dependency-manager` · `deployment-engineer` · `code-archaeologist` |
| **Docs (`haiku`)** | `documentation-specialist` |

`tech-lead-orchestrator` plans and routes but never writes code; `code-reviewer` runs last. The orchestrator, analyst, reviewer, auditor, and archaeologist are strictly read-only (`Read, Grep, Glob`).

## Security posture

- `settings.json` denies reading secrets and credentials across ecosystems (`.env*`, SSH/cloud/DB keys, `*.tfstate`/`*.tfvars`, etc.) and build/vendor output, plus a Bash deny layer for network-egress and destructive commands.
- `defaultMode: "plan"` and `disableBypassPermissionsMode: "disable"` — sessions start gated; `--dangerously-skip-permissions` is off by design.
- No agent holds `WebFetch`/`WebSearch`; the only egress channel is `Bash`, which is gated by plan-mode + per-command approval and, optionally, the `guard` hook.
- The **optional hook** (`guard.ps1` / `guard.sh`) mechanically blocks shell reads of secret paths and refuses to mint an over-privileged generated agent.
- The **optional managed policy** (`managed/managed-settings.json`) makes bypass-disable + core secret denies **unbreakable** — it sits at the highest settings tier and can't be overridden by user, project, or CLI.
- The `Read` deny-list does **not** cover shell reads — that's why the hook and plan-mode gate exist. See the residual-risk notes in [`setup.md`](setup.md).

## Install

See **[`setup.md`](setup.md)** for step-by-step instructions on Windows and Ubuntu, including the optional enforcement hook, the optional managed policy, and per-project setup.

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

The team structure here — an orchestrator that routes to specialists, a `project-analyst` for stack detection, a `team-configurator` that writes an "AI Team Configuration" table, and a roster of universal specialists — follows a pattern popularized by the open-source Claude Code community (e.g. the "AI Team" / `awesome-claude-agents` collections). **All agent prompts in this repository are independently written** for a specific least-privilege, security-reviewed threat model; no third-party agent text is reproduced verbatim.

## License

[MIT](LICENSE).
