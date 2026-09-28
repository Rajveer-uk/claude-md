# Implied work — what a request rarely says but usually means

Walk the section for the domain. An item becomes an `implied: <why>` AC only when the request can't honestly be called done without it; a nice-to-have goes under Out of scope or a one-line suggestion.

## Code
- Tests for each new behaviour; a bug fix gets a regression test that fails before the fix.
- Other call sites and consumers of a changed function, endpoint, event or schema (grep the name).
- Types, interfaces, API schemas, generated clients that mirror the change.
- Docs: README, CHANGELOG, docstrings, help text, usage examples.
- Config and env: new settings, `.env.example`, CI variables; secrets read from the environment.
- Data: migration plus its rollback; seeds and fixtures; backfill for existing rows.
- Paired files: `.sh` + `.ps1`, sync + async twins, server + client validation, web + mobile.
- Unhappy paths: error, empty, not found, permission denied, timeout, very large input.
- Access: the same auth/permission check as the neighbouring feature.
- Logging for the new path, with no secrets or personal data in it.
- Feature flag or config switch when the change is risky or staged.
- i18n: new user-facing strings go through the translation layer.
- The `REGRESSIONS.md` rows for the touched area tags: their guards stay green.

## Marketing and content
- Brand voice (`brand/voice.md`) and banned phrases (`brand/banned-phrases.txt`, `check: content-lint`).
- One clear CTA; every link resolves; tracking parameters where the channel uses them.
- Metadata and SEO: title, meta description, slug, social preview image.
- Alt text on every image; captions on video.
- Channel variants: one cut per named channel (length, format, tags).
- Numbers and regulated claims have a source and the required wording.

## Ops
- Rollback: the exact steps, tried or at least written down.
- Monitoring or an alert for the changed system; health checks still pass.
- Runbook or ops note updated.
- Secrets from the environment or a secret store; no hosts or IPs in the repo.
- Backup before a destructive step; notice or window if there's downtime.
- Every environment and runner the change applies to (staging + production, `guards.sh` + `guards.ps1`).

## Docs
- Every place the same fact appears (README, workflow guide, templates, inline help) says the same thing.
- Examples still run; links and anchors resolve.
- Inventory lists and version notes (skill, agent or command tables) updated.
- Placeholders instead of real names, hosts or client data.
