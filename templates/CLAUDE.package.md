<!--
TEMPLATE (claude-md/templates/CLAUDE.package.md) — copy to <area>/CLAUDE.md and fill every <placeholder>. Block HTML comments like this one are stripped before loading (zero tokens).
⚠️ Committed with the repo — keep it public-safe: no secrets, internal hosts/IPs, or client names.
Use the same Ledger tag as this area's row in the root CLAUDE.md package map.
-->
# Area: <name> (e.g. web app / API / worker / infra)

**Ledger tag:** `code/<area>` — grep REGRESSIONS.md for it before editing here.

**Language:** `<language + version>`
**Package manager / toolchain:** `<e.g. npm / pnpm / pip+uv / Poetry / Composer / cargo / go / Maven / Gradle / dotnet>`

## Commands

| Task | Command |
|------|---------|
| Install | `<install>` |
| Test | `<test>` |
| Lint / format | `<lint / format>` |
| Build | `<build>` |
| Run (dev) | `<run>` |

> Run **test** and **lint** before every commit that touches this area.

## Conventions

- `<Local style rules, directory layout, naming, framework idioms specific to this area.>`

## Gotchas

Once a gotcha has a guard, move it to the root `REGRESSIONS.md` as a row with this area's Ledger tag.

- `<Non-obvious traps specific to this area. Delete stale entries.>`

<!--
---
_Loads when Claude reads a file in this directory (or at launch if the session starts here) — not when files here are written, created or edited. Dropped at /compact and reloaded on the next read, so rules that must survive compaction belong in the root CLAUDE.md. Keep it short — stack commands and local rules only. The same shape works for any language (Node, Python, PHP, Go, Rust, Java/Kotlin, .NET, Ruby, …)._
-->
