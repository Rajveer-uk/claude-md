#!/usr/bin/env bash
# plan-gate.sh - OPTIONAL Stop hook (Linux/macOS). While an /implement-plan run still has open
# plan items or acceptance criteria, it keeps Claude from finishing (exit 2) and names the open
# items, a bounded number of times; then it stops blocking and warns "plan NOT complete".
# Windows twin: plan-gate.ps1 (same logic).
#
# Marker: it acts ONLY when <project>/.claude/plan-gate.local.json exists (gitignored by
# .claude/*.local.json). /implement-plan writes it at the start of a run and deletes it at the end:
#   {"session": "<session id>", "plans": ["specs/<slug>.md"]}
# "session" must equal this hook's session_id, so a marker from another session (or a committed
# one) never gates. A marker without "session" (or with an unsubstituted ${CLAUDE_SESSION_ID})
# counts only while it is less than 12 h old. Each plan path must be relative, without "..", ":"
# or symlinks, a regular file under the project, at most 1 MB; any other path is skipped.
#
# Open items (fenced code and HTML comments ignored): unchecked task boxes "- [ ]" / "* [ ]" /
# "1. [ ]"; "Status: todo | to do | pending | open | in progress | not started" (any case, also
# **Status**:, inline after the item text); Requirements rows "| AC<n> | ... |" whose Status cell is
# open | partial | not met. Everything else is closed: done, met, deferred, "Status: blocked - <reason>".
#
# It never blocks when a block cannot help: plan mode; no open item; a turn whose last line ends
# with "?" (Claude is asking the owner); a continuation in which no plan file changed since its
# last block (shows a systemMessage instead). It blocks at most CLAUDE_PLAN_GATE_MAX_BLOCKS times
# in a row per turn (default 3; 0 = never block, only warn), counted per session_id in the same
# private per-user temp dir as verify.sh; then it shows the owner a "plan NOT complete" message.
# Claude Code ends a turn after 8 consecutive Stop-hook continuations and that cap is shared by ALL
# Stop hooks (verify 3 + plan-gate 3 + the opt-in prompt check 1 = 7 fits).
#
# Safe on any repo: it reads only the marker and the plan files it names, runs no project code, no
# network, so it needs no allowlist. jq is optional (a sed fallback reads simple JSON). Any error:
# exit 0 (fail open). Register next to verify (see .claude/settings.hooks.example.json):
#   "Stop": [ ..., { "hooks": [ { "type": "command", "command": "/home/you/.claude/hooks/plan-gate.sh", "timeout": 15 } ] } ]
set -u
pg_block=0
trap 'rc=$?; if [ "$rc" = 2 ] && [ "$pg_block" = 1 ]; then exit 2; fi; exit 0' EXIT   # only the deliberate block exits non-zero

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0
havejq=0; command -v jq >/dev/null 2>&1 && havejq=1
flat="$(printf '%s' "$input" | tr -d '\n\r')"
jstr() { # $1 = key: best-effort value of a simple top-level JSON string field (no jq; escapes unsupported)
  printf '%s' "$flat" | sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"\\]*\)".*/\1/p'
}

cwd=""
if [ "$havejq" = 1 ]; then
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
else
  cwd="$(jstr cwd)"
fi
[ -z "$cwd" ] && cwd="$(pwd)"
marker="$cwd/.claude/plan-gate.local.json"
[ -f "$marker" ] || exit 0                 # no marker: not an /implement-plan run (the common, fast path)

event=""; sid=""; active="false"; mode=""
if [ "$havejq" = 1 ]; then
  event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null || true)"
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
  active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || true)"
  mode="$(printf '%s' "$input" | jq -r '.permission_mode // empty' 2>/dev/null || true)"
else
  event="$(jstr hook_event_name)"
  sid="$(jstr session_id)"
  printf '%s' "$flat" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && active="true"
  printf '%s' "$flat" | grep -Eq '"permission_mode"[[:space:]]*:[[:space:]]*"plan"' && mode="plan"
fi
[ "$mode" = "plan" ] && exit 0             # plan mode: Claude cannot edit files, so a block cannot help
[ -n "$event" ] && [ "$event" != "Stop" ] && exit 0   # registered elsewhere (e.g. SubagentStop): never gate

# ---- marker: {"session": "...", "plans": ["relative/path.md", ...]}
msize="$(wc -c < "$marker" 2>/dev/null | tr -d ' ')"
case "$msize" in ''|*[!0-9]*) exit 0 ;; esac
[ "$msize" -le 65536 ] || exit 0
mraw="$(cat "$marker" 2>/dev/null)" || exit 0
msess=""; plans=""
if [ "$havejq" = 1 ]; then
  printf '%s' "$mraw" | jq -e 'type == "object" and (.plans | type) == "array"' >/dev/null 2>&1 || exit 0
  msess="$(printf '%s' "$mraw" | jq -r 'if (.session | type) == "string" then .session else "" end' 2>/dev/null)" || exit 0
  plans="$(printf '%s' "$mraw" | jq -r '.plans[] | select(type == "string" and (explode | all(. >= 32)))' 2>/dev/null)" || exit 0
else
  mflat="$(printf '%s' "$mraw" | tr -d '\n\r')"
  case "$mflat" in *[![:space:]]*) ;; *) exit 0 ;; esac
  printf '%s' "$mflat" | grep -Eq '^[[:space:]]*\{.*\}[[:space:]]*$' || exit 0
  if printf '%s' "$mflat" | grep -Eq '"session"[[:space:]]*:'; then
    if ! printf '%s' "$mflat" | grep -Eq '"session"[[:space:]]*:[[:space:]]*null'; then
      msess="$(printf '%s' "$mflat" | sed -n 's/.*"session"[[:space:]]*:[[:space:]]*"\([^"\\]*\)".*/S:\1/p')"
      [ -n "$msess" ] || exit 0            # present but not a plain string: fail open
      msess="${msess#S:}"
    fi
  fi
  arr="$(printf '%s' "$mflat" | sed -n 's/.*"plans"[[:space:]]*:[[:space:]]*\[\([^]]*\)].*/A:\1/p')"
  [ -n "$arr" ] || exit 0
  arr="${arr#A:}"
  el='("[^"\\]*"|null|true|false|-?[0-9][0-9.eE+-]*)'   # strings are kept, other scalars ignored (as with jq)
  printf '%s' "$arr" | grep -Eq "^[[:space:]]*($el[[:space:]]*(,[[:space:]]*$el[[:space:]]*)*)?\$" || exit 0
  plans="$(printf '%s' "$arr" | tr ',' '\n' | sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p')"
fi
case "$msess" in '${CLAUDE_SESSION_ID}'|'$CLAUDE_SESSION_ID') msess="" ;; esac   # not substituted: no session
if [ -n "$msess" ]; then
  [ "$msess" = "$sid" ] || exit 0          # another session's (or a committed) marker never gates
else
  fresh="$(find "$marker" -prune -mmin -720 -print 2>/dev/null)"
  [ -n "$fresh" ] || exit 0                # session-less marker older than 12 h (or age unknown)
fi

# ---- plan files: relative, no "..", no ":", no symlink below cwd, regular file, <= 1 MB
valid_plan() {
  local p="$1" d comp oldifs
  case "$p" in ''|/*|\\*|\~*|*..*|*:*) return 1 ;; esac
  d="${cwd%/}"
  oldifs="$IFS"; IFS=/; set -f
  for comp in $p; do
    case "$comp" in ''|.) continue ;; esac
    d="$d/$comp"
    [ -L "$d" ] && { IFS="$oldifs"; set +f; return 1; }
  done
  IFS="$oldifs"; set +f
  [ -f "$d" ] && [ -r "$d" ] || return 1
  local size
  size="$(wc -c < "$d" 2>/dev/null | tr -d ' ')"
  case "$size" in ''|*[!0-9]*) return 1 ;; esac
  [ "$size" -le 1048576 ] || return 1
  return 0
}

# Prints one line (the item text, <= 80 chars) per open item of the file in $1.
scan() {
  LC_ALL=C awk '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function plain(s) { gsub(/[*_`]/, "", s); return trim(s) }
function sepok(w) { sub(/^[ \t]+/, "", w); return (w == "" || w ~ /^([,;.(:-]|\302\267|\342\200\224|\342\200\223)/) }
function isopen(v) { return match(v, /^(todo|to[ -]?do|pending|open|in[ -]?progress|not[ -]?started)/) && sepok(substr(v, RLENGTH + 1)) }
function acopen(v) { return match(v, /^(open|partial|not[ -]?met)/) && sepok(substr(v, RLENGTH + 1)) }
function emit(t) { gsub(/[*`]/, "", t); t = trim(t); gsub(/\t/, " ", t); if (t == "") t = "(no text)"; print substr(t, 1, 80) }
{
  line = $0; sub(/\r$/, "", line)
  if (!incom) {
    t = line; sub(/^[ \t]+/, "", t); f3 = substr(t, 1, 3)
    if (fence == "" && (f3 == "```" || f3 == "~~~")) { fence = f3; next }
    if (fence != "") { if (f3 == fence) fence = ""; next }
  }
  out = ""; rest = line
  while (1) {
    if (incom) { i = index(rest, "-->"); if (i == 0) { rest = ""; break }; rest = substr(rest, i + 3); incom = 0 }
    i = index(rest, "<!--"); if (i == 0) { out = out rest; break }
    out = out substr(rest, 1, i - 1); rest = substr(rest, i + 4); incom = 1
  }
  line = out
  if (line ~ /^[ \t]*$/) next
  if (line ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]+\[[ \t]\]/) {
    t = line; sub(/^[ \t]*([-*+]|[0-9]+[.)])[ \t]+\[[ \t]\][ \t]*/, "", t); emit(t); next
  }
  if (line ~ /^[ \t]*\|/) {
    tl = line; gsub(/\\\|/, "\001", tl); n = split(tl, c, "|"); first = tolower(plain(c[2]))
    if (first == "ac") { statcol = 0; for (k = 3; k <= n; k++) if (tolower(plain(c[k])) == "status") { statcol = k; break }; next }
    if (first ~ /^ac[0-9]+$/) {
      hit = 0
      if (statcol > 0) { if (statcol <= n && acopen(tolower(plain(c[statcol])))) hit = 1 }
      else { for (k = 3; k < n; k++) if (acopen(tolower(plain(c[k])))) { hit = 1; break } }
      if (hit) { r = plain(c[3]); gsub(/\001/, "|", r); emit(toupper(first) ": " r) }
      next
    }
  }
  s0 = line; gsub(/`[^`]*`/, "", s0); gsub(/[*_]/, "", s0); s = tolower(s0)
  if (match(s, /(^|[^a-z0-9])status[ \t]*:[ \t]*/)) {
    st = RSTART; sl = RLENGTH
    if (isopen(substr(s, st + sl))) {
      pre = substr(s0, 1, (substr(s, st, 6) == "status") ? st - 1 : st); sub(/^[ \t]*([-+>]|[0-9]+[.)])?[ \t]*/, "", pre)
      while (sub(/([ \t,;:(|-]|\302\267|\342\200\224|\342\200\223)$/, "", pre)) {}
      if (pre == "") pre = ctx
      if (pre == "") pre = trim(s0)
      emit(pre)
    }
    next
  }
  if (line ~ /^[ \t]*#/) { t = line; sub(/^[ \t]*#+[ \t]*/, "", t); ctx = plain(t) }
  else if (line ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]+/) { t = line; sub(/^[ \t]*([-*+]|[0-9]+[.)])[ \t]+(\[[ xX]\][ \t]*)?/, "", t); ctx = plain(t) }
}' "$1" 2>/dev/null | tr -d '\000-\011\013-\037\177'
}

total=0; names=""; items=""; hashin=""
oldifs="$IFS"; IFS='
'
set -f
nplans=0
for p in $plans; do
  IFS="$oldifs"
  nplans=$((nplans + 1)); [ "$nplans" -gt 20 ] && break
  valid_plan "$p" || continue
  f="${cwd%/}/$p"
  found="$(scan "$f")"
  hashin="$hashin$p:$(cksum < "$f" 2>/dev/null | awk '{ print $1 "-" $2 }');"
  [ -n "$found" ] || continue
  n="$(printf '%s\n' "$found" | grep -c .)"
  total=$((total + n))
  names="${names:+$names, }$p"
  items="${items:+$items
}$found"
done
IFS="$oldifs"; set +f

# ---- state: per-session counter + plan hash at the last block (private dir, like verify.sh)
key="$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9_-' | cut -c1-100)"
[ -z "$key" ] && key="no-session"
state=""
sdir="${TMPDIR:-/tmp}"; sdir="${sdir%/}/claude-verify-$(id -u 2>/dev/null || echo 0)"
if mkdir -p -m 700 "$sdir" 2>/dev/null && [ -d "$sdir" ] && [ ! -L "$sdir" ] && [ -O "$sdir" ]; then
  state="$sdir/$key.plangate"
fi

if [ "$total" -eq 0 ]; then                # every item closed (or no readable plan): done
  [ -n "$state" ] && rm -f "$state" 2>/dev/null
  exit 0
fi

# The turn ends with a question to the owner: let it stop (the answer starts a new turn).
msg=""
if [ "$havejq" = 1 ]; then
  msg="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"
else
  msg="$(printf '%s' "$flat" | sed -E -n 's/.*"last_assistant_message"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' |
    awk '{ gsub(/\\\\/, "\001"); gsub(/\\[nr]/, "\n"); gsub(/\\t/, " "); gsub(/\\"/, "\""); print }')"
fi
lastline="$(printf '%s\n' "$msg" | tr -d '\r' | grep -v '^[[:space:]]*$' | tail -n 1 | sed 's/[[:space:]*_`"'"'"')]*$//')"
case "$lastline" in *'?') [ -n "$state" ] && rm -f "$state" 2>/dev/null; exit 0 ;; esac

max="${CLAUDE_PLAN_GATE_MAX_BLOCKS:-3}"
case "$max" in ''|*[!0-9]*) max=3 ;; esac
[ "${#max}" -gt 4 ] && max=9999
max=$((10#$max))
hash="$(printf '%s' "$hashin" | cksum | awk '{ print $1 "-" $2 }')"
count=0; lasthash=""
if [ "$active" = "true" ]; then            # a continuation we (or another Stop hook) caused
  if [ -n "$state" ] && [ -f "$state" ]; then
    read -r count lasthash < "$state" 2>/dev/null || true
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    [ "${#count}" -gt 4 ] && count=9999
    count=$((10#$count))
  elif [ -z "$state" ]; then
    count="$max"                           # can't count safely: allow this stop
  fi
fi                                         # not active = first stop of a new turn: count 0
[ "${#names}" -gt 120 ] && names="$(printf '%s' "$names" | cut -c1-117)..."
say() { # non-blocking message shown to the owner (systemMessage)
  local m
  m="$(printf '%s' "$1" | tr '\t\r\n' '   ' | tr -d '\000-\037"\\')"
  printf '{"systemMessage":"%s"}\n' "$m"
}

if [ "$active" = "true" ] && [ "$count" -gt 0 ] && [ -n "$lasthash" ] && [ "$hash" = "$lasthash" ]; then
  [ -n "$state" ] && rm -f "$state" 2>/dev/null
  say "plan-gate: $total item(s) still open in $names and no plan file changed since the last nudge, so this stop is not blocked - plan NOT complete."
  exit 0
fi
if [ "$count" -ge "$max" ]; then
  [ -n "$state" ] && rm -f "$state" 2>/dev/null
  say "plan-gate: $total item(s) still open in $names after $count nudges - plan NOT complete. CLAUDE_PLAN_GATE_MAX_BLOCKS sets how many nudges are forced."
  exit 0
fi

count=$((count + 1))
[ -n "$state" ] && printf '%s %s\n' "$count" "$hash" > "$state" 2>/dev/null
list="$(printf '%s\n' "$items" | head -n 5 | awk '{ printf "%s%d) %s", (NR > 1 ? "; " : ""), NR, $0 }')"
more=""; [ "$total" -gt 5 ] && more=" (+$((total - 5)) more)"
pg_block=1
printf 'plan-gate: %s open item(s) in %s (nudge %s of %s). Implement them, or mark each Status: blocked — <reason>. Never mark an item done that isn'"'"'t. Open: %s%s\n' \
  "$total" "$names" "$count" "$max" "$list" "$more" | cut -c1-600 >&2
exit 2
