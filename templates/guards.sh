#!/usr/bin/env bash
# guards.sh - fix-once guard runner. TEMPLATE (claude-md/templates/guards.sh):
# copy to <project>/.claude/guards.sh and COMMIT it (CI, cloud sessions and teammates run it).
# Windows twin: .claude/guards.ps1 - keep the step names in sync (ledger-integrity checks both).
#
# Usage:  bash .claude/guards.sh          full set - always before calling work done
#         bash .claude/guards.sh --fast   skips steps marked slow - mid-task only
# Output: one line per step - "OK <step>", "ERROR <step>: <reason>" or "SKIP <step>: <reason>" -
#         then one summary line. Full output of every step is appended to .claude/guards.log
#         (gitignore it). Every step runs; exit 1 if any step failed, 2 on a usage error.
# Env:    GUARD_BASE_REF      git ref the ledger must stay append-only against. Default: HEAD plus,
#                             when the branch has an upstream, its fork point (merge-base with @{u}),
#                             so a committed-but-unpushed row deletion is caught too. CI sets
#                             origin/<base branch> on pull requests and the pre-push commit on pushes.
#         ALLOW_GUARD_CHANGE  1 = skip the append-only check. Owner's explicit OK only
#                             (CI: PR label guard-change-approved).
#         CONTENT_DIRS        override the content-lint folder list below
#
# Add a check: step for any invariant a test can't cover (config, ops, content rules):
#   step <name> [slow] -- <command...>   exit 0 = OK, other = ERROR. Print "ERROR: <reason>"
#                                        to set the one-line reason; exit 77 + "SKIP: <reason>" = SKIP.
# Reference it in REGRESSIONS.md as "check: <name>". Steps read files in this repo only - no
# network, no secrets, no production hosts. Needs bash, grep, sed, awk; git is optional.
set -u

# ---------------------------------------------------------------- configuration
# Full test suite (slow). Uncomment one line or write your own; runs via bash -c.
TEST_CMD=''
# TEST_CMD='npm test --silent'
# TEST_CMD='python3 -m pytest -q'
# TEST_CMD='php artisan test'
# TEST_CMD='go test ./...'

# Linter / type checker. Runs via bash -c.
LINT_CMD=''
# LINT_CMD='npm run lint --silent'
# LINT_CMD='ruff check .'
# LINT_CMD='./vendor/bin/pint --test && ./vendor/bin/phpstan analyse --no-progress'

# Folders content-lint scans for banned phrases (missing folders are ignored). A folder named
# brand/ is never scanned - it holds the rules. Keep in sync with .claude/rules/content.md paths.
# docs/ is not in the default list (engineering docs aren't brand copy) - add it if yours should be linted.
CONTENT_DIRS="${CONTENT_DIRS:-content blog posts copy marketing emails newsletters social landing-pages}"
BANNED_FILE="brand/banned-phrases.txt"
LEDGER="REGRESSIONS.md"

# ---------------------------------------------------------------- setup
here="$(cd "$(dirname "$0")" && pwd)"
SELF="$here/$(basename "$0")"
TWIN="$here/guards.ps1"
case "$here" in
  */.claude) root="${here%/.claude}" ;;
  *) root="$(git -C "$here" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$here")" ;;
esac
cd "$root" || { echo "ERROR guards: cannot cd to $root"; exit 2; }

FAST=0
for arg in "$@"; do
  case "$arg" in
    --fast) FAST=1 ;;
    -h|--help) sed -n '2,23p' "$SELF"; exit 0 ;;
    *) echo "usage: bash .claude/guards.sh [--fast]" >&2; exit 2 ;;
  esac
done

mkdir -p .claude
LOG=".claude/guards.log"
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 1048576 ]; then   # keep the log under ~1 MB
  tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
printf '\n=== guards %s%s ===\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$([ "$FAST" -eq 1 ] && echo ' --fast')" >> "$LOG"

ok=0; failed=0; skipped=0; failed_names=""
ESC="$(printf '\033')"

one_line() {  # $1 = step output, $2 = exit code -> the most useful single line
  local out line
  out="$(printf '%s\n' "$1" | sed -e "s/${ESC}\[[0-9;]*[A-Za-z]//g" -e 's/\r$//')"
  line="$(printf '%s\n' "$out" | sed -n 's/^ERROR: //p' | head -n 1)"
  # 1) runner-style failure lines (pytest/jest/go/phpunit/tap/python), 2) any fail/error line, 3) last line
  [ -n "$line" ] || line="$(printf '%s\n' "$out" | grep -E '^[[:space:]]*(FAILED|FAIL|--- FAIL|not ok)[[:space:]:]|^E[[:space:]]+[^[:space:]]|[A-Za-z]+(Error|Exception):|[Ff]ailed asserting|^[[:space:]]*[0-9]+ (failed|errors?)' | head -n 1)"
  [ -n "$line" ] || line="$(printf '%s\n' "$out" | grep -iE 'fail|error|assert|not ok|panic|exception' \
    | grep -vE '^[[:space:]=_*#-]*(FAILURES|ERRORS)?[[:space:]=_*#-]*$|^Traceback' | head -n 1)"
  [ -n "$line" ] || line="$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -n 1)"
  [ -n "$line" ] || line="exit $2"
  line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//')"
  if [ "${#line}" -gt 300 ]; then line="$(printf '%s' "$line" | cut -c1-300) ... (see log)"; fi
  printf '%s' "$line"
}

step() {  # step <name> [slow] -- <command...>
  local name="$1" slow=0 out code note
  shift
  if [ "${1:-}" = "slow" ]; then slow=1; shift; fi
  if [ "${1:-}" = "--" ]; then shift; fi
  if [ "$slow" -eq 1 ] && [ "$FAST" -eq 1 ]; then
    echo "SKIP $name: --fast"; printf -- '--- %s: skipped (--fast)\n' "$name" >> "$LOG"
    skipped=$((skipped + 1)); return 0
  fi
  out="$("$@" 2>&1)"; code=$?
  { printf -- '--- %s (exit %s)\n' "$name" "$code"; printf '%s\n' "$out"; } >> "$LOG"
  if [ "$code" -eq 0 ]; then
    note="$(printf '%s\n' "$out" | sed -n 's/^NOTE: //p' | head -n 1)"
    if [ -n "$note" ]; then echo "OK $name ($note)"; else echo "OK $name"; fi
    ok=$((ok + 1))
  elif [ "$code" -eq 77 ] && printf '%s\n' "$out" | grep -q '^SKIP: '; then
    echo "SKIP $name: $(printf '%s\n' "$out" | sed -n 's/^SKIP: //p' | head -n 1)"
    skipped=$((skipped + 1))
  else
    echo "ERROR $name: $(one_line "$out" "$code")"
    failed=$((failed + 1)); failed_names="${failed_names:+$failed_names, }$name"
  fi
}

run_configured() {  # $1 = name of the variable that holds the command
  local cmd="${!1:-}" ids
  if [ -z "$cmd" ]; then
    if [ "$1" = "TEST_CMD" ]; then   # an unset test suite must not pass the ledger's test: rows
      ids="$(guarded_ids test)"
      if [ -n "$ids" ]; then
        echo "ERROR: TEST_CMD not set but $LEDGER has test: rows $ids - set TEST_CMD near the top of .claude/guards.sh (and \$TestCmd in guards.ps1)"
        return 1
      fi
    fi
    echo "SKIP: not configured"
    echo "Reminder: set $1 near the top of .claude/guards.sh (and the matching variable in guards.ps1)."
    return 77
  fi
  bash -c "$cmd"
}

# ---------------------------------------------------------------- built-in steps
content_lint() {
  local pats dirs=() d hits n shown ids
  ids="$(guarded_ids check content-lint)"   # rows citing this step must not pass while it is unconfigured
  if [ ! -f "$BANNED_FILE" ]; then
    [ -n "$ids" ] && { echo "ERROR: no $BANNED_FILE but $LEDGER has check: content-lint rows $ids"; return 1; }
    echo "SKIP: no $BANNED_FILE"; return 77
  fi
  pats="$(mktemp)"
  sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' "$BANNED_FILE" > "$pats"
  if [ ! -s "$pats" ]; then
    rm -f "$pats"
    [ -n "$ids" ] && { echo "ERROR: no phrases in $BANNED_FILE but $LEDGER has check: content-lint rows $ids"; return 1; }
    echo "SKIP: no phrases in $BANNED_FILE yet"; return 77
  fi
  for d in $CONTENT_DIRS; do
    d="${d%/}"
    case "$d" in brand|brand/*|./brand|./brand/*) echo "ignored $d (brand/ holds the rules)"; continue ;; esac
    [ -e "$d" ] && dirs+=("$d")
  done
  if [ "${#dirs[@]}" -eq 0 ]; then rm -f "$pats"; echo "SKIP: none of CONTENT_DIRS exist ($CONTENT_DIRS)"; return 77; fi
  echo "phrases: $(wc -l < "$pats" | tr -d ' ') | scanned: ${dirs[*]}"
  hits="$(grep -rinIF -o -f "$pats" --exclude="$LEDGER" --exclude-dir=brand --exclude-dir=.git \
          --exclude-dir=.claude --exclude-dir=node_modules -- "${dirs[@]}" 2>/dev/null \
          | awk -F: '!seen[$1 ":" $2]++ { m = $3; for (i = 4; i <= NF; i++) m = m ":" $i; print $1 ":" $2 " [" m "]" }' \
          | sort -t: -k1,1 -k2,2n)"
  rm -f "$pats"
  [ -z "$hits" ] && return 0
  n="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
  shown="$(printf '%s\n' "$hits" | head -n 5 | paste -sd ';' - | sed 's/;/; /g')"
  [ "$n" -gt 5 ] && shown="$shown; +$((n - 5)) more"
  echo "ERROR: $n banned-phrase hit(s): $shown"
  printf '%s\n' "$hits"
  return 1
}

ledger_rows() {  # stdin = markdown -> normalised ledger rows (HTML comments and code fences skipped)
  sed 's/\r$//' | awk '
    incom { if (index($0, "-->")) incom = 0; next }
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    index($0, "<!--") { if (!index(substr($0, index($0, "<!--")), "-->")) incom = 1; next }
    /^[[:space:]]*\|[[:space:]]*R-[0-9]+[[:space:]]*\|/ { print }' \
  | sed -E 's/[[:space:]]+/ /g; s/ ?\| ?/|/g; s/^ //; s/ $//'
}

step_defined() {  # $1 = runner file, $2 = step name
  local n="${2//./\\.}"
  case "$1" in
    *.ps1) grep -iEq "^[[:space:]]*step[[:space:]]+(-name[[:space:]]+)?['\"]?$n['\"]?([[:space:]]|$)" "$1" ;;
    *)     grep -Eq  "^[[:space:]]*step[[:space:]]+['\"]?$n['\"]?([[:space:]]|$)" "$1" ;;
  esac
}

guarded_ids() {  # $1 = guard kind (test/check), $2 = optional check step -> "R-001,R-004" of live rows
  [ -f "$LEDGER" ] || return 0
  ledger_rows < "$LEDGER" | sed 's/\\|/%PIPE%/g' | awk -F'|' -v kind="$1" -v want="${2:-}" '
    function trim(x) { gsub(/^ +| +$/, "", x); return x }
    NF {
      rule = $4; sub(/^[ _*~`]*/, "", rule)
      if (tolower(substr(rule, 1, 8)) == "retired:") next
      g = ($NF == "" ? $(NF-2) : $(NF-1)); gsub(/`/, "", g); g = trim(g)
      i = index(g, ":"); if (!i) next
      if (tolower(trim(substr(g, 1, i - 1))) != kind) next
      if (want != "" && tolower(trim(substr(g, i + 1))) != tolower(want)) next
      ids = ids (ids == "" ? "" : ",") trim($2)
    }
    END { print ids }'
}

base_refs() {  # append-only bases, one "<ref> <label>" per line
  if [ -n "${GUARD_BASE_REF:-}" ]; then printf '%s %s\n' "$GUARD_BASE_REF" "$GUARD_BASE_REF"; return 0; fi
  echo "HEAD HEAD"
  command -v git >/dev/null 2>&1 || return 0
  local up mb head   # + the upstream fork point: a row deleted in an unpushed commit is caught too
  up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || return 0
  mb="$(git merge-base HEAD '@{u}' 2>/dev/null)" || return 0
  head="$(git rev-parse --verify --quiet HEAD 2>/dev/null)"
  [ -n "$up" ] && [ -n "$mb" ] && [ "$mb" != "$head" ] \
    && printf '%s upstream %s fork point %s\n' "$mb" "$up" "$(printf '%s' "$mb" | cut -c1-7)"
  return 0
}

ledger_integrity() {
  local rows problems="" row id rule guard kind val path name dups ref label old missing oid count
  if [ ! -f "$LEDGER" ]; then   # a ledger that existed at a base ref must not vanish
    if [ "${ALLOW_GUARD_CHANGE:-0}" != "1" ] && command -v git >/dev/null 2>&1; then
      while read -r ref label; do
        [ -n "$ref" ] || continue
        if git cat-file -e "$ref:./$LEDGER" 2>/dev/null; then
          echo "ERROR: $LEDGER was deleted since $label (owner OK = ALLOW_GUARD_CHANGE=1)"; return 1
        fi
      done <<REFS
$(base_refs)
REFS
    fi
    echo "SKIP: no $LEDGER"; return 77
  fi
  rows="$(ledger_rows < "$LEDGER")"
  count="$(printf '%s\n' "$rows" | grep -c '^|')"
  add() { problems="${problems:+$problems
}$1"; }

  dups="$(printf '%s\n' "$rows" | awk -F'|' 'NF { print $2 }' | sort | uniq -d | paste -sd ',' -)"
  [ -n "$dups" ] && add "duplicate ID(s) $dups"

  while IFS= read -r row; do
    [ -n "$row" ] || continue
    row="${row//\\|/%PIPE%}"
    id="$(printf '%s' "$row" | awk -F'|' '{ print $2 }')"
    rule="$(printf '%s' "$row" | awk -F'|' '{ print $4 }')"
    guard="$(printf '%s' "$row" | awk -F'|' '{ print ($NF == "" ? $(NF-2) : $(NF-1)) }')"
    guard="$(printf '%s' "$guard" | tr -d '`' | sed -e 's/^ *//' -e 's/ *$//')"
    case "$(printf '%s' "$rule" | sed -E 's/^[ _*~`]*//' | tr '[:upper:]' '[:lower:]')" in retired:*) continue ;; esac
    case "$guard" in *:*) ;; *) add "$id: guard must start with test:, check: or review:"; continue ;; esac
    kind="$(printf '%s' "${guard%%:*}" | tr '[:upper:]' '[:lower:]')"
    val="$(printf '%s' "${guard#*:}" | sed -e 's/^ *//' -e 's/ *$//')"
    case "$kind" in
      test)
        case "$val" in *::*) ;; *) add "$id: test guard needs <path>::<name>"; continue ;; esac
        path="${val%%::*}"; name="${val##*::}"; name="${name%%\[*}"
        path="${path#./}"; name="$(printf '%s' "$name" | sed -e 's/^ *//' -e 's/ *$//')"
        if [ ! -f "$path" ]; then add "$id: test file $path not found"
        elif [ -z "$name" ] || ! grep -qF -- "$name" "$path"; then add "$id: test $name not found in $path"; fi ;;
      check)
        if ! printf '%s' "$val" | grep -Eq '^[A-Za-z0-9._-]+$'; then add "$id: bad check step name '$val'"
        elif ! step_defined "$SELF" "$val"; then add "$id: check step $val missing in .claude/$(basename "$SELF")"
        elif [ -f "$TWIN" ] && ! step_defined "$TWIN" "$val"; then add "$id: check step $val missing in .claude/guards.ps1 (keep runners in sync)"; fi ;;
      review)
        [ -n "$val" ] || add "$id: review guard needs an observable outcome" ;;
      *) add "$id: unknown guard type '$kind' (use test:, check: or review:)" ;;
    esac
  done <<EOF
$rows
EOF

  if [ "${ALLOW_GUARD_CHANGE:-0}" = "1" ]; then
    echo "NOTE: append-only check bypassed by ALLOW_GUARD_CHANGE=1"
  elif ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "append-only check skipped: not a git work tree"
  else
    while read -r ref label; do   # every base: HEAD (+ upstream fork point), or GUARD_BASE_REF
      [ -n "$ref" ] || continue
      if ! git rev-parse --verify --quiet "$ref^{commit}" >/dev/null 2>&1; then
        if [ -n "${GUARD_BASE_REF:-}" ]; then add "GUARD_BASE_REF $ref not found (CI: checkout with fetch-depth: 0 - after a force push the old tip may be missing)"
        else echo "append-only check skipped: no commit yet"; fi
      elif old="$(git show "$ref:./$LEDGER" 2>/dev/null)"; then
        echo "append-only vs $label"
        missing=""
        while IFS= read -r row; do
          [ -n "$row" ] || continue
          if ! printf '%s\n' "$rows" | grep -qxF -- "$row"; then
            oid="$(printf '%s' "$row" | awk -F'|' '{ print $2 }')"
            missing="${missing:+$missing,}$oid"
          fi
        done <<EOF
$(printf '%s\n' "$old" | ledger_rows)
EOF
        [ -n "$missing" ] && add "row(s) $missing removed or edited since $label (ledger is append-only, owner OK = ALLOW_GUARD_CHANGE=1)"
      else
        echo "append-only check skipped: $LEDGER not in $label"
      fi
    done <<REFS
$(base_refs)
REFS
  fi

  echo "rows: $count"
  [ -n "$problems" ] || return 0
  echo "ERROR: $(printf '%s\n' "$problems" | wc -l | tr -d ' ') ledger problem(s): $(printf '%s\n' "$problems" | paste -sd ';' - | sed 's/;/; /g')"
  printf '%s\n' "$problems"
  return 1
}

# ---------------------------------------------------------------- steps (order = output order)
step ledger-integrity -- ledger_integrity
step content-lint -- content_lint
step lint -- run_configured LINT_CMD

# ---- project check: steps. Uncomment/adapt, add the same step to guards.ps1, and reference it
# ---- in REGRESSIONS.md as "check: <name>".
# check_mysql_binlog_expiry() {   # R-00x ops/mysql: binlogs expire after 1 day
#   local f="infra/mysql/my.cnf"
#   [ -f "$f" ] || { echo "ERROR: $f not found"; return 1; }
#   grep -Eq '^[[:space:]]*binlog[_-]expire[_-]logs[_-]seconds[[:space:]]*=[[:space:]]*86400[[:space:]]*$' "$f" \
#     || { echo "ERROR: $f must set binlog_expire_logs_seconds=86400 (1 day)"; return 1; }
# }
# step mysql-binlog-expiry -- check_mysql_binlog_expiry
#
# check_worker_topology() {       # R-00x ops/workers: 6 stream workers + 1 queue worker
#   local f="infra/supervisor/workers.conf" s q
#   s="$(grep -c '^\[program:stream-' "$f")"; q="$(grep -c '^\[program:queue-' "$f")"
#   [ "$s" -eq 6 ] && [ "$q" -eq 1 ] || { echo "ERROR: $f has $s stream / $q queue workers, want 6 / 1"; return 1; }
# }
# step worker-topology -- check_worker_topology

step tests slow -- run_configured TEST_CMD

# ---------------------------------------------------------------- summary
total=$((ok + failed + skipped))
if [ "$failed" -eq 0 ]; then
  summary="guards: PASS - $ok ok, 0 failed, $skipped skipped of $total"
else
  summary="guards: FAIL - $ok ok, $failed failed ($failed_names), $skipped skipped of $total"
fi
[ "$FAST" -eq 1 ] && summary="$summary [--fast: not valid for done]"
summary="$summary (log: $LOG)"
echo "$summary"; echo "$summary" >> "$LOG"
[ "$failed" -eq 0 ] || exit 1
exit 0
