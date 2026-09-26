---
description: "'review this email before I send it' triggers work-quality-checker and ends in its Ship it / Fix these 2 things first verdict."
expected_outcome: "Skill work-quality-checker fires; reply has a VERDICT line with one of the two verdicts."
tags: [skill-trigger, work-quality-checker, smoke]
max_turns: 5
allowed_tools: [Read, Glob, Grep, Skill]
---

Review this email before I send it to our CFO:

Subject: Q3 cloud spend

Hi Priya,

Quick update — our cloud bill went up a lot this quarter, mainly because of the new analytics cluster. I think we can probably save around 30% if we move some workloads to reserved instances, but I haven't checked the numbers in detail yet. Could we get approval to sign a 3-year commitment by Friday? Happy to discuss.

Thanks,
Sam
