#!/usr/bin/env bash
# package-claude-ai.sh - validate skills and zip them for upload to a claude.ai account
# (Settings > Capabilities: code execution on; then Customize > Skills > + > Create skill > Upload a skill).
#
# Use it only for surfaces the account plugins don't reach: mobile, the API, cloud Code sessions,
# or an account without plugins. Where an account plugin (base / marketing / council) is installed,
# its skills are already there - uploading the same skill lists it twice (and it also syncs into
# signed-in local Claude Code as anthropic-skills:<name>, next to the plugin copy).
#
# Usage (from anywhere):
#   bash scripts/package-claude-ai.sh              # default set: regression-guard, work-quality-checker,
#                                                  #   ai-writing-tells, brand-voice, secure-code-reviewer
#   bash scripts/package-claude-ai.sh <skill> ...  # instead: skill folder paths, or bare names found
#                                                  #   under plugins/*/skills/ (e.g. caveman, council)
#
# Checks per skill - ERROR (not packaged): SKILL.md missing or its frontmatter unparseable; folder name
# differs from frontmatter `name`; name not ^[a-z0-9-]{1,64}$ or contains "anthropic"/"claude";
# description missing, over 1024 chars, or containing < or >; unquoted ": " in name/description.
# WARN (still packaged): description over 200 chars (help-center limit), SKILL.md body over 500 lines,
# frontmatter fields outside the Agent Skills set, symlinks (skipped). A missing skill folder is skipped.
#
# Output: dist/claude-ai/<name>.zip with the skill folder at the zip root (dist/ is gitignored).
# Needs bash + python3 (stdlib zipfile only). Exit 0 = all found skills packaged; 1 = an ERROR or
# nothing packaged; 2 = python3 missing or dist/ not writable.
set -u
unset CDPATH

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
out_dir="$repo_root/dist/claude-ai"
default_skills=(
  plugins/base/skills/regression-guard
  plugins/base/skills/work-quality-checker
  plugins/marketing/skills/ai-writing-tells
  plugins/marketing/skills/brand-voice
  plugins/base/skills/secure-code-reviewer
)

case "${1:-}" in
  -h|--help) sed -n '2,/^set -u$/p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR python3 not found - it validates and zips the skills (standard library only)" >&2
  exit 2
fi

# Validate one skill folder and zip it. argv: <skill dir> <out dir>. Prints OK/WARN/ERROR lines.
# Exit 0 = packaged (warnings allowed), 1 = not packaged.
IFS= read -r -d '' PACKAGER <<'PY'
import fnmatch, os, re, subprocess, sys, zipfile

src, out_dir = sys.argv[1], sys.argv[2]
folder = os.path.basename(os.path.normpath(src))
SAFE = {"name", "description", "license", "allowed-tools", "metadata", "compatibility", "version"}
JUNK_FILES = {".DS_Store", "Thumbs.db", "desktop.ini"}
JUNK_DIRS = {".git", "__pycache__"}
# Mirrors the settings.json secret deny-list: such files are never packaged, even if present on disk.
SECRET_NAMES = [".env", ".env.*", ".envrc", "*.pem", "*.key", "*.p12", "*.pfx", "*.keystore", "*.jks",
                "*.ppk", "id_rsa", "id_rsa.*", "id_ed25519", "id_ed25519.*", "*_rsa", "*_ed25519", "*_ecdsa",
                "*_dsa", ".git-credentials", ".netrc", ".npmrc", ".pypirc", ".pgpass", ".my.cnf",
                "credentials", "credentials.*", "*.credentials", "*.tfstate", "*.tfstate.backup", "*.tfvars",
                "gha-creds-*.json", "*service-account*.json"]
errors, warns = [], []

def is_secret(rel):
    parts = rel.lower().split("/")
    if "secrets" in parts[:-1]:
        return True
    return any(fnmatch.fnmatchcase(parts[-1], pat) for pat in SECRET_NAMES)

def is_git_ignored(path):
    # Skip files git ignores (e.g. a stray local file); outside a git work tree nothing is skipped.
    try:
        r = subprocess.run(["git", "-C", os.path.dirname(path) or ".", "check-ignore", "-q", path],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return r.returncode == 0
    except OSError:
        return False

def unquote_double(s):
    out, i = [], 0
    esc = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "/": "/", " ": " ", "0": "\0"}
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            if n == "u" and re.match(r"[0-9a-fA-F]{4}", s[i + 2:i + 6]):
                out.append(chr(int(s[i + 2:i + 6], 16))); i += 6; continue
            out.append(esc.get(n, n)); i += 2; continue
        out.append(c); i += 1
    return "".join(out)

def scalar(key, raw, cont):
    """Value of a top-level key: plain, quoted or block scalar. None = nested mapping/list."""
    raw = raw.strip()
    if raw[:1] in (">", "|"):                                   # block scalar: >, >-, |, |- ...
        body = [l for l in cont]
        nonblank = [l for l in body if l.strip()]
        if not nonblank:
            return ""
        ind = min(len(l) - len(l.lstrip(" ")) for l in nonblank)
        body = [l[ind:] if l.strip() else "" for l in body]
        if raw[0] == "|":
            return "\n".join(body).strip("\n")
        paras, cur = [], []
        for l in body:
            if l.strip():
                cur.append(l.strip())
            else:
                paras.append(" ".join(cur)); cur = []
        paras.append(" ".join(cur))
        return "\n".join(p for p in paras).strip("\n")
    joined = " ".join([raw] + [l.strip() for l in cont]).strip()
    if raw == "" and cont:
        return None                                             # nested block (e.g. metadata:)
    if raw[:1] == '"':
        m = re.match(r'^"((?:[^"\\]|\\.)*)"\s*(#.*)?$', joined)
        if not m:
            errors.append(f"{key}: unterminated or malformed double-quoted value")
            return joined
        return unquote_double(m.group(1))
    if raw[:1] == "'":
        m = re.match(r"^'((?:[^']|'')*)'\s*(#.*)?$", joined)
        if not m:
            errors.append(f"{key}: unterminated or malformed single-quoted value")
            return joined
        return m.group(1).replace("''", "'")
    value = re.split(r"\s#", joined, maxsplit=1)[0].strip()   # plain scalar: " #" starts a comment
    if key in ("name", "description") and (": " in value or value.endswith(":")):
        errors.append(f'{key}: unquoted ": " breaks YAML - wrap the value in double quotes or use >-')
    return value

skill_md = os.path.join(src, "SKILL.md")
if not os.path.isfile(skill_md):
    print(f"ERROR {folder}: no SKILL.md in {src}")
    sys.exit(1)
with open(skill_md, encoding="utf-8-sig") as f:
    lines = f.read().splitlines()

fields, body = {}, []
if not lines or lines[0].strip() != "---":
    errors.append("SKILL.md must start with a --- frontmatter line")
else:
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        errors.append("frontmatter has no closing --- line")
    else:
        fm, body = lines[1:end], lines[end + 1:]
        i = 0
        while i < len(fm):
            line = fm[i]
            if not line.strip() or line.lstrip().startswith("#"):
                i += 1; continue
            m = re.match(r"^([A-Za-z0-9_-]+):(?:[ \t]+(.*)|[ \t]*)$", line)
            if not m:
                errors.append(f"frontmatter line {i + 2} is not 'key: value': {line.strip()[:60]}")
                i += 1; continue
            j = i + 1
            while j < len(fm) and (fm[j][:1] in (" ", "\t") or not fm[j].strip()):
                j += 1
            cont = fm[i + 1:j]
            while cont and not cont[-1].strip():
                cont.pop()
            key = m.group(1)
            if key in fields:
                errors.append(f"frontmatter key '{key}' appears twice")
            fields[key] = scalar(key, m.group(2) or "", cont)
            i = j

name, desc = fields.get("name"), fields.get("description")
if not isinstance(name, str) or not name:
    errors.append("frontmatter has no name")
else:
    if name != folder:
        errors.append(f"folder name '{folder}' != frontmatter name '{name}' (claude.ai rejects the upload)")
    if not re.fullmatch(r"[a-z0-9-]{1,64}", name):
        errors.append(f"name '{name}' must be 1-64 chars of a-z, 0-9 and hyphens")
    if re.search(r"anthropic|claude", name, re.I):
        errors.append(f"name '{name}' must not contain 'anthropic' or 'claude'")
if not isinstance(desc, str) or not desc.strip():
    errors.append("frontmatter has no description")
else:
    if len(desc) > 1024:
        errors.append(f"description is {len(desc)} chars (max 1024)")
    elif len(desc) > 200:
        warns.append(f"description is {len(desc)} chars - the help center says 200 max; uploads have accepted more, so test it")
    if re.search(r"[<>]", desc):
        errors.append("description contains < or > (not allowed)")
extra = sorted(k for k in fields if k not in SAFE)
if extra:
    warns.append("fields outside the Agent Skills set (claude.ai may ignore them): " + ", ".join(extra))
if len(body) > 500:
    warns.append(f"SKILL.md body is {len(body)} lines (keep it under 500; move detail into references/)")

zip_path = os.path.join(out_dir, folder + ".zip")
for w in warns:
    print(f"WARN {folder}: {w}")
if errors:
    for e in errors:
        print(f"ERROR {folder}: {e}")
    if os.path.exists(zip_path):
        os.remove(zip_path)                                     # never leave a stale zip behind
    sys.exit(1)

tmp_path = zip_path + ".partial"
count = 0
try:
    with zipfile.ZipFile(tmp_path, "w", zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(src, followlinks=False):
            keep = []
            for d in sorted(dirs):
                p = os.path.join(root, d)
                if d in JUNK_DIRS:
                    continue
                if os.path.islink(p):
                    print(f"WARN {folder}: skipped symlinked folder {os.path.relpath(p, src)}")
                    continue
                keep.append(d)
            dirs[:] = keep
            for fn in sorted(files):
                p = os.path.join(root, fn)
                rel = os.path.relpath(p, src).replace(os.sep, "/")
                if fn in JUNK_FILES or fn.endswith(".pyc"):
                    continue
                if os.path.islink(p):
                    print(f"WARN {folder}: skipped symlink {rel}")
                    continue
                if is_secret(rel):
                    print(f"WARN {folder}: skipped secret-looking file {rel} (never uploaded)")
                    continue
                if is_git_ignored(p):
                    print(f"WARN {folder}: skipped git-ignored file {rel}")
                    continue
                if "\\" in rel:
                    raise ValueError(f"path contains a backslash: {rel}")
                z.write(p, f"{name}/{rel}")
                count += 1
    with zipfile.ZipFile(tmp_path) as z:
        if f"{name}/SKILL.md" not in z.namelist():
            raise ValueError(f"{name}/SKILL.md missing from the zip root")
    os.replace(tmp_path, zip_path)
except Exception as exc:                                        # noqa: BLE001 - report and fail this skill
    if os.path.exists(tmp_path):
        os.remove(tmp_path)
    print(f"ERROR {folder}: zipping failed - {exc}")
    sys.exit(1)

kb = max(1, round(os.path.getsize(zip_path) / 1024))
print(f"OK {name} -> dist/claude-ai/{name}.zip ({count} files, {kb} KB, description {len(desc)} chars)")
PY

# Resolve an argument to an absolute skill folder: a path (from cwd or repo root) or a bare skill name.
# Returns 0 + prints the path, 1 = not found, 3 = bare name found in several plugins.
resolve_skill() {
  local a="${1%/}" d n=0 found=""
  if [ -d "$a" ]; then (cd "$a" && pwd); return 0; fi
  if [ -d "$repo_root/$a" ]; then (cd "$repo_root/$a" && pwd); return 0; fi
  case "$a" in */*|"") return 1 ;; esac
  for d in "$repo_root"/plugins/*/skills/"$a"; do
    [ -d "$d" ] || continue
    n=$((n + 1)); found="$d"
  done
  [ "$n" -eq 1 ] && { printf '%s\n' "$found"; return 0; }
  [ "$n" -gt 1 ] && return 3
  return 1
}

if [ "$#" -gt 0 ]; then skills=("$@"); else skills=("${default_skills[@]}"); fi
mkdir -p "$out_dir" || { echo "ERROR cannot create $out_dir" >&2; exit 2; }

packaged=0; failed=0; skipped=0; warned=0
for s in "${skills[@]}"; do
  dir="$(resolve_skill "$s")"; rc=$?
  if [ "$rc" -eq 3 ]; then
    echo "WARN $s: several plugins ship a skill with this name - pass its folder path instead; skipped"
    skipped=$((skipped + 1)); continue
  fi
  if [ "$rc" -ne 0 ] || [ -z "$dir" ]; then
    echo "WARN $s: skill folder not found - skipped"
    skipped=$((skipped + 1)); continue
  fi
  result="$(python3 -c "$PACKAGER" "$dir" "$out_dir" 2>&1)"; rc=$?
  [ -n "$result" ] && printf '%s\n' "$result"
  warned=$((warned + $(printf '%s\n' "$result" | grep -c '^WARN')))
  if [ "$rc" -eq 0 ]; then packaged=$((packaged + 1)); else failed=$((failed + 1)); fi
done

echo
echo "Summary: $packaged packaged, $failed failed, $skipped skipped, $warned warnings -> dist/claude-ai/"
echo
echo "Upload: claude.ai > Settings > Capabilities (code execution on), then Customize > Skills > + > Create skill > Upload a skill, one zip at a time."
echo "Reminder: don't upload a skill that an installed account plugin already provides (base, marketing, council) - it would be listed twice."
echo "Upload only for surfaces plugins don't reach: mobile, the API, cloud Code sessions. Uploaded skills also sync into signed-in"
echo "local Claude Code as anthropic-skills:<name>; check /skills (claude.ai sync group) and /context for duplicates."

[ "$failed" -eq 0 ] && [ "$packaged" -gt 0 ] && exit 0
exit 1
