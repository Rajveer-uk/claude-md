#!/usr/bin/env bash
# guards.sh - claude-md's OWN guard runner: this repo eats its own dog food. Every rule in
# REGRESSIONS.md ("check: <step>") is a step below, so the hard rule - additive or strict upgrades
# only, never remove or weaken an agent, skill, command, hook capability, deny rule, plan default,
# bypass-disable, least-privilege tools list, network scoping or the verify allowlist gate - is
# enforced mechanically, locally and in CI (.github/workflows/guards.yml).
# Template for other projects: templates/guards.sh (same conventions).
#
# Usage:  bash .claude/guards.sh          full set - always before calling work done
#         bash .claude/guards.sh --fast   skips steps marked slow - mid-task only
# Output: one line per step - "OK <step>", "ERROR <step>: <reason>" or "SKIP <step>: <reason>" -
#         then one summary line. Full output of every step is appended to .claude/guards.log
#         (gitignored). Every step runs; exit 1 if any step failed, 2 on a usage error.
# Env:    GUARD_BASE_REF      git ref the "never shrink" baselines are read from with
#                             git show <ref>:<file>. Default: HEAD plus, when the branch has an
#                             upstream, its fork point (merge-base with @{u}), so a removal in a
#                             committed-but-unpushed commit is caught too. CI sets origin/<base>
#                             on PRs and the pre-push commit on pushes.
#         ALLOW_GUARD_CHANGE  1 = owner's explicit OK (CI: PR label guard-change-approved).
#                             Turns base-ref diffs (a lost deny entry, agent, tool restriction or
#                             ledger row) into a NOTE. Absolute invariants (plan default,
#                             bypass-disable, WebFetch/WebSearch denied, network scoping, parsing)
#                             still fail - changing those means editing this file with owner OK.
# Needs:  bash, grep, sed, awk, git, python3 (stdlib only). Optional: the claude CLI (plugin-validate
#         runs only when it is on PATH; otherwise SKIP). No network, no secrets.
set -u

LEDGER="REGRESSIONS.md"

# ---------------------------------------------------------------- setup
here="$(cd "$(dirname "$0")" && pwd)"
SELF="$here/$(basename "$0")"
case "$here" in
  */.claude) root="${here%/.claude}" ;;
  *) root="$(git -C "$here" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$here")" ;;
esac
cd "$root" || { echo "ERROR guards: cannot cd to $root"; exit 2; }

FAST=0
for arg in "$@"; do
  case "$arg" in
    --fast) FAST=1 ;;
    -h|--help) sed -n '2,25p' "$SELF"; exit 0 ;;
    *) echo "usage: bash .claude/guards.sh [--fast]" >&2; exit 2 ;;
  esac
done

base_refs() {  # "never shrink" bases, one "<ref> <label>" per line
  if [ -n "${GUARD_BASE_REF:-}" ]; then printf '%s %s\n' "$GUARD_BASE_REF" "$GUARD_BASE_REF"; return 0; fi
  echo "HEAD HEAD"
  command -v git >/dev/null 2>&1 || return 0
  local up mb head   # + the upstream fork point: a removal in an unpushed commit is caught too
  up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || return 0
  mb="$(git merge-base HEAD '@{u}' 2>/dev/null)" || return 0
  head="$(git rev-parse --verify --quiet HEAD 2>/dev/null)"
  [ -n "$up" ] && [ -n "$mb" ] && [ "$mb" != "$head" ] \
    && printf '%s upstream %s fork point %s\n' "$mb" "$up" "$(printf '%s' "$mb" | cut -c1-7)"
  return 0
}
BASES="$(base_refs)"
BASE="$(printf '%s\n' "$BASES" | cut -d' ' -f2- | paste -sd ',' - | sed 's/,/ + /g')"   # labels, for the log
mkdir -p .claude
LOG=".claude/guards.log"
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 1048576 ]; then   # keep the log under ~1 MB
  tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
printf '\n=== guards %s%s (base %s%s) ===\n' "$(date '+%Y-%m-%d %H:%M:%S')" \
  "$([ "$FAST" -eq 1 ] && echo ' --fast')" "$BASE" \
  "$([ "${ALLOW_GUARD_CHANGE:-0}" = "1" ] && echo ', ALLOW_GUARD_CHANGE=1')" >> "$LOG"

ok=0; failed=0; skipped=0; failed_names=""
ESC="$(printf '\033')"

one_line() {  # $1 = step output, $2 = exit code -> the most useful single line
  local out line
  out="$(printf '%s\n' "$1" | sed -e "s/${ESC}\[[0-9;]*[A-Za-z]//g" -e 's/\r$//')"
  line="$(printf '%s\n' "$out" | sed -n 's/^ERROR: //p' | head -n 1)"
  [ -n "$line" ] || line="$(printf '%s\n' "$out" | grep -iE 'fail|error|invalid|warning' | head -n 1)"
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

# ---------------------------------------------------------------- python3 checks (stdlib only)
PYTHON=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 \
     && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)' >/dev/null 2>&1; then
    PYTHON="$c"; break
  fi
done

IFS= read -r -d '' PYCHECKS <<'PY' || true
import json, os, re, subprocess, sys

BASE = os.environ.get('GUARD_BASE') or 'HEAD'
SHOW = os.environ.get('GUARD_BASE_LABEL') or BASE   # BASE as shown in messages
ALLOW = os.environ.get('ALLOW_GUARD_CHANGE', '') == '1'
LOG = '.claude/guards.log'

NET_AGENTS = ('plugins/marketing/agents/content-researcher.md',
              'plugins/marketing/agents/seo-rank-monitor.md')
NET_PREFIX = 'mcp__plugin_marketing_'          # plugin-scoped MCP names: mcp__plugin_<plugin>_<server>__<tool>
READONLY_MARKERS = {'Write', 'Edit', 'Bash'}   # an agent with none of these at the base ref is read-only
WRITE_EXEC = {'Write', 'Edit', 'MultiEdit', 'NotebookEdit', 'Bash', 'PowerShell'}
AGENT_RE = re.compile(r'^(?:plugins/[^/]+|\.claude)/agents/[^/]+\.md$')
SKILL_RE = re.compile(r'^(?:plugins/[^/]+|\.claude)/skills/[^/]+/SKILL\.md$')
COMMAND_RE = re.compile(r'^(?:plugins/[^/]+|\.claude)/commands/[^/]+\.md$')
KEEP_RE = re.compile(r'^(?:plugins/.+|templates/.+|\.claude/hooks/[^/]+|\.claude-plugin/marketplace\.json'
                     r'|\.claude/settings\.json|\.claude/settings\.hooks\.example\.json'
                     r'|managed/managed-settings\.json)$')
BUDGETS = (('global/CLAUDE.md', 70), ('CLAUDE.md', 60))
HOOKS_EXAMPLE = '.claude/settings.hooks.example.json'

# public-safe allow-list: only genuine placeholders/examples found in the tree. Adding one needs owner OK.
EMAIL_OK_DOMAINS = ('example.com', 'example.net', 'example.org')    # RFC 2606, plus their subdomains
EMAIL_OK_TLDS = ('example', 'test', 'invalid', 'localhost')         # RFC 2606 / 6761 reserved TLDs
EMAIL_OK_LITERALS = {
    'you@your-domain.com', 'your@email.com', 'valid@email.com',     # placeholders (ecc docs)
    'user+tag@example.co.uk', 'mock@test.com', 'email@test.com',    # test fixtures (ecc skills)
    'user@test.com',
    'secret@db.internal',                                           # user:secret@host DSN placeholder
    '-@dev.md',                                                     # file-name pattern <date>-@dev.md
}
IPV4_OK = {'0.0.0.0', '127.0.0.1', '10.0.0.0', '172.16.0.0', '192.168.0.0'}  # bind-all, loopback, RFC 1918 bases
IPV4_OK_PREFIXES = ('192.0.2.', '198.51.100.', '203.0.113.')                  # RFC 5737 documentation ranges
SECRET_OK_LITERALS = {'AKIAIOSFODNN7EXAMPLE'}                                   # AWS documentation example key id
EMAIL_RE = re.compile(r'(?<![A-Za-z0-9._%+-])([A-Za-z0-9._%+-]+)@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})\b')
IPV4_RE = re.compile(r'(?<![\w.])(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?!\.?\d)')
SECRET_RES = (
    ('Anthropic API key', re.compile(r'sk-ant-[A-Za-z0-9_-]{20,}')),
    ('GitHub token', re.compile(r'\bgh[pousr]_[A-Za-z0-9]{36,}')),
    ('GitHub fine-grained token', re.compile(r'\bgithub_pat_[A-Za-z0-9_]{22,}')),
    ('AWS access key id', re.compile(r'\b(?:AKIA|ASIA)[0-9A-Z]{16}\b')),
    ('private key block', re.compile(r'-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----')),
    ('Slack token', re.compile(r'\bxox[abposr]-[A-Za-z0-9-]{10,}')),
)


# ---- output protocol (see step() in the bash runner)
def done(hard=(), soft=(), note=None):
    """hard problems always fail; soft = base-ref diffs, downgraded to a NOTE by ALLOW_GUARD_CHANGE=1."""
    hard, soft = list(hard), list(soft)
    for p in hard + soft:
        print('  - ' + p)
    probs = hard + (soft if not ALLOW else [])
    if probs:
        more = ' (+%d more, see .claude/guards.log)' % (len(probs) - 1) if len(probs) > 1 else ''
        print('ERROR: ' + probs[0] + more)
        sys.exit(1)
    if soft:
        print('NOTE: ALLOW_GUARD_CHANGE=1 approved %d change(s) vs %s, listed in .claude/guards.log' % (len(soft), SHOW))
    elif note:
        print('NOTE: ' + note)
    sys.exit(0)


# ---- files: working tree (tracked + untracked, not ignored) and the base ref
def sh(args):
    r = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return r.returncode, r.stdout.decode('utf-8', 'replace')


_cache = {}


def work_paths():
    if 'work' not in _cache:
        rc, out = sh(['git', 'ls-files', '-z', '-co', '--exclude-standard'])
        paths = [p for p in out.split('\0') if p] if rc == 0 else []
        if rc != 0:
            for d, dirs, files in os.walk('.'):
                dirs[:] = [x for x in dirs if x != '.git']
                paths += [os.path.relpath(os.path.join(d, f)).replace(os.sep, '/') for f in files]
        _cache['work'] = sorted(p for p in set(paths) if p != LOG and os.path.isfile(p))
    return _cache['work']


def require_base():
    if 'base_ok' not in _cache:
        _cache['base_ok'] = sh(['git', 'rev-parse', '--verify', '--quiet', BASE + '^{commit}'])[0] == 0
    if not _cache['base_ok']:
        done(hard=['base ref %s not found (set GUARD_BASE_REF; CI needs fetch-depth: 0 - after a force push the old tip may be missing)' % SHOW])


def base_paths():
    require_base()
    rc, out = sh(['git', 'ls-tree', '-r', '-z', '--name-only', BASE])
    return [p for p in out.split('\0') if p]


def base_text(path):
    require_base()
    rc, out = sh(['git', 'show', '%s:%s' % (BASE, path)])
    return out if rc == 0 else None


def read(path):
    with open(path, 'rb') as f:
        return f.read().decode('utf-8', 'replace')


def load_json_text(text):
    def pairs(items):
        d = {}
        for k, v in items:
            if k in d:
                raise ValueError('duplicate key %r' % k)
            d[k] = v
        return d
    return json.loads(text, object_pairs_hook=pairs)


def load_json_file(path):
    with open(path, 'rb') as f:
        raw = f.read()
    if raw.startswith(b'\xef\xbb\xbf'):
        raise ValueError('UTF-8 BOM (JSON loaders reject it)')
    return load_json_text(raw.decode('utf-8'))


def load_or_fail(path):
    if not os.path.isfile(path):
        done(hard=['%s missing' % path])
    try:
        return load_json_file(path)
    except (ValueError, UnicodeDecodeError) as e:
        done(hard=['%s does not parse: %s' % (path, e)])


def perms(d):
    p = d.get('permissions') if isinstance(d, dict) else None
    return p if isinstance(p, dict) else {}


# ---- frontmatter (stdlib-only YAML subset check; agrees with a YAML loader on every file in this repo)
KEY_RE = re.compile(r'''^(?:([A-Za-z_$][\w$.-]*)|"([^"\\]*)"|'([^']*)')[ \t]*:(?:[ \t]+(.*))?$''')


def _scan_quote(s):
    """s starts with a quote; return index just past the closing quote, or -1."""
    q, j = s[0], 1
    while j < len(s):
        c = s[j]
        if q == '"' and c == '\\':
            j += 2
            continue
        if c == q:
            if q == "'" and j + 1 < len(s) and s[j + 1] == "'":
                j += 2
                continue
            return j + 1
        j += 1
    return -1


def _flow_end(s):
    """s starts with [ or {; return index just past the matching bracket, or -1."""
    depth, q = 0, None
    for j, c in enumerate(s):
        if q:
            if c == q:
                q = None
        elif c in '"\'':
            q = c
        elif c in '[{':
            depth += 1
        elif c in ']}':
            depth -= 1
            if depth == 0:
                return j + 1
    return -1


def _unquote(s):
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] == '"':
        try:
            return json.loads(s)
        except ValueError:
            return s[1:-1]
    if len(s) >= 2 and s[0] == s[-1] == "'":
        return s[1:-1].replace("''", "'")
    return s


def parse_fm(text):
    """Returns (top-level fields, errors). Flags what breaks YAML loaders: no --- block, an unquoted
    value containing ': ', reserved leading characters, unterminated quotes, tabs, duplicate keys."""
    if text.startswith('\ufeff'):
        text = text[1:]
    lines = [l.rstrip('\r') for l in text.split('\n')]
    if not lines or lines[0].rstrip() != '---':
        return {}, ['no frontmatter (first line is not ---)']
    end = next((i for i in range(1, len(lines)) if lines[i].rstrip() == '---'), None)
    if end is None:
        return {}, ['frontmatter has no closing --- line']
    body, fields, errs = lines[1:end], {}, []
    cont = None        # ('block'|'plain', indent, top-level key or None)
    container = None   # top-level key whose value continues on the next lines
    i = 0
    while i < len(body):
        raw = body[i]
        n = i + 2
        i += 1
        s = raw.strip()
        ind = len(raw) - len(raw.lstrip(' '))
        if cont and cont[0] == 'block':
            if not s or ind > cont[1]:
                if cont[2] and s:
                    fields[cont[2]] = (fields[cont[2]] + ' ' + s).strip()
                continue
            cont = None
        if not s or s.startswith('#'):
            continue
        if raw[:len(raw) - len(raw.lstrip())].find('\t') >= 0:
            errs.append('line %d: tab in indentation' % n)
            continue
        if cont and cont[0] == 'plain':
            if ind > cont[1]:
                if re.search(r':(\s|$)', re.split(r'\s#', s, 1)[0]):
                    errs.append('line %d: unquoted continuation line contains ": "' % n)
                if cont[2]:
                    fields[cont[2]] += ' ' + s
                continue
            cont = None
        if s == '-' or s.startswith('- '):
            if container is not None and isinstance(fields.get(container), list):
                fields[container].append(_unquote(s[1:]))
            elif ind == 0:
                errs.append('line %d: list item outside a list' % n)
            continue
        m = KEY_RE.match(s)
        if not m:
            if container is not None and ind > 0 and fields.get(container) == []:
                if re.search(r':(\s|$)', re.split(r'\s#', s, 1)[0]):
                    errs.append('line %d: unquoted value contains ": "' % n)
                fields[container] = s
                cont = ('plain', 0, container)
                container = None
                continue
            errs.append('line %d: not a "key: value" line: %s' % (n, s[:60]))
            continue
        key = m.group(1) or m.group(2) or m.group(3)
        val = (m.group(4) or '').strip()
        top = ind == 0
        if top:
            if key in fields:
                errs.append('line %d: duplicate key %s' % (n, key))
            container = None
        elif container is not None and fields.get(container) == []:
            fields[container] = {}
        if val == '' or val.startswith('#'):
            if top:
                fields[key] = []
                container = key
            continue
        c0 = val[0]
        if c0 in '"\'':
            joined = val
            endq = _scan_quote(joined)
            while endq < 0 and i < len(body):
                joined += ' ' + body[i].strip()
                i += 1
                endq = _scan_quote(joined)
            if endq < 0:
                errs.append('line %d: unterminated quoted %s value' % (n, key))
                continue
            rest = joined[endq:].strip()
            if rest and not rest.startswith('#'):
                errs.append('line %d: text after the closing quote of %s' % (n, key))
            if top:
                fields[key] = _unquote(joined[:endq])
        elif c0 in '[{':
            joined = val
            endf = _flow_end(joined)
            while endf < 0 and i < len(body):
                joined += ' ' + body[i].strip()
                i += 1
                endf = _flow_end(joined)
            if endf < 0:
                errs.append('line %d: unclosed [ or { in %s' % (n, key))
                continue
            rest = joined[endf:].strip()
            if rest and not rest.startswith('#'):
                errs.append('line %d: text after the closing bracket of %s (quote the value)' % (n, key))
            if top:
                fields[key] = joined[:endf]
        elif c0 in '|>':
            if not re.match(r'^[|>][+-]?[1-9]?[+-]?\s*(#.*)?$', val):
                errs.append('line %d: bad block scalar header for %s' % (n, key))
            if top:
                fields[key] = ''
            cont = ('block', ind, key if top else None)
        elif c0 in '@`%' or val.startswith('- ') or val.startswith('? ') or val.startswith(': '):
            errs.append('line %d: %s value starts with a YAML indicator %r (quote it)' % (n, key, val[:2]))
        elif c0 in '&*!':
            if top:
                fields[key] = val
        else:
            plain = re.split(r'\s#', val, 1)[0].rstrip()
            if re.search(r':(\s|$)', plain):
                errs.append('line %d: unquoted %s value contains ": " (quote it or use >-)' % (n, key))
            if top:
                fields[key] = plain
            cont = ('plain', ind, key if top else None)
    return fields, errs


def _split_top(s):
    out, depth, cur, q = [], 0, '', None
    for c in s:
        if q:
            cur += c
            if c == q:
                q = None
            continue
        if c in '"\'':
            q = c
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        elif c == ',' and depth <= 0:
            out.append(cur)
            cur = ''
            continue
        cur += c
    out.append(cur)
    return out


def tool_list(fields):
    """Declared tools, or None when there is no tools: list (the agent inherits every tool)."""
    if 'tools' not in fields:
        return None
    v = fields['tools']
    if isinstance(v, dict):
        return None
    if not isinstance(v, list):
        v = v.strip()
        if v.startswith('[') and v.endswith(']'):
            v = v[1:-1]
        v = _split_top(v)
    out = []
    for t in v:
        t = str(t).strip().strip('"\'').strip()
        if t:
            out.append(t)
    return out


def tname(t):
    return t.split('(', 1)[0].strip()


def is_net(t):
    n = tname(t)
    return n in ('WebFetch', 'WebSearch') or n.startswith('mcp__')


def effective_tools(text):
    """(tools or None, errors). Frontmatter that does not parse loads with every field ignored,
    so its tools: list is dropped and the agent inherits every tool - treat that as None."""
    f, errs = parse_fm(text)
    return (None if errs else tool_list(f)), errs


def agent_paths():
    return [p for p in work_paths() if AGENT_RE.match(p)]


# ---- steps
def st_json_parse():
    files = [p for p in work_paths() if p.endswith('.json')]
    bad = []
    for p in files:
        try:
            load_json_file(p)
        except (ValueError, UnicodeDecodeError) as e:
            bad.append('%s: %s' % (p, e))
    print('%d JSON files checked' % len(files))
    done(hard=bad)


def st_frontmatter():
    probs, n = [], 0
    for p in work_paths():
        kind = ('agent' if AGENT_RE.match(p) else 'skill' if SKILL_RE.match(p)
                else 'command' if COMMAND_RE.match(p) else None)
        if not kind:
            continue
        n += 1
        f, errs = parse_fm(read(p))
        probs += ['%s: %s' % (p, e) for e in errs]
        if not errs and kind in ('agent', 'skill'):
            for k in ('name', 'description'):
                v = f.get(k)
                if not isinstance(v, str) or not v.strip():
                    probs.append('%s: missing %s' % (p, k))
    print('%d agent/skill/command files checked' % n)
    done(hard=probs)


def st_settings_baseline():
    path = '.claude/settings.json'
    p = perms(load_or_fail(path))
    hard = []
    if p.get('defaultMode') != 'plan':
        hard.append('%s: permissions.defaultMode is %r, must be "plan"' % (path, p.get('defaultMode')))
    if p.get('disableBypassPermissionsMode') != 'disable':
        hard.append('%s: permissions.disableBypassPermissionsMode is %r, must be "disable"'
                    % (path, p.get('disableBypassPermissionsMode')))
    done(hard=hard)


def rules_never_shrink(path, cur):
    """Soft problems for every deny/ask rule present at the base ref but gone now."""
    soft, hard = [], []
    for key in ('deny', 'ask'):
        v = cur.get(key, [])
        if not isinstance(v, list) or not all(isinstance(x, str) for x in v):
            hard.append('%s: permissions.%s must be a list of strings' % (path, key))
    bt = base_text(path)
    if bt is None:
        print('%s not in %s: nothing to compare' % (path, SHOW))
        return hard, soft
    try:
        bp = perms(load_json_text(bt))
    except ValueError as e:
        print('%s at %s does not parse (%s): nothing to compare' % (path, SHOW, e))
        return hard, soft
    for key in ('deny', 'ask'):
        now = cur.get(key) if isinstance(cur.get(key), list) else []
        was = bp.get(key) if isinstance(bp.get(key), list) else []
        print('permissions.%s: %d entries now, %d at %s' % (key, len(now), len(was), SHOW))
        soft += ['%s: permissions.%s lost %r (vs %s)' % (path, key, r, SHOW) for r in was if r not in now]
    return hard, soft


def st_settings_deny():
    path = '.claude/settings.json'
    cur = perms(load_or_fail(path))
    hard, soft = rules_never_shrink(path, cur)
    deny = cur.get('deny') if isinstance(cur.get('deny'), list) else []
    hard += ['%s: permissions.deny must contain %s' % (path, t) for t in ('WebFetch', 'WebSearch') if t not in deny]
    done(hard, soft)


def st_managed_settings():
    path = 'managed/managed-settings.json'
    cur = perms(load_or_fail(path))
    hard, soft = rules_never_shrink(path, cur)
    if cur.get('disableBypassPermissionsMode') != 'disable':
        hard.append('%s: permissions.disableBypassPermissionsMode must be "disable"' % path)
    done(hard, soft)


def st_network_agents():
    hard, agents = [], agent_paths()
    hard += ['%s missing (one of the two network agents)' % p for p in NET_AGENTS if p not in agents]
    for p in agents:
        f, errs = parse_fm(read(p))
        tools = None if errs else tool_list(f)
        if p in NET_AGENTS:
            if tools is None:
                hard.append('%s: no parseable tools: list' % p)
                continue
            names = {tname(t) for t in tools if is_net(t)}
            web = sorted(t for t in names if not t.startswith('mcp__'))
            if web:
                hard.append('%s: network agents use their MCP tools only, found %s' % (p, ', '.join(web)))
            classic = {t for t in names if t.startswith('mcp__') and not t.startswith('mcp__plugin_')}
            scoped = {t for t in names if t.startswith('mcp__plugin_')}
            if not classic:
                hard.append('%s: lists no classic mcp__<server>__<tool> tool' % p)
            for t in sorted(classic):
                if NET_PREFIX + t[len('mcp__'):] not in scoped:
                    hard.append('%s: %s has no plugin-scoped twin %s' % (p, t, NET_PREFIX + t[len('mcp__'):]))
            for t in sorted(scoped):
                if not t.startswith(NET_PREFIX):
                    hard.append('%s: %s is not a marketing-plugin MCP tool' % (p, t))
                elif 'mcp__' + t[len(NET_PREFIX):] not in classic:
                    hard.append('%s: %s has no classic twin mcp__%s' % (p, t, t[len(NET_PREFIX):]))
            continue
        if errs:
            hard.append('%s: frontmatter does not parse, so tools: is ignored (inherits every tool, incl. network)' % p)
            continue
        if tools is None:
            hard.append('%s: no tools: list (inherits every tool, incl. network)' % p)
        else:
            net = sorted({tname(t) for t in tools if is_net(t)})
            if net:
                hard.append('%s: network tool(s) %s outside content-researcher/seo-rank-monitor' % (p, ', '.join(net)))
        if 'mcpServers' in f:
            hard.append('%s: mcpServers outside content-researcher/seo-rank-monitor' % p)
    print('%d agents checked' % len(agents))
    done(hard=hard)


def st_readonly_agents():
    readonly = []
    for p in base_paths():
        if AGENT_RE.match(p):
            tools, _ = effective_tools(base_text(p) or '')
            if tools is not None and not ({tname(t) for t in tools} & READONLY_MARKERS):
                readonly.append(p)
    print('read-only agents at %s (no Write/Edit/Bash): %d' % (SHOW, len(readonly)))
    soft = []
    for p in readonly:
        if not os.path.isfile(p):
            continue   # a removed agent is the inventory step's finding
        f, errs = parse_fm(read(p))
        if errs:
            soft.append('%s: frontmatter does not parse, so its read-only tools: list is ignored' % p)
            continue
        tools = tool_list(f)
        if tools is None:
            soft.append('%s: read-only agent lost its tools: list (inherits Write/Edit/Bash)' % p)
            continue
        gained = sorted({tname(t) for t in tools} & WRITE_EXEC)
        if gained:
            soft.append('%s: read-only agent gained %s' % (p, ', '.join(gained)))
        if 'memory' in f:
            soft.append('%s: memory: on a read-only agent auto-grants Read/Write/Edit' % p)
    done(soft=soft)


def st_agent_network_growth():
    soft, agents = [], agent_paths()
    for p in agents:
        bt = base_text(p)
        if bt is None:
            base_tools = []              # new agent: starts from zero network tools
        else:
            base_tools, _ = effective_tools(bt)
            if base_tools is None:
                continue                 # inherited every tool at the base ref: nothing to grow into
        f, errs = parse_fm(read(p))
        cur = None if errs else tool_list(f)
        if cur is None:
            soft.append('%s: tools: list %s - the agent inherits every tool, incl. network'
                        % (p, 'does not parse' if errs else 'is missing'))
            continue
        plugin = p.split('/')[1] if p.startswith('plugins/') else None
        base_net = {tname(t) for t in base_tools if is_net(t)}
        twins = {'mcp__plugin_%s_%s' % (plugin, t[len('mcp__'):]) for t in base_net
                 if plugin and t.startswith('mcp__') and not t.startswith('mcp__plugin_')}
        grown = sorted({tname(t) for t in cur if is_net(t)} - base_net - twins)
        if grown:
            soft.append('%s: tools: gained network tool(s) %s (vs %s)' % (p, ', '.join(grown), SHOW))
    print('%d agents checked' % len(agents))
    done(soft=soft)


def st_inventory():
    soft, kept = [], 0
    for p in base_paths():
        if KEEP_RE.match(p):
            kept += 1
            if not os.path.isfile(p):
                soft.append('%s removed (vs %s)' % (p, SHOW))
    mp = '.claude-plugin/marketplace.json'
    bt = base_text(mp)
    if bt is not None:
        try:
            was = {x.get('name') for x in load_json_text(bt).get('plugins', []) if isinstance(x, dict)}
        except (ValueError, AttributeError):
            was = set()
        now_d = load_or_fail(mp)
        now = {x.get('name') for x in now_d.get('plugins', []) if isinstance(x, dict)}
        soft += ['%s: plugin entry %r removed (vs %s)' % (mp, n, SHOW) for n in sorted(was - now, key=str)]
    print('%d protected files at %s' % (kept, SHOW))
    done(soft=soft)


def _code_only(text, ps1):
    if ps1:
        text = re.sub(r'<#.*?#>', '', text, flags=re.S)
    return '\n'.join(l for l in text.split('\n') if not l.lstrip().startswith('#'))


def st_verify_gate():
    hard = []
    for p in ('.claude/hooks/verify.sh', '.claude/hooks/verify.ps1'):
        if not os.path.isfile(p):
            hard.append('%s missing' % p)
        elif 'verify-allowed.txt' not in _code_only(read(p), p.endswith('.ps1')):
            hard.append('%s: the verify-allowed.txt allowlist gate is gone from its code' % p)
    done(hard=hard)


def hook_entries(d, event):
    h = d.get('hooks') if isinstance(d, dict) else None
    ev = h.get(event) if isinstance(h, dict) else None
    return [e for e in ev if isinstance(e, dict)] if isinstance(ev, list) else []


def entry_commands(e):
    hs = e.get('hooks')
    return [str(x.get('command', '')) for x in hs if isinstance(x, dict)] if isinstance(hs, list) else []


def matcher_covers(m, tool):
    if m in (None, '', '*'):
        return True
    m = str(m)
    if re.fullmatch(r'[A-Za-z0-9_|]+', m):
        return tool in m.split('|')
    try:
        return re.search(m, tool) is not None
    except re.error:
        return False


def st_guard_matcher():
    d = load_or_fail(HOOKS_EXAMPLE)
    guards = [e for e in hook_entries(d, 'PreToolUse')
              if any(re.search(r'guard\.(sh|ps1)', c) for c in entry_commands(e))]
    if not guards:
        done(hard=['%s: no PreToolUse entry runs guard.sh / guard.ps1' % HOOKS_EXAMPLE])
    miss = [t for t in ('Bash', 'PowerShell', 'Monitor', 'Write', 'Edit')
            if not any(matcher_covers(e.get('matcher'), t) for e in guards)]
    done(hard=['%s: guard hook matcher does not cover %s' % (HOOKS_EXAMPLE, ', '.join(miss))] if miss else [])


def st_hook_registrations():
    d = load_or_fail(HOOKS_EXAMPLE)
    hard = []
    for event, pat, what in (('PreToolUse', r'guard\.(sh|ps1)', 'guard'),
                             ('PostToolUse', r'format\.(sh|ps1)', 'format'),
                             ('Stop', r'verify\.(sh|ps1)', 'verify')):
        if not any(re.search(pat, c) for e in hook_entries(d, event) for c in entry_commands(e)):
            hard.append('%s: %s no longer registers the %s hook' % (HOOKS_EXAMPLE, event, what))
    if 'UserPromptSubmit' not in read(HOOKS_EXAMPLE):
        hard.append('%s: the opt-in per-prompt UserPromptSubmit snippet is missing' % HOOKS_EXAMPLE)
    done(hard=hard)


def st_hook_optin_snippet():
    # R-018 only checks for the text "UserPromptSubmit", which verify's own turn-start entry now also
    # contains - so check the opt-in delegation snippet and the verify marker explicitly.
    d = load_or_fail(HOOKS_EXAMPLE)
    hard = []
    snip = d.get('_optional_perPromptDelegationReminder')
    blob = json.dumps(snip) if snip is not None else ''
    if not snip:
        hard.append('%s: _optional_perPromptDelegationReminder (the old per-prompt delegation hook, opt-in) is missing' % HOOKS_EXAMPLE)
    elif 'UserPromptSubmit' not in blob or 'Standing directive' not in blob:
        hard.append('%s: _optional_perPromptDelegationReminder no longer holds the UserPromptSubmit delegation directive' % HOOKS_EXAMPLE)
    if not any(re.search(r'verify\.(sh|ps1)', c) for e in hook_entries(d, 'UserPromptSubmit') for c in entry_commands(e)):
        hard.append('%s: verify is no longer registered on UserPromptSubmit (turn-start marker for review-only turns)' % HOOKS_EXAMPLE)
    done(hard=hard)


def st_base_hook():
    path = 'plugins/base/hooks/hooks.json'
    d = load_or_fail(path)
    hard = []
    if not isinstance(d.get('description'), str) or not d['description'].strip():
        hard.append('no top-level "description"')
    hooks = d.get('hooks') if isinstance(d.get('hooks'), dict) else {}
    if sorted(hooks) != ['SessionStart']:
        hard.append('hook events are %s, must be only SessionStart (no per-prompt hook)' % sorted(hooks))
    entries = hook_entries(d, 'SessionStart')
    if not entries:
        hard.append('no SessionStart entry')
    for e in entries:
        m = str(e.get('matcher', ''))
        if sorted(m.split('|')) != ['clear', 'compact', 'startup']:
            hard.append('SessionStart matcher %r must be startup|clear|compact' % m)
        hs = e.get('hooks') if isinstance(e.get('hooks'), list) else []
        if not hs:
            hard.append('SessionStart entry has no hooks')
        for h in hs:
            c = str(h.get('command', '')) if isinstance(h, dict) else ''
            mm = re.fullmatch(r"echo '([^']*)'", c)
            if not isinstance(h, dict) or h.get('type') != 'command' or not mm:
                hard.append('command must be one single-quoted echo: echo \'...\'')
                continue
            text = mm.group(1)
            if any(ord(ch) > 127 for ch in c):
                hard.append('command must be ASCII only')
            if not text.strip() or text.lstrip().startswith('{'):
                hard.append('echo text must be non-empty plain text (not JSON)')
            hard += ['echo text no longer mentions %s' % w for w in ('REGRESSIONS.md', 'regression-guard') if w not in text]
    done(hard=['%s: %s' % (path, x) for x in hard])


def loaded_lines(text):
    t = text.replace('\r\n', '\n')
    t = re.sub(r'(?ms)^[ \t]*<!--(?:(?!-->).)*-->[ \t]*(?:\n|\Z)', '', t)   # whole-line comments vanish
    t = re.sub(r'(?s)<!--(?:(?!-->).)*-->', '', t)                           # inline comments
    lines = t.split('\n')
    if lines and lines[-1] == '':
        lines.pop()
    return len(lines)


def st_line_budgets():
    hard, notes = [], []
    for p, cap in BUDGETS:
        if not os.path.isfile(p):
            hard.append('%s missing' % p)
            continue
        n = loaded_lines(read(p))
        notes.append('%s %d/%d' % (p, n, cap))
        if n > cap:
            hard.append('%s has %d loaded lines (HTML comments excluded), max %d' % (p, n, cap))
    print('loaded lines: ' + ', '.join(notes))
    done(hard=hard)


def _email_ok(local, domain):
    addr, dom = ('%s@%s' % (local, domain)).lower(), domain.lower()
    return (addr in EMAIL_OK_LITERALS or dom.rsplit('.', 1)[-1] in EMAIL_OK_TLDS
            or any(dom == d or dom.endswith('.' + d) for d in EMAIL_OK_DOMAINS))


def _ip_ok(ip):
    return ip in IPV4_OK or ip.startswith(IPV4_OK_PREFIXES)


def st_public_safe():
    hits, scanned = [], 0
    for p in work_paths():
        try:
            with open(p, 'rb') as f:
                raw = f.read(5 * 1024 * 1024)
        except OSError:
            continue
        if b'\0' in raw[:8192]:
            continue                      # binary
        scanned += 1
        for ln, line in enumerate(raw.decode('utf-8', 'replace').split('\n'), 1):
            if '@' in line:
                for m in EMAIL_RE.finditer(line):
                    if not _email_ok(m.group(1), m.group(2)):
                        hits.append('%s:%d: email address ***@%s' % (p, ln, m.group(2)))
            for m in IPV4_RE.finditer(line):
                ip = '.'.join(m.groups())
                if all(int(x) <= 255 for x in m.groups()) and not _ip_ok(ip):
                    hits.append('%s:%d: IPv4 address %s' % (p, ln, ip))
            for label, rx in SECRET_RES:
                for m in rx.finditer(line):
                    if m.group(0) not in SECRET_OK_LITERALS:
                        hits.append('%s:%d: %s (value not shown)' % (p, ln, label))
    print('%d text files scanned' % scanned)
    done(hard=hits)


def st_readme_agent_badge():
    n = len([p for p in work_paths() if re.match(r'^plugins/[^/]+/agents/[^/]+\.md$', p)])
    if not os.path.isfile('README.md'):
        done(hard=['README.md missing'])
    badges = re.findall(r'img\.shields\.io/badge/agents-(\d+)-', read('README.md'))
    if not badges:
        done(hard=['README.md: no agents badge (img.shields.io/badge/agents-<n>-...)'])
    done(hard=['README.md: agents badge says %s, plugins/*/agents/*.md has %d' % (b, n) for b in badges if int(b) != n])


# ---- prompt hygiene: model-loaded prompt files never gain CAPS emphasis or verification/thinking rituals
PROMPT_RE = re.compile(r'^(?:global/CLAUDE\.md|CLAUDE\.md|claude-ai/[^/]+\.md|templates/(?:CLAUDE\.package|SPEC)\.md'
                       r'|plugins/base/hooks/hooks\.json|plugins/(?:base|marketing|council)/(?!.*/evals/).+\.md)$')
PROMPT_SKIP = ('README.md', 'ATTRIBUTION.md', 'CHANGELOG.md')
CAPS_RE = re.compile(r'\b(MUST|NEVER|ALWAYS|IMPORTANT|CRITICAL)\b')
RITUAL_RE = re.compile(r'double[- ]check|verify twice|re-verify|verify (?:it |your work )?before finali[sz]|'
                       r'maximally thorough|think step[- ]by[- ]step|think hard(?:er)?\b|ultrathink|megathink', re.I)


def hygiene_hits(text):
    t = re.sub(r'(?s)<!--.*?-->', '', (text or '').replace('\r\n', '\n'))   # maintainer comments cost 0 tokens
    hits = []
    for line in t.split('\n'):
        for m in CAPS_RE.finditer(line):
            if m.group(1) == 'CRITICAL' and 'HIGH' in line:   # severity vocabulary (CRITICAL / HIGH / ...)
                continue
            hits.append(line.strip())
        hits += [line.strip() for _ in RITUAL_RE.finditer(line)]
    return hits


def st_prompt_hygiene():
    soft, n = [], 0
    for p in work_paths():
        if not PROMPT_RE.match(p) or p.rsplit('/', 1)[-1] in PROMPT_SKIP:
            continue
        n += 1
        cur = hygiene_hits(read(p))
        was = hygiene_hits(base_text(p)) if cur else []
        if len(cur) > len(was):
            new = [h for h in cur if h not in was] or cur
            soft.append('%s: %d CAPS-emphasis/ritual hit(s), %d at %s - write it in normal case, without the ritual: %s'
                        % (p, len(cur), len(was), SHOW, new[0][:120]))
    print('%d prompt files checked' % n)
    done(soft=soft)


# ---- plan-gate Stop hook keeps its bounds; the completeness chain keeps its load-bearing parts
def st_plan_gate_bounds():
    hard = []
    for p in ('.claude/hooks/plan-gate.sh', '.claude/hooks/plan-gate.ps1'):
        if not os.path.isfile(p):
            hard.append('%s missing' % p)
            continue
        code = _code_only(read(p), p.endswith('.ps1'))
        for what, pat in (('the plan-mode exit', r'''permission_?[Mm]ode[\s\S]{0,400}?["']plan["']'''),
                          ('the session-matched marker', r'plan-gate\.local\.json'),
                          ('the session_id match', r'session_?[Ii]d'),
                          ('the CLAUDE_PLAN_GATE_MAX_BLOCKS cap', r'CLAUDE_PLAN_GATE_MAX_BLOCKS')):
            if not re.search(pat, code):
                hard.append('%s: %s is gone from its code' % (p, what))
    d = load_or_fail(HOOKS_EXAMPLE)
    if not any(re.search(r'plan-gate\.(sh|ps1)', c) for e in hook_entries(d, 'Stop') for c in entry_commands(e)):
        hard.append('%s: Stop no longer registers the plan-gate hook' % HOOKS_EXAMPLE)
    if os.path.isfile('.claude/hooks/plan-gate.sh') and sh(['bash', '-c', 'true'])[0] == 0:
        hard += ['.claude/hooks/plan-gate.sh: ' + x for x in _plan_gate_behaviour(os.path.abspath('.claude/hooks/plan-gate.sh'))]
    done(hard=hard)


def _plan_gate_behaviour(script):
    """Runs the hook on throwaway fixtures (own TMPDIR, so no shared state): the bounds must hold in behaviour too."""
    import shutil, tempfile
    tmp = tempfile.mkdtemp(prefix='plangate-guard-')
    probs = []
    try:
        proj = os.path.join(tmp, 'proj')
        os.makedirs(os.path.join(proj, '.claude'))
        os.makedirs(os.path.join(tmp, 't'))
        plan = os.path.join(proj, 'plan.md')
        env = dict(os.environ, TMPDIR=os.path.join(tmp, 't'))
        env.pop('CLAUDE_PLAN_GATE_MAX_BLOCKS', None)

        def put(text, session='s1'):
            with open(plan, 'w') as f:
                f.write(text)
            with open(os.path.join(proj, '.claude', 'plan-gate.local.json'), 'w') as f:
                json.dump({'session': session, 'plans': ['plan.md']}, f)

        def run(sid, mode='default', active=False, extra=None):
            e = dict(env, **(extra or {}))
            inp = json.dumps({'hook_event_name': 'Stop', 'session_id': sid, 'cwd': proj, 'permission_mode': mode,
                              'stop_hook_active': active, 'last_assistant_message': 'Task 1 is finished.'})
            r = subprocess.run(['bash', script], input=inp.encode(), stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, env=e, cwd=proj, timeout=60)
            return r.returncode

        put('# Plan\n- [ ] task one\n')
        for what, want, got in (('plan mode with an open item', 0, run('s1', mode='plan')),
                                ('marker from another session', 0, run('s2')),
                                ('own session with an open item', 2, run('s1'))):
            if got != want:
                probs.append('%s -> exit %s, expected %s' % (what, got, want))
        put('# Plan\n- [x] task one\nStatus: blocked - waiting on the owner\n', session='s3')
        if run('s3') != 0:
            probs.append('every item done or blocked -> should exit 0')
        put('# Plan\n- [ ] task one\n', session='s4')
        cap = {'CLAUDE_PLAN_GATE_MAX_BLOCKS': '1'}
        first = run('s4', extra=cap)
        put('# Plan\n- [ ] task one\n- [x] task two\n', session='s4')   # the plan moved, so only the cap can stop a block
        second = run('s4', active=True, extra=cap)
        if (first, second) != (2, 0):
            probs.append('CLAUDE_PLAN_GATE_MAX_BLOCKS=1 -> exits %s then %s, expected 2 then 0' % (first, second))
    except (OSError, subprocess.SubprocessError) as ex:
        probs.append('behaviour fixture failed to run: %s' % ex)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return probs


COMPLETENESS = (
    ('plugins/base/skills/requirements-gate/SKILL.md', ('AskUserQuestion', 'AC1', 'Requirements:', 'NEEDS_CONTEXT')),
    ('plugins/base/commands/spec.md', ('AskUserQuestion', 'templates/SPEC.md', '/implement-plan')),
    ('plugins/base/agents/completion-auditor.md', ('Unrequested', 'Requirements:')),
    ('plugins/base/commands/implement-plan.md', ('completion-auditor', 'Requirements:', 'plan-gate.local.json',
                                                 'NEEDS_CONTEXT', '--strict', 'features.json')),
    ('templates/SPEC.md', ('## Requirements', '## Plan', '## Evidence', 'Out of scope')),
    ('global/CLAUDE.md', ('requirements-gate', 'Requirements:')),
    ('CLAUDE.md', ('requirements-gate', 'Requirements:')),
)


def st_completeness_chain():
    hard = []
    for p, needles in COMPLETENESS:
        if not os.path.isfile(p):
            hard.append('%s missing' % p)
            continue
        t = read(p)
        hard += ['%s: no longer contains %r' % (p, w) for w in needles if w not in t]
    p = 'plugins/base/agents/completion-auditor.md'
    if os.path.isfile(p):
        tools = effective_tools(read(p))[0]
        if tools is None or {tname(t) for t in tools} & WRITE_EXEC or any(is_net(t) for t in tools):
            hard.append('%s: must keep an explicit read-only tools: list with no write, shell or network tool' % p)
    done(hard=hard)


def st_user_installer():
    """Runs scripts/install-user-config.sh on throwaway homes: the merge only ever adds."""
    import shutil, tempfile
    inst = os.path.abspath('scripts/install-user-config.sh')
    hard = []
    if not os.path.isfile(inst):
        done(hard=['scripts/install-user-config.sh missing'])
    cs = 'templates/cloud-setup.sh'
    if not os.path.isfile(cs):
        hard.append('%s missing' % cs)
    else:
        code = _code_only(read(cs), False)
        if not re.search(r'install-user-config\.sh"?\s+--cloud', code):
            hard.append('%s no longer runs install-user-config.sh --cloud' % cs)
        if not re.search(r'(?m)^exit 0\s*$', code):
            hard.append('%s must end with exit 0 (a failure never blocks a cloud session)' % cs)
    ps1 = 'scripts/install-user-config.ps1'
    if not os.path.isfile(ps1):
        hard.append('%s (the Windows twin) missing' % ps1)
    else:
        code = _code_only(read(ps1), True)
        for what, needle in (('the -Cloud preset', '$Cloud'), ('the backup before a change', '.bak'),
                             ('keeping an owner CLAUDE.md', 'claude-md-new'),
                             ('bypass disabled', 'disableBypassPermissionsMode'),
                             ('the Plan default only outside -Cloud', 'defaultMode')):
            if needle not in code:
                hard.append('%s: %s is gone from its code' % (ps1, what))
    base = load_or_fail('.claude/settings.json')
    bdeny, bask = base['permissions'].get('deny', []), base['permissions'].get('ask', [])
    tmp = tempfile.mkdtemp(prefix='installer-guard-')

    def home(name, settings=None, md=None):
        h = os.path.join(tmp, name)
        os.makedirs(os.path.join(h, '.claude'))
        if settings is not None:
            with open(os.path.join(h, '.claude', 'settings.json'), 'w') as f:
                f.write(settings if isinstance(settings, str) else json.dumps(settings))
        if md is not None:
            with open(os.path.join(h, '.claude', 'CLAUDE.md'), 'w') as f:
                f.write(md)
        return h

    def run(h, *args):
        env = dict(os.environ, HOME=h)
        r = subprocess.run(['bash', inst, '--files'] + list(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           env=env, cwd=tmp, timeout=120)
        return r.returncode

    def settings(h):
        with open(os.path.join(h, '.claude', 'settings.json')) as f:
            return json.load(f)
    try:
        stop = [{'hooks': [{'type': 'command', 'command': '/opt/harness/stop.sh'}]}]
        h = home('local', {'customKey': 1, 'hooks': {'Stop': stop},
                           'permissions': {'defaultMode': 'acceptEdits', 'deny': ['Bash(custom:*)']}}, '# My own notes\n')
        rc1 = run(h)
        s1 = settings(h)
        p = s1.get('permissions', {})
        checks = (
            ('exit 0 on a valid install', rc1 == 0),
            ('an unrelated key is kept', s1.get('customKey') == 1),
            ('an existing hook is kept', s1.get('hooks', {}).get('Stop') == stop),
            ('an existing deny entry is kept', 'Bash(custom:*)' in p.get('deny', [])),
            ('every baseline deny entry is added', all(x in p.get('deny', []) for x in bdeny)),
            ('every baseline ask entry is added', all(x in p.get('ask', []) for x in bask)),
            ('a non-plan defaultMode is kept', p.get('defaultMode') == 'acceptEdits'),
            ('bypass mode is disabled', p.get('disableBypassPermissionsMode') == 'disable'),
            ('a backup is written before the change', any('.bak' in n for n in os.listdir(os.path.join(h, '.claude')))),
            ("the owner's own CLAUDE.md is kept", read(os.path.join(h, '.claude', 'CLAUDE.md')) == '# My own notes\n'),
            ('the new CLAUDE.md goes next to it', os.path.isfile(os.path.join(h, '.claude', 'CLAUDE.md.claude-md-new'))),
            ('the base agents are copied', os.path.isfile(os.path.join(h, '.claude', 'agents', 'completion-auditor.md'))),
        )
        hard += ['local install: ' + what for what, good in checks if not good]
        rc2 = run(h)
        s2 = settings(h)
        if rc2 != 0 or s2 != s1 or len(s2['permissions']['deny']) != len(set(s2['permissions']['deny'])):
            hard.append('a re-run must change nothing and add no duplicate')
        h = home('cloud', {'hooks': {'Stop': stop}})
        if run(h, '--cloud') != 0:
            hard.append('cloud install: exit is not 0')
        else:
            sc = settings(h)
            if 'defaultMode' in sc.get('permissions', {}):
                hard.append('cloud install: must not set a Plan default (phone sessions and routines would stall)')
            if not os.path.isfile(os.path.join(h, '.claude', 'CLAUDE.md')):
                hard.append('cloud install: global CLAUDE.md not installed')
        h = home('broken', '{"permissions": [')
        if run(h) != 1 or read(os.path.join(h, '.claude', 'settings.json')) != '{"permissions": [':
            hard.append('an unparseable settings.json must be left untouched with exit 1')
    except (OSError, ValueError, subprocess.SubprocessError) as ex:
        hard.append('installer fixture failed to run: %s' % ex)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    done(hard=hard)


TEMPLATE_RUNNERS = (('templates/guards.sh', re.compile(r'^step\s+([A-Za-z0-9._-]+)', re.M)),
                    ('templates/guards.ps1', re.compile(r"^Step\s+'([A-Za-z0-9._-]+)'", re.M)))
TEMPLATE_STEPS_REQUIRED = {'ledger-integrity', 'content-lint', 'lint', 'tests', 'no-stubs', 'spec-integrity'}


def st_template_guard_steps():
    hard, soft, sets = [], [], {}
    for p, rx in TEMPLATE_RUNNERS:
        if not os.path.isfile(p):
            hard.append('%s missing' % p)
            continue
        sets[p] = cur = set(rx.findall(read(p)))
        hard += ['%s: step %s missing' % (p, s) for s in sorted(TEMPLATE_STEPS_REQUIRED - cur)]
        bt = base_text(p)
        was = set(rx.findall(bt)) if bt is not None else set()
        soft += ['%s: step %s removed (vs %s)' % (p, s, SHOW) for s in sorted(was - cur)]
    if len(sets) == 2:
        a, b = (sets[p] for p, _ in TEMPLATE_RUNNERS)
        if a != b:
            hard.append('templates/guards.sh and guards.ps1 define different steps: only sh %s, only ps1 %s'
                        % (sorted(a - b), sorted(b - a)))
    print('template steps: %s' % ', '.join(sorted(set().union(*sets.values())) if sets else '-'))
    done(hard=hard, soft=soft)


STEPS = {
    'prompt-hygiene': st_prompt_hygiene, 'plan-gate-bounds': st_plan_gate_bounds,
    'completeness-chain': st_completeness_chain, 'template-guard-steps': st_template_guard_steps,
    'user-installer': st_user_installer,
    'json-parse': st_json_parse, 'frontmatter': st_frontmatter,
    'settings-baseline': st_settings_baseline, 'settings-deny': st_settings_deny,
    'managed-settings': st_managed_settings, 'network-agents': st_network_agents,
    'readonly-agents': st_readonly_agents, 'agent-network-growth': st_agent_network_growth,
    'inventory': st_inventory, 'verify-gate': st_verify_gate, 'guard-matcher': st_guard_matcher,
    'hook-registrations': st_hook_registrations, 'hook-optin-snippet': st_hook_optin_snippet,
    'base-hook': st_base_hook,
    'line-budgets': st_line_budgets, 'public-safe': st_public_safe,
    'readme-agent-badge': st_readme_agent_badge,
}
if len(sys.argv) < 2 or sys.argv[1] not in STEPS:
    print('ERROR: unknown python check %r' % (sys.argv[1:2],))
    sys.exit(2)
STEPS[sys.argv[1]]()
PY

py() {  # py <check> - run one python3 check from PYCHECKS, once per base ref (BASES)
  [ -n "$PYTHON" ] || { echo "ERROR: python3 not found (needed for the JSON/frontmatter/config checks)"; return 1; }
  local ref label rc=0
  while read -r ref label; do
    [ -n "$ref" ] || continue
    printf '%s\n' "$PYCHECKS" | GUARD_BASE="$ref" GUARD_BASE_LABEL="$label" "$PYTHON" - "$@" || rc=$?
  done <<REFS
$BASES
REFS
  return "$rc"
}

# ---------------------------------------------------------------- bash checks
plugin_validate() {
  command -v claude >/dev/null 2>&1 || { echo "SKIP: claude CLI not on PATH"; return 77; }
  local d failed="" to=""
  command -v timeout >/dev/null 2>&1 && to="timeout 180"
  for d in . plugins/*; do
    if [ "$d" = . ]; then [ -f .claude-plugin/marketplace.json ] || continue
    else [ -f "$d/.claude-plugin/plugin.json" ] || continue; fi
    echo "\$ claude plugin validate $d --strict"
    # shellcheck disable=SC2086 # $to is intentionally word-split (empty or "timeout 180")
    $to claude plugin validate "$d" --strict 2>&1 || failed="${failed:+$failed, }$d"
  done
  [ -z "$failed" ] || { echo "ERROR: claude plugin validate --strict failed for $failed"; return 1; }
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
  grep -Eq "^[[:space:]]*step[[:space:]]+['\"]?$n['\"]?([[:space:]]|$)" "$1"
}

ledger_integrity() {  # the standard step (templates/guards.sh); here a missing ledger is an ERROR
  [ -f "$LEDGER" ] || { echo "ERROR: $LEDGER missing - this repo's guards are defined by it"; return 1; }
  local rows problems="" row id rule guard kind val path name dups ref label old missing oid count
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
        elif ! step_defined "$SELF" "$val"; then add "$id: check step $val missing in .claude/$(basename "$SELF")"; fi ;;
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
$BASES
REFS
  fi

  echo "rows: $count"
  [ -n "$problems" ] || return 0
  echo "ERROR: $(printf '%s\n' "$problems" | wc -l | tr -d ' ') ledger problem(s): $(printf '%s\n' "$problems" | paste -sd ';' - | sed 's/;/; /g')"
  printf '%s\n' "$problems"
  return 1
}

# ---------------------------------------------------------------- steps (order = output order)
# Each step is named in REGRESSIONS.md as "check: <step>". Never delete or loosen one without the
# owner's explicit OK (the guard hook asks before edits to this file).
step ledger-integrity -- ledger_integrity
step settings-baseline -- py settings-baseline
step settings-deny -- py settings-deny
step managed-settings -- py managed-settings
step network-agents -- py network-agents
step readonly-agents -- py readonly-agents
step agent-network-growth -- py agent-network-growth
step verify-gate -- py verify-gate
step guard-matcher -- py guard-matcher
step base-hook -- py base-hook
step line-budgets -- py line-budgets
step json-parse -- py json-parse
step frontmatter -- py frontmatter
step public-safe -- py public-safe
step readme-agent-badge -- py readme-agent-badge
step inventory -- py inventory
step hook-registrations -- py hook-registrations
step hook-optin-snippet -- py hook-optin-snippet
step prompt-hygiene -- py prompt-hygiene
step plan-gate-bounds -- py plan-gate-bounds
step completeness-chain -- py completeness-chain
step template-guard-steps -- py template-guard-steps
step user-installer -- py user-installer
step plugin-validate slow -- plugin_validate

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
