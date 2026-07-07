# ecc pack

A **curated, security-audited subset of [ECC](https://github.com/affaan-m/ECC)** (MIT), vendored as a
fourth, namespaced pack in this marketplace. It adds breadth — per-language reviewers, build-error
resolvers, and a large library of engineering skills — **without touching** the `base` pack or this
repo's least-privilege, no-network security posture.

- **41 agents · 116 skills · 34 commands** (191 of 435 upstream items vendored)
- Includes **10 ECC agent-engineering knowledge skills** (agent architecture, autonomous loops, eval-driven dev), each carrying a provenance note. The broader ECC harness/command machinery (gan/orch/hookify/instinct/multi/epic/sessions) was **trimmed for token economy** — it was inert here without ECC's runtime
- Namespaced separately, so nothing collides with `base` / `marketing` / `council`
- **Pure markdown** — no bundled scripts, no hooks, no installers, no cross-harness config
- Network stays governed by the repo's `settings.json` baseline
- Full provenance, license, and the exact audit edits are in [`ATTRIBUTION.md`](./ATTRIBUTION.md)

## Install

```
/plugin marketplace add .            # or <owner>/claude-md when public
/plugin install ecc@claude-md-packs
```

Install the security baseline (`settings.json`) separately — see the repo's `setup.md`.

## What's inside

**Agents** (`agents/`) — mostly things `base` doesn't cover:
- **Language reviewers:** Go, Rust, Java, Kotlin, Swift, C#, C++, Dart/Flutter, Python, TypeScript, React, Vue, Django, FastAPI, F#, PHP, MLE
- **Build-error resolvers:** C++, Dart, Django, Go, Java, Kotlin, React, Rust, Swift, TypeScript/Node — plus `pytorch-runtime-debugger` for training/inference crashes
- **Cross-cutting:** `code-architect`, `code-simplifier`, `refactor-cleaner`, `tdd-guide`,
  `silent-failure-hunter`, `type-design-analyzer`, `comment-analyzer`, `a11y-architect`,
  `e2e-runner`, `pr-test-analyzer`, and the `opensource-forker` / `-sanitizer` / `-packager` trio

**Skills** (`skills/`) — testing/TDD, architecture (hexagonal, ADRs, design systems), per-stack
patterns (Django, Spring Boot, Quarkus, Kotlin, React/Next/Nuxt/Vue, Rust, Go, Perl, .NET, Prisma,
Redis, Docker, Kubernetes), performance/latency, accessibility, migrations, code-tour/onboarding,
and more. Invoke with `/ecc:<skill>` (or as auto-surfaced skills).

**Commands** (`commands/`) — per-language `*-build` / `*-review` / `*-test` shortcuts plus
`feature-dev`, `plan`, `plan-prd`, `pr`, `refactor-clean`, `test-coverage`, and the `prp-*` pair.

## Security notes

- `settings.json` denies `WebFetch`/`WebSearch` and network Bash session-wide — web-assuming skills
  are blocked by default.
- `github-ops` uses the authenticated `gh` CLI (needs `gh` installed + logged in).
- `inherit-legacy-style` can optionally install a **user-gated** `PreToolUse` hook — review before accepting.

Every agent declares an explicit least-privilege `tools:` array; several malformed upstream arrays
were normalized and a handful of ECC-internal references were trimmed during the audit
(see `ATTRIBUTION.md`).
