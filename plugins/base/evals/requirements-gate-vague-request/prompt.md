---
description: "Completeness gate: a vague multi-part change request triggers requirements-gate; the reply lists AC1… including an implied test, and asks about the forks or records its assumptions."
expected_outcome: "Skill requirements-gate fires; reply has an AC1… list with at least one implied AC tied to a test, plus numbered questions or an Assumptions list."
tags: [skill-trigger, requirements-gate, smoke]
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

Add CSV export to the reports page. The repo isn't in this workspace, so here are the relevant files.

`app/reports.py`
```python
from flask import Blueprint, render_template, request
from flask_login import current_user, login_required

from .models import Report

bp = Blueprint("reports", __name__)


@bp.route("/reports")
@login_required
def reports_page():
    status = request.args.get("status", "all")
    rows = Report.for_account(current_user.account_id, status=status)
    return render_template("reports.html", rows=rows, status=status)
```

`app/templates/reports.html`
```html
<h1>Reports</h1>
<form method="get">
  <select name="status">
    <option value="all">All</option>
    <option value="paid">Paid</option>
    <option value="overdue">Overdue</option>
  </select>
  <button>Filter</button>
</form>
<table>
  <tr><th>Client</th><th>Issued</th><th>Amount</th><th>Status</th></tr>
  {% for r in rows %}
  <tr><td>{{ r.client_name }}</td><td>{{ r.issued_on }}</td><td>{{ r.amount }}</td><td>{{ r.status }}</td></tr>
  {% endfor %}
</table>
```

`tests/test_reports.py`
```python
def test_reports_page_filters_by_status(client, login, make_report):
    login()
    make_report(client_name="Alpha", status="paid")
    make_report(client_name="Beta", status="overdue")
    resp = client.get("/reports?status=paid")
    assert resp.status_code == 200
    assert b"Alpha" in resp.data and b"Beta" not in resp.data
```
