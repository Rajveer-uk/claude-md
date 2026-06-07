#!/usr/bin/env bash
# verify.sh - OPTIONAL Stop hook (Linux/macOS). When the agent tries to finish, run the
# project's own checks (lint/test) and BLOCK finishing (exit 2) if they fail.
#
# SAFE BY DEFAULT - it runs a project's .claude/checks.sh ONLY when ALL of:
#   (a) that file exists AND is executable, AND
#   (b) the project's path is listed in ~/.claude/verify-allowed.txt
#       (one absolute path per line; '#' comments allowed). List specific project
#       roots, NOT a broad parent dir — subdirectories of a listed path are trusted too.
# The allowlist lives OUTSIDE any repo, so a cloned/untrusted repo that ships its own
# checks.sh can NOT auto-run code. No-op otherwise; always fails open. Needs jq.
#
# Enable a TRUSTED project once:
#   echo "/path/to/project" >> ~/.claude/verify-allowed.txt
# then create an executable .claude/checks.sh, e.g.:
#   #!/usr/bin/env bash
#   ./vendor/bin/pint --test && ./vendor/bin/phpstan analyse

input="$(cat 2>/dev/null || true)"
if command -v jq >/dev/null 2>&1 && [ -n "$input" ]; then
  [ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
fi
[ -z "${cwd:-}" ] && cwd="$(pwd)"

checks="$cwd/.claude/checks.sh"
[ -x "$checks" ] || exit 0   # opt-in per project (must exist + be executable)

allow="$HOME/.claude/verify-allowed.txt"
[ -f "$allow" ] || exit 0
cwdN="${cwd%/}"
ok=0
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"   # left-trim
  case "$line" in ''|'#'*) continue ;; esac
  p="${line%/}"
  case "$cwdN" in "$p"|"$p"/*) ok=1; break ;; esac
done < "$allow"
[ "$ok" -eq 1 ] || exit 0

out="$("$checks" 2>&1)"; code=$?
if [ "$code" -ne 0 ]; then
  printf 'Project checks (.claude/checks.sh) failed with exit %s - fix before finishing:\n%s\n' "$code" "$out" >&2
  exit 2
fi
exit 0
