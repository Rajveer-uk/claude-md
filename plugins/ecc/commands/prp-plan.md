---
description: Create comprehensive feature implementation plan with codebase analysis and pattern extraction
argument-hint: <feature description | path/to/prd.md>
allowed-tools: Read, Edit, Grep, Glob, Bash, Task
---

> Adapted from PRPs-agentic-eng by Wirasm. Part of the PRP workflow series.

# PRP Plan

Create a self-contained implementation plan capturing every codebase pattern, convention, and gotcha needed to implement a feature in a single pass — captured once, referenced throughout, no further questions needed.

**Golden Rule**: If you would need to search the codebase during implementation, capture that knowledge NOW in the plan.

---

## Phase 0 — DETECT

Determine input type from `$ARGUMENTS`:

| Input Pattern | Detection | Action |
|---|---|---|
| Path ending in `.prd.md` | File path to PRD | Parse PRD, find next pending phase |
| Path to `.md` with "Implementation Phases" | PRD-like document | Parse phases, find next pending |
| Path to any other file | Reference file | Read file for context, treat as free-form |
| Free-form text | Feature description | Proceed directly to Phase 1 |
| Empty / blank | No input | Ask user what feature to plan |

### PRD Parsing (when input is a PRD)

1. Read the PRD file with `cat "$PRD_PATH"`
2. Parse the **Implementation Phases** section
3. Select the **next eligible pending phase** — `pending` status, with any prior-phase dependencies `complete`
4. Extract the phase name, description, acceptance criteria, dependencies, and any scope notes/constraints
5. Use the phase description as the feature to plan

If no pending phases remain, report that all phases are complete.

---

## Phase 1 — PARSE

### Feature Understanding

From the input (PRD phase or free-form), identify:

- **What** is being built (concrete deliverable)
- **Why** it matters (user value)
- **Who** uses it (target user/system)
- **Where** it fits (which part of the codebase)

### User Story

Format as:
```
As a [type of user],
I want [capability],
So that [benefit].
```

### Complexity Assessment

| Level | Indicators | Typical Scope |
|---|---|---|
| **Small** | Single file, isolated change, no new dependencies | 1-3 files, <100 lines |
| **Medium** | Multiple files, follows existing patterns, minor new concepts | 3-10 files, 100-500 lines |
| **Large** | Cross-cutting concerns, new patterns, external integrations | 10+ files, 500+ lines |
| **XL** | Architectural changes, new subsystems, migration needed | 20+ files, consider splitting |

### Ambiguity Gate

If any of these are unclear, **STOP and ask the user** before proceeding:

- The core deliverable is vague
- Success criteria are undefined
- There are multiple valid interpretations
- Technical approach has major unknowns

Do NOT guess. Ask. A plan built on assumptions fails during implementation.

---

## Phase 2 — EXPLORE

Gather deep codebase intelligence.

### Codebase Search (8 Categories)

Search each category using grep, find, and file reading:

1. **Similar Implementations** — existing features resembling the planned one: analogous patterns, endpoints, components, modules.

2. **Naming Conventions** — how files, functions, variables, classes, and exports are named in the relevant area.

3. **Error Handling** — how errors are caught, propagated, logged, and returned to users in similar code paths.

4. **Logging Patterns** — what gets logged, at what level, in what format.

5. **Type Definitions** — relevant types, interfaces, schemas, and their organization.

6. **Test Patterns** — how similar features are tested: test file locations, naming, setup/teardown patterns, assertion styles.

7. **Configuration** — relevant config files, environment variables, feature flags.

8. **Dependencies** — packages, imports, and internal modules used by similar features.

### Codebase Analysis (5 Traces)

Read relevant files to trace:

1. **Entry Points** — how a request/action enters the system and reaches the area you're modifying
2. **Data Flow** — how data moves through the relevant code paths
3. **State Changes** — what state is modified and where
4. **Contracts** — interfaces, APIs, or protocols that must be honored
5. **Patterns** — architectural patterns in use (repository, service, controller, etc.)

### Unified Discovery Table

Compile findings into a single reference:

| Category | File:Lines | Pattern | Key Snippet |
|---|---|---|---|
| Naming | `src/services/userService.ts:1-5` | camelCase services, PascalCase types | `export class UserService` |
| Error | `src/middleware/errorHandler.ts:10-25` | Custom AppError class | `throw new AppError(...)` |
| ... | ... | ... | ... |

---

## Phase 3 — RESEARCH

For external libraries, APIs, or unfamiliar technology:

1. Search the web for official documentation
2. Find usage examples and best practices
3. Identify version-specific gotchas

Format each finding as:

```
KEY_INSIGHT: [what you learned]
APPLIES_TO: [which part of the plan this affects]
GOTCHA: [any warnings or version-specific issues]
```

If the feature uses only well-understood internal patterns, skip this phase and note: "No external research needed — feature uses established internal patterns."

---

## Phase 4 — DESIGN

### UX Transformation (if applicable)

Document the before/after UX:

**Before:**
```
┌─────────────────────────────┐
│  [Current user experience]  │
│  Show the current flow,     │
│  what the user sees/does    │
└─────────────────────────────┘
```

**After:**
```
┌─────────────────────────────┐
│  [New user experience]      │
│  Show the improved flow,    │
│  what changes for the user  │
└─────────────────────────────┘
```

### Interaction Changes

| Touchpoint | Before | After | Notes |
|---|---|---|---|
| ... | ... | ... | ... |

If the feature is purely backend/internal with no UX change, note: "Internal change — no user-facing UX transformation."

---

## Phase 5 — ARCHITECT

### Strategic Design

Define:

- **Approach**: high-level strategy (e.g., "Add new service layer following existing repository pattern")
- **Alternatives Considered**: other approaches evaluated and why rejected
- **Scope**: concrete boundaries of what WILL be built
- **NOT Building**: explicit OUT OF SCOPE list (prevents scope creep during implementation)

---

## Phase 6 — GENERATE

Write the full plan using the template below to `.claude/PRPs/plans/{kebab-case-feature-name}.plan.md`.

Create the directory if needed:
```bash
mkdir -p .claude/PRPs/plans
```

### Plan Template

````markdown
# Plan: [Feature Name]

## Summary
[2-3 sentence overview]

## User Story
As a [user], I want [capability], so that [benefit].

## Problem → Solution
[Current state] → [Desired state]

## Metadata
- **Complexity**: [Small | Medium | Large | XL]
- **Source PRD**: [path or "N/A"]
- **PRD Phase**: [phase name or "N/A"]
- **Estimated Files**: [count]

---

## UX Design

### Before
[ASCII diagram or "N/A — internal change"]

### After
[ASCII diagram or "N/A — internal change"]

### Interaction Changes
| Touchpoint | Before | After | Notes |
|---|---|---|---|

---

## Mandatory Reading

Files that MUST be read before implementing:

| Priority | File | Lines | Why |
|---|---|---|---|
| P0 (critical) | `path/to/file` | 1-50 | Core pattern to follow |
| P1 (important) | `path/to/file` | 10-30 | Related types |
| P2 (reference) | `path/to/file` | all | Similar implementation |

## External Documentation

| Topic | Source | Key Takeaway |
|---|---|---|
| ... | ... | ... |

---

## Patterns to Mirror

Code patterns discovered in the codebase. Follow these exactly.

### NAMING_CONVENTION
// SOURCE: [file:lines]
[actual code snippet showing the naming pattern]

### ERROR_HANDLING
// SOURCE: [file:lines]
[actual code snippet showing error handling]

### LOGGING_PATTERN
// SOURCE: [file:lines]
[actual code snippet showing logging]

### REPOSITORY_PATTERN
// SOURCE: [file:lines]
[actual code snippet showing data access]

### SERVICE_PATTERN
// SOURCE: [file:lines]
[actual code snippet showing service layer]

### TEST_STRUCTURE
// SOURCE: [file:lines]
[actual code snippet showing test setup]

---

## Files to Change

| File | Action | Justification |
|---|---|---|
| `path/to/file.ts` | CREATE | New service for feature |
| `path/to/existing.ts` | UPDATE | Add new method |

## NOT Building

- [Explicit item 1 that is out of scope]
- [Explicit item 2 that is out of scope]

---

## Step-by-Step Tasks

### Task 1: [Name]
- **ACTION**: [What to do]
- **IMPLEMENT**: [Specific code/logic to write]
- **MIRROR**: [Pattern from Patterns to Mirror section to follow]
- **IMPORTS**: [Required imports]
- **GOTCHA**: [Known pitfall to avoid]
- **VALIDATE**: [How to verify this task is correct]

### Task 2: [Name]
- **ACTION**: ...
- **IMPLEMENT**: ...
- **MIRROR**: ...
- **IMPORTS**: ...
- **GOTCHA**: ...
- **VALIDATE**: ...

[Continue for all tasks...]

---

## Testing Strategy

### Unit Tests

| Test | Input | Expected Output | Edge Case? |
|---|---|---|---|
| ... | ... | ... | ... |

### Edge Cases Checklist
- [ ] Empty input
- [ ] Maximum size input
- [ ] Invalid types
- [ ] Concurrent access
- [ ] Network failure (if applicable)
- [ ] Permission denied

---

## Validation Commands

### Static Analysis
```bash
# Run type checker
[project-specific type check command]
```
EXPECT: Zero type errors

### Unit Tests
```bash
# Run tests for affected area
[project-specific test command]
```
EXPECT: All tests pass

### Full Test Suite
```bash
# Run complete test suite
[project-specific full test command]
```
EXPECT: No regressions

### Database Validation (if applicable)
```bash
# Verify schema/migrations
[project-specific db command]
```
EXPECT: Schema up to date

### Browser Validation (if applicable)
```bash
# Start dev server and verify
[project-specific dev server command]
```
EXPECT: Feature works as designed

### Manual Validation
- [ ] [Step-by-step manual verification checklist]

---

## Acceptance Criteria
- [ ] All tasks completed
- [ ] All validation commands pass
- [ ] Tests written and passing
- [ ] No type errors
- [ ] No lint errors
- [ ] Matches UX design (if applicable)

## Completion Checklist
- [ ] Code follows discovered patterns
- [ ] Error handling matches codebase style
- [ ] Logging follows codebase conventions
- [ ] Tests follow test patterns
- [ ] No hardcoded values
- [ ] Documentation updated (if needed)
- [ ] No unnecessary scope additions
- [ ] Self-contained — no questions needed during implementation

## Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| ... | ... | ... | ... |

## Notes
[Any additional context, decisions, or observations]
```

---

## Output

### Save the Plan

Write to:
```
.claude/PRPs/plans/{kebab-case-feature-name}.plan.md
```

### Update PRD (if input was a PRD)

1. Update the phase status from `pending` to `in-progress`
2. Add the plan file path as a reference in the phase

### Report to User

```
## Plan Created

- **File**: .claude/PRPs/plans/{kebab-case-feature-name}.plan.md
- **Source PRD**: [path or "N/A"]
- **Phase**: [phase name or "standalone"]
- **Complexity**: [level]
- **Scope**: [N files, M tasks]
- **Key Patterns**: [top 3 discovered patterns]
- **External Research**: [topics researched or "none needed"]
- **Risks**: [top risk or "none identified"]
- **Confidence Score**: [1-10] — likelihood of single-pass implementation

> Next step: Run `/prp-implement .claude/PRPs/plans/{name}.plan.md` to execute this plan.
```

---

## Verification

Before finalizing, verify against these checklists:

### Context Completeness
- [ ] All relevant files discovered and documented
- [ ] Naming conventions captured with examples
- [ ] Error handling patterns documented
- [ ] Test patterns identified
- [ ] Dependencies listed

### Implementation Readiness
- [ ] Every task has ACTION, IMPLEMENT, MIRROR, and VALIDATE
- [ ] No task requires additional codebase searching
- [ ] Import paths are specified
- [ ] GOTCHAs documented where applicable

### Pattern Faithfulness
- [ ] Code snippets are actual codebase examples (not invented)
- [ ] SOURCE references point to real files and line numbers
- [ ] Patterns cover naming, errors, logging, data access, and tests
- [ ] New code will be indistinguishable from existing code

### Validation Coverage
- [ ] Static analysis commands specified
- [ ] Test commands specified
- [ ] Build verification included

### UX Clarity
- [ ] Before/after states documented (or marked N/A)
- [ ] Interaction changes listed
- [ ] Edge cases for UX identified

### No Prior Knowledge Test
A developer unfamiliar with this codebase should be able to implement the feature using ONLY this plan, without searching the codebase or asking questions. If not, add the missing context.

---

## Next Steps

- Run `/prp-implement <plan-path>` to execute this plan
- Run `/plan` for quick conversational planning without artifacts
- Run `/prp-prd` to create a PRD first if scope is unclear
````
