---
description: "Fix-once guard: a plain bug-fix request triggers the regression-guard skill, and the fix comes with a regression test and a ledger row."
expected_outcome: "Skill regression-guard fires; reply has the corrected offset, a test that pins the bug, and an R-00x row or a REGRESSIONS.md mention."
tags: [skill-trigger, regression-guard, smoke]
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

Bug report: `paginate(list(range(10)), page=1, per_page=5)` returns `[5, 6, 7, 8, 9]`, but page 1 should be `[0, 1, 2, 3, 4]`. Pages are 1-based. The file isn't in this workspace, so here is the whole function — fix it and show me the corrected code.

```python
def paginate(items, page, per_page):
    """Return the 1-based page `page` of `items`."""
    start = page * per_page
    return items[start:start + per_page]
```
