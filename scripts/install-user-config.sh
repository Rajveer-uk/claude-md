#!/usr/bin/env bash
# install-user-config.sh - install the claude-md user layer into ~/.claude in one command: the
# security baseline (merged, never overwritten), the global working agreement (CLAUDE.md), the
# plugin packs, and optionally the guard / plan-gate hooks. Same script for a local machine
# (CLI + Desktop Code tab + IDEs share ~/.claude) and for cloud sessions (run from the cloud
# environment's Setup script - see templates/cloud-setup.sh). Windows: install-user-config.ps1.
#
# Usage (from anywhere):
#   bash scripts/install-user-config.sh                        # local: base pack, Plan default
#   bash scripts/install-user-config.sh --packs base,council   # more packs (base marketing council ecc)
#   bash scripts/install-user-config.sh --hooks guard,plan-gate   # also install + register these hooks
#   bash scripts/install-user-config.sh --cloud                # cloud preset: no Plan default, no hooks,
#                                                              #   marketplace = this clone (pinned ref)
# Options: --dest <dir> (default ~/.claude) · --marketplace <owner/repo | path> (default: this repo's
#          GitHub origin, else this folder) · --files (copy agents/skills/commands instead of installing
#          plugins; used automatically when the claude CLI is missing) · --replace-claude-md (replace a
#          CLAUDE.md that isn't ours, after a backup)
#
# Safety: settings.json is merged - deny/ask entries are only ever added, every other key and hook is
# kept, a timestamped backup is written before any change, and an unparseable file is left untouched
# (exit 1). An existing CLAUDE.md from an older claude-md release is backed up and replaced; any other
# CLAUDE.md is kept and the new one is written next to it as CLAUDE.md.claude-md-new. No network except
# the claude CLI fetching a GitHub marketplace; nothing outside --dest is written.
# Needs: bash, python3 (stdlib). Optional: the claude CLI (plugins), jq (runtime need of the guard hook).
# Exit: 0 installed (warnings possible) · 1 a step failed · 2 usage error.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
dest="$HOME/.claude"; packs="base"; hooks=""; cloud=0; files=0; marketplace=""; replace_md=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dest) dest="${2:?--dest needs a directory}"; shift 2 ;;
    --packs) packs="${2:?--packs needs a list}"; shift 2 ;;
    --hooks) hooks="${2:?--hooks needs a list}"; shift 2 ;;
    --marketplace) marketplace="${2:?--marketplace needs a source}"; shift 2 ;;
    --cloud) cloud=1; shift ;;
    --files) files=1; shift ;;
    --replace-claude-md) replace_md=1; shift ;;
    -h|--help) sed -n '2,/^set -u$/p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "usage: bash scripts/install-user-config.sh [--packs a,b] [--hooks guard,plan-gate] [--cloud] [--files] [--dest dir] [--marketplace src] [--replace-claude-md]" >&2; exit 2 ;;
  esac
done

rc=0
ok()   { echo "OK   $*"; }
note() { echo "NOTE $*"; }
warn() { echo "WARN $*"; }
fail() { echo "ERROR $*"; rc=1; }

for p in $(printf '%s' "$packs" | tr ',' ' '); do
  case "$p" in base|marketing|council|ecc) ;; *) echo "unknown pack: $p (base marketing council ecc)" >&2; exit 2 ;; esac
done
for h in $(printf '%s' "$hooks" | tr ',' ' '); do
  case "$h" in guard|plan-gate) ;; *) echo "unknown hook: $h (guard plan-gate; format/verify run project code - register them by hand, see setup.md)" >&2; exit 2 ;; esac
done
[ "$cloud" = 1 ] && [ -n "$hooks" ] && { warn "--hooks is ignored with --cloud"; hooks=""; }

PY=""
for c in python3 python; do
  command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)' 2>/dev/null && { PY="$c"; break; }
done
[ -n "$PY" ] || { echo "ERROR python3 is required (settings.json merge)"; exit 1; }
[ -f "$repo/.claude/settings.json" ] && [ -f "$repo/global/CLAUDE.md" ] || { echo "ERROR $repo is not a claude-md checkout"; exit 1; }
mkdir -p "$dest" || { echo "ERROR cannot create $dest"; exit 1; }
stamp="$(date +%Y%m%d-%H%M%S)"

# ---- 1. security baseline -> settings.json (merge, add-only)
"$PY" - "$repo/.claude/settings.json" "$dest/settings.json" "$cloud" "$stamp" <<'PY'
import json, os, shutil, sys
src, dst, cloud, stamp = sys.argv[1], sys.argv[2], sys.argv[3] == '1', sys.argv[4]
def load(p):
    with open(p, 'rb') as f:
        return json.loads(f.read().decode('utf-8-sig'))
base = load(src)
cur = {}
if os.path.exists(dst):
    try:
        cur = load(dst)
    except ValueError as e:
        print('ERROR %s does not parse (%s) - left untouched; fix it, then run again' % (dst, e)); sys.exit(1)
    if not isinstance(cur, dict):
        print('ERROR %s is not a JSON object - left untouched' % dst); sys.exit(1)
before = json.dumps(cur, sort_keys=True)
cur.setdefault('$schema', base.get('$schema'))
perms = cur.setdefault('permissions', {})
if not isinstance(perms, dict):
    print('ERROR %s: "permissions" is not an object - left untouched' % dst); sys.exit(1)
added = {}
for k in ('deny', 'ask'):
    have = perms.setdefault(k, [])
    if not isinstance(have, list):
        print('ERROR %s: permissions.%s is not a list - left untouched' % (dst, k)); sys.exit(1)
    new = [r for r in base['permissions'].get(k, []) if r not in have]
    have.extend(new)
    added[k] = len(new)
perms['disableBypassPermissionsMode'] = 'disable'
cur['useAutoModeDuringPlan'] = False
notes = []
if not cloud:
    mode = perms.get('defaultMode')
    if mode is None:
        perms['defaultMode'] = 'plan'
    elif mode != 'plan':
        notes.append('permissions.defaultMode is %r (kept); the baseline default is "plan"' % mode)
if json.dumps(cur, sort_keys=True) == before:
    print('OK   settings.json already has the baseline (%s)' % dst)
else:
    if os.path.exists(dst):
        shutil.copy2(dst, '%s.%s.bak' % (dst, stamp))
    tmp = dst + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(cur, f, indent=2, ensure_ascii=False)
        f.write('\n')
    load(tmp)
    os.replace(tmp, dst)
    print('OK   settings.json merged: +%d deny, +%d ask%s (%s)' % (
        added['deny'], added['ask'], '' if cloud else ', Plan default', dst))
for n in notes:
    print('NOTE ' + n)
PY
[ $? -eq 0 ] || rc=1

# ---- 2. global working agreement -> CLAUDE.md
md="$dest/CLAUDE.md"; src_md="$repo/global/CLAUDE.md"
if [ ! -e "$md" ]; then
  cp "$src_md" "$md" && ok "CLAUDE.md installed ($md)" || fail "cannot write $md"
elif cmp -s "$src_md" "$md"; then
  ok "CLAUDE.md already current"
elif [ "$replace_md" = 1 ] || grep -q '^# Working agreement (all projects)' "$md"; then
  cp "$md" "$md.$stamp.bak" && cp "$src_md" "$md" && ok "CLAUDE.md updated (backup: $md.$stamp.bak)" || fail "cannot update $md"
else
  cp "$src_md" "$md.claude-md-new" && warn "$md is your own file - kept; merge $md.claude-md-new into it by hand (or re-run with --replace-claude-md)"
fi

# ---- 3. packs: plugins via the claude CLI, else plain files
if [ -z "$marketplace" ]; then
  if [ "$cloud" = 1 ]; then
    marketplace="$repo"
  else
    origin="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
    slug="$(printf '%s' "$origin" | sed -En 's#^(https://github\.com/|git@github\.com:)([^/]+/[^/]+)$#\2#p' | sed 's/\.git$//')"
    marketplace="${slug:-$repo}"
  fi
fi
if [ "$files" = 0 ] && [ "$(cd "$dest" && pwd -P)" != "$(mkdir -p "$HOME/.claude" && cd "$HOME/.claude" && pwd -P)" ]; then
  note "--dest is not ~/.claude, where the claude CLI installs plugins - copying the packs as plain files instead"; files=1
fi
if [ "$files" = 0 ] && ! command -v claude >/dev/null 2>&1; then
  note "claude CLI not found - copying the packs as plain files instead of plugins"; files=1
fi
if [ "$files" = 0 ]; then
  if claude plugin marketplace list 2>/dev/null | grep -q 'claude-md-packs'; then
    claude plugin marketplace update claude-md-packs >/dev/null 2>&1 \
      && ok "marketplace claude-md-packs refreshed" || warn "marketplace claude-md-packs: refresh failed (kept the installed version)"
  elif claude plugin marketplace add "$marketplace" >/dev/null 2>&1; then
    ok "marketplace claude-md-packs added ($marketplace)"
  else
    fail "claude plugin marketplace add $marketplace failed - check the source (a private GitHub repo needs git credentials)"
  fi
  for p in $(printf '%s' "$packs" | tr ',' ' '); do
    if claude plugin install "$p@claude-md-packs" --scope user >/dev/null 2>&1; then
      claude plugin update "$p@claude-md-packs" >/dev/null 2>&1 || true
      ok "plugin $p@claude-md-packs installed (user scope)"
    else
      fail "claude plugin install $p@claude-md-packs failed"
    fi
  done
else
  mkdir -p "$dest/agents" "$dest/skills" "$dest/commands"
  for p in $(printf '%s' "$packs" | tr ',' ' '); do
    pd="$repo/plugins/$p"
    [ "$p" = ecc ] && { warn "ecc is not copied as files (about 15k always-on tokens; install it as a plugin per project)"; continue; }
    cp "$pd"/agents/*.md "$dest/agents/" 2>/dev/null || true
    for s in "$pd"/skills/*/; do [ -d "$s" ] && cp -R "${s%/}" "$dest/skills/"; done   # no trailing slash: BSD cp would copy the contents
    for c in "$pd"/commands/*.md; do
      [ -f "$c" ] || continue
      if [ "$p" = marketing ]; then cp "$c" "$dest/commands/marketing-$(basename "$c")"; else cp "$c" "$dest/commands/"; fi
    done
    ok "pack $p copied as files (agents, skills, commands) into $dest"
  done
fi

# ---- 4. optional hooks (local only): copy + register with absolute paths, never duplicated
if [ -n "$hooks" ]; then
  mkdir -p "$dest/hooks"
  for h in $(printf '%s' "$hooks" | tr ',' ' '); do
    cp "$repo/.claude/hooks/$h.sh" "$dest/hooks/$h.sh" && chmod +x "$dest/hooks/$h.sh" || { fail "cannot copy hook $h"; continue; }
  done
  "$PY" - "$dest/settings.json" "$dest/hooks" "$hooks" "$stamp" <<'PY'
import json, os, shutil, sys
dst, hdir, names, stamp = sys.argv[1], sys.argv[2], sys.argv[3].split(','), sys.argv[4]
with open(dst, 'rb') as f:
    cur = json.loads(f.read().decode('utf-8-sig'))
spec = {'guard': ('PreToolUse', {'matcher': 'Bash|PowerShell|Monitor|Write|Edit'}, {}),
        'plan-gate': ('Stop', {}, {'timeout': 15})}
hooks = cur.setdefault('hooks', {})
changed = []
for n in names:
    event, entry_extra, hook_extra = spec[n]
    cmd = os.path.join(hdir, n + '.sh')
    lst = hooks.setdefault(event, [])
    if any(n + '.sh' in str(h.get('command', '')) for e in lst if isinstance(e, dict)
           for h in (e.get('hooks') or []) if isinstance(h, dict)):
        print('OK   hook %s already registered on %s' % (n, event)); continue
    e = dict(entry_extra); e['hooks'] = [dict({'type': 'command', 'command': cmd}, **hook_extra)]
    lst.append(e); changed.append('%s on %s' % (n, event))
if changed:
    shutil.copy2(dst, '%s.%s.hooks.bak' % (dst, stamp))
    with open(dst + '.tmp', 'w', encoding='utf-8') as f:
        json.dump(cur, f, indent=2, ensure_ascii=False); f.write('\n')
    os.replace(dst + '.tmp', dst)
    print('OK   hooks registered: ' + ', '.join(changed))
PY
  [ $? -eq 0 ] || rc=1
  case ",$hooks," in *,guard,*) command -v jq >/dev/null 2>&1 || warn "the guard hook needs jq at runtime - install it (Ubuntu: sudo apt-get install -y jq; macOS: brew install jq)" ;; esac
fi

if [ "$rc" = 0 ]; then
  echo "DONE claude-md user layer installed into $dest$([ "$cloud" = 1 ] && echo ' (cloud preset)'). Start a new session, then check /context (memory files) and /plugin or @agent- (agents)."
else
  echo "FAILED - fix the ERROR line(s) above and run again (safe to re-run)."
fi
exit "$rc"
