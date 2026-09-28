---
description: "Fix-once guard: an owner correction ('you broke X again') triggers the regression-guard skill and yields a ledger row, not just a patch."
expected_outcome: "Skill regression-guard fires; reply restores DD/MM/YYYY and proposes an R-00x row or names REGRESSIONS.md."
tags: [skill-trigger, regression-guard, smoke]
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

You broke the invoice date format again. After your last change `format_invoice_date()` prints `09/25/2026`, and it must be UK format, `25/09/2026` (DD/MM/YYYY). This is the second time. The file isn't in this workspace, so here is the current function — fix it and make sure it never comes back.

```python
from datetime import date

def format_invoice_date(d: date) -> str:
    return d.strftime("%m/%d/%Y")
```
