#!/usr/bin/env bash
# review-gate.sh - OPTIONAL PreToolUse hook (Linux / macOS / cloud): no `git commit` until the diff
# being committed has been reviewed. Windows twin: review-gate.ps1 (same logic).
#
# Rule it enforces (the owner's): every change is verified before it is applied - code-reviewer and
# ponytail review the diff, every blocking finding is fixed, the guards are re-run, and only then is
# the change committed. A tiny diff (up to CLAUDE_REVIEW_GATE_INLINE_MAX changed lines, default 10)
# may use the inline checklist instead of the two agents.
#
# Two modes, one script:
#   Hook (stdin = PreToolUse JSON for Bash / PowerShell / Monitor): when the command runs `git commit`,
#     it fingerprints the diff that commit would record (SHA-256 of `git diff --cached --binary`, or
#     `git diff HEAD` for -a/--all; git's SHA-1 only where neither sha256sum nor shasum exists) and
#     denies the call unless a review was recorded for exactly that fingerprint. Any edit after
#     recording changes the fingerprint and needs a new review. It follows `cd`/`pushd`/`Set-Location`
#     and `git -C` (quoted or not), a path-prefixed `git`/`git.exe`, global options such as --no-pager,
#     `sh -c '...'`, $(...), and commands on separate lines; a commit whose repository it can't
#     resolve, and a command holding more than one `git commit`, are denied. Other commands and
#     an empty diff (message-only amend) pass untouched. Unusual quoting (e.g. mixed quotes inside one
#     path) and a commit inside backticks (left out so a message may quote `git commit`) are not
#     followed - the rule, not only the hook, still applies.
#   Record (run by Claude after the review is clean):
#     bash ~/.claude/hooks/review-gate.sh --record agents   # code-reviewer + ponytail were clean
#     bash ~/.claude/hooks/review-gate.sh --record inline   # tiny diff, inline checklist (no binary files)
#     (add --all when the commit will use -a; add -C <dir> for another repo)
#
# The record lives outside the repo (private per-user temp dir, like verify.sh), so nothing is
# committed or left in the project. It proves a review step happened and was stated in the
# transcript, not how good the review was - the reviewers' findings stay visible in the chat.
# Env: CLAUDE_REVIEW_GATE=0 turns the hook off for that session (owner's call; visible in the
#      command); CLAUDE_REVIEW_GATE_INLINE_MAX (default 10; e.g. 50 for a lighter gate).
# Safe on any repo: runs only git read commands, no network, no project code. Fails open on any
# unexpected error (the permission gate and the guards still apply).
# Register (user scope, absolute path - see .claude/settings.hooks.example.json):
#   "PreToolUse": [ { "matcher": "Bash|PowerShell|Monitor", "hooks": [ { "type": "command", "command": "/home/you/.claude/hooks/review-gate.sh" } ] } ]
set -u

inline_max="${CLAUDE_REVIEW_GATE_INLINE_MAX:-10}"
case "$inline_max" in *[!0-9]*) inline_max=10 ;; esac
nl=$'\n'; cr=$'\r'   # bash 3.2: no $'..' inside "${..}" (see guard.sh)

sha256() {  # stdin -> hex digest (git's SHA-1 object hash where no SHA-256 tool is installed)
  if command -v sha256sum >/dev/null 2>&1; then sha256sum
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256
  else git hash-object --stdin; fi | cut -d' ' -f1
}

state_file() {  # $1 = repo top level -> private marker path (created lazily)
  local sdir key
  sdir="${TMPDIR:-/tmp}"; sdir="${sdir%/}/claude-verify-$(id -u 2>/dev/null || echo 0)"
  mkdir -p -m 700 "$sdir" 2>/dev/null && [ -d "$sdir" ] && [ ! -L "$sdir" ] && [ -O "$sdir" ] || return 1
  key="$(printf '%s' "$1" | sha256 | cut -c1-16)"
  printf '%s/review-%s.json' "$sdir" "$key"
}

fingerprint() {  # $1 = repo dir, $2 = 1 for -a/--all -> "<sha256> <changed lines> <binary files>" (empty: "- 0 0")
  local r=--cached
  [ "$2" = 1 ] && r=HEAD
  git -C "$1" diff "$r" --quiet 2>/dev/null
  [ $? = 1 ] || { echo "- 0 0"; return 0; }   # 0 = no diff; anything else but 1 = git failed
  printf '%s %s\n' "$(git -C "$1" diff "$r" --binary 2>/dev/null | sha256)" \
    "$(git -C "$1" diff "$r" --numstat 2>/dev/null | awk '{ if ($1 ~ /^[0-9]+$/) n += $1; else if ($1 == "-") b++; if ($2 ~ /^[0-9]+$/) n += $2 } END { print n + 0, b + 0 }')"
}

# ---------------------------------------------------------------- record mode
if [ "${1:-}" = "--record" ]; then
  mode="${2:-}"; shift 2 2>/dev/null || shift $#
  all=0; dir="$(pwd)"
  while [ $# -gt 0 ]; do
    case "$1" in
      --all|-a) all=1; shift ;;
      -C) dir="${2:-.}"; shift 2 2>/dev/null || shift $# ;;
      *) shift ;;
    esac
  done
  case "$mode" in agents|inline) ;; *) echo "usage: review-gate.sh --record agents|inline [--all] [-C dir]" >&2; exit 2 ;; esac
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || { echo "review-gate: $dir is not a git repo" >&2; exit 1; }
  set -- $(fingerprint "$top" "$all"); fp="$1"; n="$2"; b="$3"
  [ "$fp" = "-" ] && { echo "review-gate: nothing to commit - no review needed"; exit 0; }
  if [ "$mode" = inline ] && [ "$n" -gt "$inline_max" ]; then
    echo "review-gate: $n changed lines is more than the inline limit ($inline_max) - run code-reviewer and ponytail on the diff, then --record agents" >&2
    exit 1
  fi
  if [ "$mode" = inline ] && [ "$b" -gt 0 ]; then
    echo "review-gate: the diff changes $b binary file(s), which the inline checklist can't cover - run code-reviewer and ponytail on the diff, then --record agents" >&2
    exit 1
  fi
  sf="$(state_file "$top")" || { echo "review-gate: no private state dir available" >&2; exit 1; }
  printf '{"diff":"%s","mode":"%s","lines":%s,"at":"%s"}\n' "$fp" "$mode" "$n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$sf" \
    || { echo "review-gate: cannot write $sf" >&2; exit 1; }
  echo "review-gate: recorded an $mode review for this diff ($n changed lines). Commit now; any further edit needs a new review."
  exit 0
fi

# ---------------------------------------------------------------- hook mode (fail open)
trap 'exit 0' EXIT   # fail open: the verdict is the JSON printed below, never the exit code
[ "${CLAUDE_REVIEW_GATE:-1}" = 0 ] && exit 0
input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0
if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
else   # best-effort fallback: simple JSON only
  flat="$(printf '%s' "$input" | tr '\n\r' '  ')"
  tool="$(printf '%s' "$flat" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  cmd="$(printf '%s' "$flat" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(\([^"\\]\|\\.\)*\)".*/\1/p')"
  cwd="$(printf '%s' "$flat" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  cmd="${cmd//\\r/}"; cmd="${cmd//\\n/$nl}"   # JSON line breaks, still escaped here
fi
case "$tool" in Bash|PowerShell|Monitor) ;; *) exit 0 ;; esac
# One line: a line continuation (\ in sh, ` in PowerShell) joins, any other line break separates commands.
cont='\'; [ "$tool" = PowerShell ] && cont='`'
one="${cmd//$cr/}"; one="${one//"$cont$nl"/ }"; one="${one//$nl/;}"
# `git commit`, also `git -C dir commit` and `git -c k=v commit`, at the start of any command segment
garg='("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:];&|]+)'   # one argument, quoted or bare
gopt="[[:space:]]+(-[Cc][[:space:]]+$garg|--[a-z-]+(=$garg)?|-[pP])"   # git's global options before the subcommand
gcommit="(^|[;&|({]|&&|\\|\\||-c[[:space:]]+[\"'])[[:space:]]*([^[:space:];&|]*/)?git(\\.exe)?($gopt)*[[:space:]]+commit([[:space:];&|)\"']|\$)"
printf '%s' "$one" | grep -Eq "$gcommit" || exit 0
deny() {  # $1 = reason
  local r; r="$(printf '%s' "$1" | tr '\000-\037' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$r"
  exit 0
}
# one commit per command: pad each separator so back-to-back commits count apart
pad="$(printf '%s' "$one" | sed -E 's/[;&|()]/ & /g')"
[ $(( $(printf '%s' "$pad" | grep -oE "$gcommit" | wc -l) )) -gt 1 ] \
  && deny "review-gate: this command runs more than one git commit (or its message holds git commit after a line break, ; & | or (). Run one commit per command, each after its own review is recorded."
[ -n "$cwd" ] || cwd="$(pwd)"
unquote() { local v="$1"; v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"; case "$v" in "~") v="$HOME" ;; "~/"*) v="$HOME/${v#\~/}" ;; esac; printf '%s' "$v"; }
resolve() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$2" "$1" ;; esac; }
dir="$cwd"
# a `cd <dir>` earlier in the same command moves the commit (the last one before `git ... commit` wins)
before="$(printf '%s' "$one" | sed -E "s#$gcommit.*##")"   # gcommit holds "/" but never "#"
cdto="$(printf '%s' "$before" | grep -oiE "(^|[;&|({[:space:]])(cd|pushd|chdir|set-location|sl)[[:space:]]+(-path[[:space:]]+|-literalpath[[:space:]]+)?$garg" | tail -n 1 | sed -E 's/^.?[A-Za-z-]+[[:space:]]+(-[A-Za-z]*[Pp][Aa][Tt][Hh][[:space:]]+)?//')"
[ -n "$cdto" ] && dir="$(resolve "$(unquote "$cdto")" "$dir")"
# `git -C <dir> commit`, quoted or not - from the `git ... commit` match itself
cdir="$(printf '%s' "$one" | grep -oE "$gcommit" | head -n 1 | grep -oE "[[:space:]]-C[[:space:]]+$garg" | tail -n 1 | sed -E 's/^[[:space:]]-C[[:space:]]+//')"
[ -n "$cdir" ] && dir="$(resolve "$(unquote "$cdir")" "$dir")"
top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" \
  || deny "review-gate: can't tell which repository this commit runs in ($dir). Commit from the repository folder, or use git -C <repo> commit, after the review is recorded there."
all=0
printf '%s' "$one" | grep -Eq 'commit([[:space:]]+[^;&|]*)?[[:space:]](-a|--all|-[a-zA-Z]*a[a-zA-Z]*)([[:space:];&|)]|$)' && all=1
set -- $(fingerprint "$top" "$all"); fp="$1"; n="$2"
[ "$fp" = "-" ] && exit 0                         # nothing staged: message-only amend, --allow-empty
sf="$(state_file "$top")" || exit 0
if [ -f "$sf" ] && grep -q "\"diff\":\"$fp\"" "$sf" 2>/dev/null; then exit 0; fi
flag=" -C \"$top\""; [ "$all" = 1 ] && flag="$flag --all"
deny "review-gate: this commit's diff ($n changed lines) has no recorded review. Before committing: run code-reviewer and ponytail on the diff (git -C $top diff$([ "$all" = 1 ] && echo ' HEAD' || echo ' --cached')), fix every blocking finding, re-run the guards, then record it with: bash $0 --record agents$flag (a diff of $inline_max lines or fewer, with no binary file, may use the inline checklist: --record inline$flag). Then commit again. Any edit after recording needs a new review."
