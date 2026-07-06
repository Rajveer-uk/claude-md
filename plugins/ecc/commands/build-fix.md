---
description: Detect the project build system and incrementally fix build/type errors with minimal safe changes.
allowed-tools: Read, Edit, Grep, Glob, Bash, Task
---

# Build and Fix

Fix build and type errors incrementally with minimal, safe changes.

## Step 1: Detect Build System

Identify the build tool and run the build:

| Indicator | Build Command |
|-----------|---------------|
| `package.json` with `build` script | `npm run build` or `pnpm build` |
| `tsconfig.json` (TypeScript only) | `npx tsc --noEmit` |
| `Cargo.toml` | `cargo build 2>&1` |
| `pom.xml` | `mvn compile` |
| `build.gradle` | `./gradlew compileJava` |
| `go.mod` | `go build ./...` |
| `pyproject.toml` | `python -m compileall -q .` or `mypy .` |

## Step 2: Parse and Group Errors

1. Run the build; capture stderr
2. Group errors by file path
3. Sort by dependency order (imports/types before logic errors)
4. Count total errors for progress tracking

## Step 3: Fix Loop (One Error at a Time)

For each error:

1. **Read** — error context (10 lines around the error)
2. **Diagnose** — root cause (missing import, wrong type, syntax error)
3. **Fix minimally** — smallest Edit that resolves the error
4. **Re-run build** — error gone, no new errors introduced
5. **Move to next** error

## Step 4: Guardrails

Stop and ask the user if:
- A fix introduces **more errors than it resolves**
- The **same error persists after 3 attempts** (likely deeper issue)
- The fix requires **architectural changes** (not just a build fix)
- Errors stem from **missing dependencies** (need `npm install`, `cargo add`, etc.)

## Step 5: Summary

Report:
- Errors fixed (with file paths)
- Errors remaining (if any)
- New errors introduced (should be zero)
- Suggested next steps for unresolved issues

## Recovery Strategies

| Situation | Action |
|-----------|--------|
| Missing module/import | Check if package is installed; suggest install command |
| Type mismatch | Read both type definitions; fix the narrower type |
| Circular dependency | Identify cycle with import graph; suggest extraction |
| Version conflict | Check `package.json` / `Cargo.toml` for version constraints |
| Build tool misconfiguration | Read config file; compare with working defaults |

One error at a time; minimal diffs over refactoring.
