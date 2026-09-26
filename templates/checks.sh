#!/usr/bin/env bash
# checks.sh - LOCAL trigger for the verify Stop hook. TEMPLATE (claude-md/templates/checks.sh).
# Copy to <project>/.claude/checks.sh, then: chmod +x .claude/checks.sh
# Keep it gitignored and never commit it.
#
# Why this is separate from the committed .claude/guards.sh:
# - The verify hook auto-runs .claude/checks.sh when Claude tries to finish, but only in projects
#   listed in ~/.claude/verify-allowed.txt (a user-authored allowlist outside every repo).
# - A cloned or untrusted repo can ship any guards.sh it likes; it still can't make your machine
#   auto-run it, because this one-line trigger is yours: create it only in projects you trust,
#   after reading their .claude/guards.sh.
# - The guards themselves stay committed in guards.sh, so CI and cloud sessions run them without it.
set -u
exec bash "$(dirname "$0")/guards.sh" "$@"
