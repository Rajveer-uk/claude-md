#!/usr/bin/env bash
# verify.sh - OPTIONAL Stop hook (Linux/macOS). When the agent tries to finish, run the
# project's own checks (guards/lint/test) and BLOCK finishing (exit 2) while they fail.
#
# SAFE BY DEFAULT - it runs a project's .claude/checks.sh ONLY when ALL of:
#   (a) that file exists AND is executable, AND
#   (b) the project's path is listed in ~/.claude/verify-allowed.txt
#       (one absolute path per line; '#' comments allowed). List specific project
#       roots, NOT a broad parent dir — subdirectories of a listed path are trusted too.
# The allowlist lives OUTSIDE any repo, so a cloned/untrusted repo that ships its own
# checks.sh can NOT auto-run code. No-op otherwise; always fails open. Uses jq when present.
#
# Bounded retries: while the checks fail it blocks up to CLAUDE_VERIFY_MAX_BLOCKS times in a
# row (default 3; 0 = never block, only warn). The count is kept per session_id in a private
# per-user temp dir and restarts with each new turn. Once the limit is reached it stops
# blocking and shows the owner a "checks still RED" message (JSON systemMessage) instead;
# a pass clears the count. Claude Code itself also ends the turn after 8 consecutive Stop-hook
# blocks (CLAUDE_CODE_STOP_HOOK_BLOCK_CAP), so values of 8 or more add nothing.
# What Claude sees on a block is kept short: the ERROR lines plus the last 20 other lines.
# The guard runner keeps the full output in .claude/guards.log. A custom checks.sh (no
# .claude/guards.log) has no log to point at, so its output itself is shown: all of it up to
# 200 lines, beyond that the ERROR lines plus the first 100 and last 100 lines.
#
# It never blocks when a block cannot help:
#   * plan mode (hook input permission_mode "plan"): Claude cannot edit files, so it exits 0
#     without running the checks;
#   * unchanged tree: each red run stores a hash of the git working-tree state (git status +
#     diff vs HEAD + untracked file contents) for the session. If the checks (still run) are
#     red again and no file changed since the last red run (e.g. a question-only turn), it does
#     not block but shows the owner the same kind of "checks still RED" message instead.
#     Outside git (or without git) there is no hash, so it blocks as before.
#
# Enable a TRUSTED project once:
#   echo "/path/to/project" >> ~/.claude/verify-allowed.txt
# then create an executable .claude/checks.sh (template: templates/checks.sh), e.g.:
#   #!/usr/bin/env bash
#   exec bash .claude/guards.sh          # or: ./vendor/bin/pint --test && ./vendor/bin/phpstan analyse
set -u

input="$(cat 2>/dev/null || true)"
cwd=""; sid=""; active="false"; mode=""
if command -v jq >/dev/null 2>&1 && [ -n "$input" ]; then
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
  active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || true)"
  mode="$(printf '%s' "$input" | jq -r '.permission_mode // empty' 2>/dev/null || true)"
elif [ -n "$input" ]; then   # no jq: best-effort scrape of the simple fields
  sid="$(printf '%s' "$input" | tr -d '\n' | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && active="true"
  printf '%s' "$input" | grep -Eq '"permission_mode"[[:space:]]*:[[:space:]]*"plan"' && mode="plan"
fi
[ "$mode" = "plan" ] && exit 0   # plan mode: Claude cannot edit files, so a block cannot help
[ -z "$cwd" ] && cwd="$(pwd)"

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

# ---- block counter (private dir; no counter file = old one-block-per-turn behaviour)
max="${CLAUDE_VERIFY_MAX_BLOCKS:-3}"
case "$max" in ''|*[!0-9]*) max=3 ;; esac
[ "${#max}" -gt 4 ] && max=9999
max=$((10#$max))
key="$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9_-' | cut -c1-100)"
[ -z "$key" ] && key="no-session"
state=""; tstate=""
sdir="${TMPDIR:-/tmp}"; sdir="${sdir%/}/claude-verify-$(id -u 2>/dev/null || echo 0)"
if mkdir -p -m 700 "$sdir" 2>/dev/null && [ -d "$sdir" ] && [ ! -L "$sdir" ] && [ -O "$sdir" ]; then
  state="$sdir/$key.count"
  tstate="$sdir/$key.tree"                 # tree hash after the last red run of this session
fi
count=0
if [ "$active" = "true" ]; then            # a continuation we (or another Stop hook) caused
  if [ -n "$state" ] && [ -f "$state" ]; then
    IFS= read -r count < "$state" 2>/dev/null || true
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    [ "${#count}" -gt 4 ] && count=9999
    count=$((10#$count))
  elif [ -z "$state" ]; then
    count="$max"                           # can't count safely: allow this stop
  fi
fi                                         # not active = first stop of a new turn: count 0

tree_state() { # hash of the git working-tree state (status + diff vs HEAD + untracked contents); empty outside git
  command -v git >/dev/null 2>&1 || return 0
  local st
  st="$(GIT_OPTIONAL_LOCKS=0 git status --porcelain --untracked-files=all 2>/dev/null)" || return 0
  {
    printf '%s\n' "$st"
    GIT_OPTIONAL_LOCKS=0 git diff --no-ext-diff --no-textconv --binary HEAD 2>/dev/null || {
      GIT_OPTIONAL_LOCKS=0 git diff --no-ext-diff --no-textconv --binary --cached 2>/dev/null
      GIT_OPTIONAL_LOCKS=0 git diff --no-ext-diff --no-textconv --binary 2>/dev/null; }   # no commit yet
    GIT_OPTIONAL_LOCKS=0 git ls-files -z -o --exclude-standard 2>/dev/null | xargs -0 git hash-object -- 2>/dev/null
  } | git hash-object --stdin 2>/dev/null
}

# ---- run the project's checks (same trust model: only the allowlisted local wrapper)
cd "$cwd" 2>/dev/null || exit 0
pre=""; last=""
if [ -n "$tstate" ]; then
  pre="$(tree_state)"
  [ -f "$tstate" ] && { IFS= read -r last < "$tstate" 2>/dev/null || true; }
fi
out="$("$checks" 2>&1)"; code=$?
if [ "$code" -eq 0 ]; then
  [ -n "$state" ] && rm -f "$state" 2>/dev/null
  [ -n "$tstate" ] && rm -f "$tstate" 2>/dev/null
  exit 0
fi
unchanged=0
[ -n "$pre" ] && [ "$pre" = "$last" ] && unchanged=1
if [ -n "$pre" ]; then                     # remember the tree as the checks left it (they may write files)
  post="$(tree_state)"
  [ -n "$post" ] && printf '%s\n' "$post" > "$tstate" 2>/dev/null
fi

errs="$(printf '%s\n' "$out" | grep -E '^[[:space:]]*ERROR' | head -n 40 | cut -c1-300)"
rest="$(printf '%s\n' "$out" | grep -Ev '^[[:space:]]*ERROR' | tail -n 20 | cut -c1-300)"
log="re-run .claude/checks.sh for the full output"
haslog=0
[ -f "$cwd/.claude/guards.log" ] && { log="full log in .claude/guards.log"; haslog=1; }
first=""
[ -n "$errs" ] && first="$(printf '%s\n' "$errs" | head -n 3 | sed 's/$/; /' | tr -d '\n')"
say() { # show the owner a non-blocking message (systemMessage is shown to the user)
  local m
  m="$(printf '%s' "$1" | tr '\t\r' '  ' | tr -d '\000-\037"\\')"
  printf '{"systemMessage":"%s"}\n' "$m"
}

# Nothing changed since the last red run (e.g. a question-only turn): a block cannot help.
if [ "$unchanged" -eq 1 ]; then
  [ -n "$state" ] && rm -f "$state" 2>/dev/null
  say "verify: project checks are still RED (exit $code) and no file has changed since the last red run in this session, so this stop is not blocked - this work is NOT verified. ${first:+Errors: $first}Details: $log."
  exit 0
fi

if [ "$count" -lt "$max" ]; then
  count=$((count + 1))
  [ -n "$state" ] && printf '%s\n' "$count" > "$state" 2>/dev/null
  {
    printf 'verify: project checks (.claude/checks.sh) failed with exit %s (block %s of %s). Fix the cause - not the test or guard - then finish; %s.\n' "$code" "$count" "$max" "$log"
    if [ "$haslog" -eq 1 ]; then
      [ -n "$errs" ] && printf '%s\n' "$errs"
      [ -n "$rest" ] && printf -- '--- last lines ---\n%s\n' "$rest"
    else                                   # custom checks.sh: show its output, capped at 200 lines
      n=$(( $(printf '%s\n' "$out" | wc -l) + 0 ))
      if [ "$n" -le 200 ]; then
        printf -- '--- output ---\n'
        printf '%s\n' "$out" | cut -c1-300
      else
        [ -n "$errs" ] && printf '%s\n' "$errs"
        printf -- '--- output: first 100 of %s lines ---\n' "$n"
        printf '%s\n' "$out" | head -n 100 | cut -c1-300
        printf -- '--- ... %s lines omitted ... last 100 lines ---\n' "$((n - 200))"
        printf '%s\n' "$out" | tail -n 100 | cut -c1-300
      fi
    fi
  } >&2
  exit 2
fi

# Limit reached: stop blocking, but tell the owner plainly (systemMessage is shown to the user).
[ -n "$state" ] && rm -f "$state" 2>/dev/null
say "verify: project checks are still RED (exit $code) after $max blocked stop(s) - this work is NOT verified. ${first:+Errors: $first}Details: $log. CLAUDE_VERIFY_MAX_BLOCKS sets how many fix attempts are forced."
exit 0
