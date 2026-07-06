---
description: Fix Kotlin/Gradle build, compiler, and dependency errors incrementally via the kotlin-build-resolver agent for minimal, surgical fixes.
allowed-tools: Read, Edit, Grep, Glob, Bash, Task
---

# Kotlin Build and Fix

Invokes the **kotlin-build-resolver** agent to fix Kotlin build errors incrementally with minimal changes.

## What This Command Does

1. **Run Diagnostics**: `./gradlew build`, `detekt`, `ktlintCheck`
2. **Parse Errors**: group by file, sort by severity
3. **Fix Incrementally**: one error at a time
4. **Verify Each Fix**: re-run build after each change
5. **Report Summary**: what was fixed, what remains

## When to Use
- `./gradlew build` fails with errors
- Kotlin compiler reports errors
- `./gradlew detekt` reports violations
- Gradle dependency resolution fails
- After pulling changes that break the build

## Diagnostic Commands Run

```bash
# Primary build check
./gradlew build 2>&1

# Static analysis
./gradlew detekt 2>&1 || echo "detekt not configured"
./gradlew ktlintCheck 2>&1 || echo "ktlint not configured"

# Dependency issues
./gradlew dependencies --configuration runtimeClasspath 2>&1 | head -100

# Optional deep refresh when caches or dependency metadata are suspect
./gradlew build --refresh-dependencies
```

## Example Session

````text
User: /kotlin-build

Agent:
# Kotlin Build Resolution

## Initial Diagnostics

```bash
$ ./gradlew build
e: src/main/kotlin/com/example/service/UserService.kt:25:15 Unresolved reference: UserRepository
e: src/main/kotlin/com/example/routes/UserRoutes.kt:42:9 Type mismatch: inferred type is String but Int was expected
e: src/main/kotlin/com/example/routes/UserRoutes.kt:58:5 'when' expression must be exhaustive
```

Errors found: 3

## Fix 1: Unresolved Reference

File: src/main/kotlin/com/example/service/UserService.kt:25
Error: Unresolved reference: UserRepository
Cause: Missing import

```kotlin
// Added import
import com.example.repository.UserRepository
```

```bash
$ ./gradlew build
# 2 errors remaining
```

## Fix 2: Type Mismatch

File: src/main/kotlin/com/example/routes/UserRoutes.kt:42
Error: Type mismatch: inferred type is String but Int was expected

```kotlin
// Changed
val count = call.parameters["count"]
// To
val count = call.parameters["count"]?.toIntOrNull()
    ?: return@get call.respond(HttpStatusCode.BadRequest, "Invalid count")
```

```bash
$ ./gradlew build
# 1 error remaining
```

## Fix 3: Non-Exhaustive When

File: src/main/kotlin/com/example/routes/UserRoutes.kt:58
Error: 'when' expression must be exhaustive

```kotlin
// Added missing branch
when (user.role) {
    Role.ADMIN -> handleAdmin(user)
    Role.USER -> handleUser(user)
    Role.MODERATOR -> handleModerator(user) // Added
}
```

```bash
$ ./gradlew build
# Build successful!
```

## Final Verification

```bash
$ ./gradlew detekt
# No issues

$ ./gradlew test
# All tests passed
```

## Summary

| Metric | Count |
|--------|-------|
| Build errors fixed | 3 |
| Detekt issues fixed | 0 |
| Files modified | 2 |
| Remaining issues | 0 |

Build Status: PASS: SUCCESS
````

## Common Errors Fixed

| Error | Typical Fix |
|-------|-------------|
| `Unresolved reference: X` | Add import or dependency |
| `Type mismatch` | Fix type conversion or assignment |
| `'when' must be exhaustive` | Add missing sealed class branches |
| `Suspend function can only be called from coroutine` | Add `suspend` modifier |
| `Smart cast impossible` | Use local `val` or `let` |
| `None of the following candidates is applicable` | Fix argument types |
| `Could not resolve dependency` | Fix version or add repository |

## Fix Strategy

1. **Build errors first** - code must compile
2. **Detekt violations second** - code quality
3. **ktlint warnings third** - formatting
4. **One fix at a time** - verify each change
5. **Minimal changes** - fix, don't refactor

## Stop Conditions

Stop and report if:
- Same error persists after 3 attempts
- Fix introduces more errors
- Requires architectural changes
- Missing external dependencies

## Related Commands

- `/kotlin-test` - Run tests after build succeeds
- `/kotlin-review` - Review code quality
- `eval-harness` skill - Full verification loop

## Related

- Agent: kotlin-build-resolver
- Skill: kotlin-patterns
