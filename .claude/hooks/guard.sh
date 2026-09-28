#!/usr/bin/env bash
# guard.sh - OPTIONAL PreToolUse guard for Claude Code (Linux / macOS, bash + jq).
#
# Port of guard.ps1 - keep the two in sync. Adds *mechanical* enforcement on top of the
# settings.json deny-list. Read/Edit deny rules now also cover the shell readers Claude Code
# recognises (cat/head/tail/sed/tee and < > redirect targets), but NOT grep -r, interpreters
# (python/node/...), npx, sh -c, or paths outside a rule's anchor (a **/ rule starts at the
# working directory, so home dirs need ~/ rules). Bash(curl:*)-style denies miss /usr/bin/curl,
# sh -c and interpreter one-liners. This guard adds those:
#   * Shell tools - Bash, PowerShell (a separate tool on Windows) and Monitor (command, or ws url):
#       - BLOCKS reads/copies of protected secret paths (same list as the settings.json
#         deny-list, incl. ~/.aws, ~/.config/gh, ~/.claude/.credentials.json, .kube, .docker)
#         by shell readers AND interpreters (python, node, deno, bun, perl, ruby, php, pwsh,
#         bash -c / sh -c, source, rg, jq, npx ...);
#       - PROMPTS on shell commands that overwrite, move or delete a fix-once file
#         (REGRESSIONS.md, .claude/guards.*, .claude/checks.*, banned-phrases.txt);
#         appends (>>, tee -a, Add-Content) to the ledger or banned list pass;
#         an interpreter (python, node, ruby, perl, pwsh ...), sort -o, awk -i inplace or
#         ruby -i in the same command segment as such a file counts as a change (running a
#         guard runner, e.g. pwsh -File .claude/guards.ps1, does not);
#       - PROMPTS on whole-tree git reverts (git checkout/restore -- ., git reset --hard,
#         git checkout -f) when the repo root has a REGRESSIONS.md, and on any command that
#         sets or passes ALLOW_GUARD_CHANGE / GUARD_BASE_REF (they bypass or re-base the
#         ledger's append-only check);
#       - PROMPTS on network egress: curl/wget by any path, Invoke-WebRequest/RestMethod,
#         Start-BitsTransfer, bitsadmin, certutil -urlcache, WebClient, nc/ssh/scp/rsync/...,
#         an interpreter given a non-localhost URL, and a Monitor WebSocket source.
#   * Write/Edit of fix-once files (regression-guard skill):
#       - REGRESSIONS.md: PROMPTS only if an existing R-### row would disappear or change
#         (pure appends pass silently);
#       - .claude/guards.* and .claude/checks.* (not the .log): always PROMPTS;
#       - brand/banned-phrases.txt: PROMPTS if a non-comment line would be removed or changed.
#   * Write/Edit of a generated "<framework>-expert.md" agent file: BLOCKS over-privileged
#           tools (anything beyond Read/Write/Edit/Grep/Glob), BLOCKS writes outside the
#           workspace, and PROMPTS if the Guardrails section is missing.
#
# Register with matcher "Bash|PowerShell|Monitor|Write|Edit" (see settings.hooks.example.json).
# Reads the hook JSON from stdin; prints a permission decision as JSON on stdout.
# It matches command text, so it is a speed bump, not a sandbox.
# ANY unexpected condition exits 0 (defer to the normal permission flow) so it can never
# wedge a session. Requires jq:  sudo apt-get install -y jq
# It deliberately does NOT touch the curated agents - only files ending "-expert.md".
set -u

input="$(cat 2>/dev/null || true)"
[ -z "$input" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0   # no jq -> defer
shopt -u patsub_replacement 2>/dev/null || true   # bash 5.2: keep '&' literal in ${x/a/b}
# Runs on macOS stock bash 3.2 too: no ${x/"a"/"b"} with a quoted replacement (bash <= 4.2 keeps
# the quotes) and no $'..' inside "${..}" - plain variables below instead.
nl=$'\n'; cr=$'\r'

decide() { # $1=decision  $2=reason
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}
field() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null || true; }
raw_field() { # $1=var name  $2=jq path; keeps trailing newlines, drops CR
  local v
  v="$(printf '%s' "$input" | jq -r "(($2) // \"\" | tostring) + \"#\"" 2>/dev/null)" || v="#"
  v="${v%#}"
  printf -v "$1" '%s' "${v//$cr/}"
}
has() { printf '%s' "$1" | grep -Eq -- "$2"; }   # $1=text $2=ERE

tool="$(field '.tool_name')"
cwd="$(field '.cwd')"

# --- pattern lists (lower-case ERE; guard.ps1 holds the same lists in .NET syntax) ---------
# Commands that can read or copy a file's content: shell readers + interpreters.
readers='get-content|\bgc\b|\bcat\b|\btype\b|\bsls\b|select-string|\bmore\b|\bless\b|\bhead\b|\btail\b|\bnl\b|\bcut\b|\bgrep\b|\begrep\b|\bsed\b|\bawk\b|\bbase64\b|\bxxd\b|\bod\b|\bstrings\b|\bdd\b|\btar\b|\brsync\b|format-hex|copy-item|\bcp\b|move-item|\bmv\b|out-file|set-content'
readers="$readers"'|\brg\b|\bfindstr\b|\bjq\b|\byq\b|\bzip\b|\b7z\b|\bgpg\b|\bcertutil\b|\bxcopy\b|\brobocopy\b|readall(text|bytes|lines)'
# Line-preserving text tools and editors dump a file's content too (sort ~/.env prints it whole).
readers="$readers"'|\bsort\b|\buniq\b|\btac\b|\brev\b|\bcolumn\b|\bpaste\b|\bjoin\b|\bfold\b|\bexpand\b|\bunexpand\b|\bfmt\b|\bpr\b|\bcomm\b|\bdiff\b|\bsdiff\b|\bcmp\b|\btr\b|\biconv\b|\bsplit\b|\bcsplit\b|\blook\b|\bhexdump\b|\bhd\b|\bzcat\b|\bgzip\b|\bbzip2\b|\bxz\b|\bzstd\b|\bopenssl\b|\btee\b|\bed\b|\bex\b|\bvi\b|\bvim\b|\bnano\b|\bemacs\b'
interp='\bpython[0-9.]*\b|\bnode\b|\bdeno\b|\bbunx?\b|\bnpx\b|\bperl\b|\bruby\b|\bphp\b|\bpwsh\b|powershell|\b(ba|z|da|k)?sh[[:space:]]+-[a-z]*c\b'
readers="$readers|$interp"'|\bsource\b|(^|[;&|({])[[:space:]]*\.[[:space:]]+[^[:space:]]'
# Protected secret paths (mirrors the settings.json Read deny-list, incl. home-dir credentials).
secrets='\.env\b|\.envrc|\.ssh|\.aws|\.azure|gcloud|secrets[/\\]|\.git-credentials|\.pgpass|\.my\.cnf|\.tfstate|\.tfvars|id_rsa|id_ed25519|\.pem\b|\.pfx\b|\.p12\b|\.key\b'
secrets="$secrets"'|\.netrc|\.npmrc|\.pypirc|\.gnupg|\.kube|\.docker\b|\.config[/\\]gh\b|\.credentials\.json|\.keystore\b|\.jks\b|\.ppk\b|id_ecdsa|id_dsa|_rsa\b|_ed25519\b|_ecdsa\b|_dsa\b|gha-creds-[^[:space:]]*\.json|service-account[^[:space:]]*\.json|[/\\]credentials(\.[a-z0-9]+)?([^a-z0-9_./-]|$)'
# Network egress (substring match on curl/wget also catches /usr/bin/curl and curl.exe).
egress='curl|wget|invoke-webrequest|\biwr\b|invoke-restmethod|\birm\b|bitsadmin|ncat|telnet|\bnc\b|\bscp\b|\bsftp\b|\bftp\b|\bssh\b|\brsync\b'
egress="$egress"'|start-bitstransfer|certutil.*(urlcache|verifyctl)|net\.webclient|downloadstring|downloadfile'
# Fix-once files and the shell verbs that overwrite, move or delete them.
fixonce='regressions\.md|\.claude[/\\](guards|checks)\.(sh|ps1|cmd|bat)\b|banned-phrases\.txt'
mutate='\bsed\b.*[[:space:]](-[a-z]*i|--in-place)|\bperl\b.*[[:space:]]-[a-z]*i|\b(rm|mv|cp|truncate|unlink|shred|ln|chmod|dd|install)\b|\bgit[[:space:]]+(checkout|restore|rm|mv)\b'
mutate="$mutate"'|set-content|\bsc\b|remove-item|\bri\b|\bdel\b|\berase\b|move-item|\bmi\b|\bmove\b|rename-item|\bren\b|copy-item|\bcpi\b|\bcopy\b|clear-content|\bclc\b|new-item|\bni\b|writeall(text|bytes|lines)'
# In-place rewriters that name the file as an option value: sort -o, (g)awk -i inplace, ruby -i.
mutate="$mutate|\\bsort\\b.*[[:space:]](-[a-z]*o[[:space:]]*|--output[=[:space:]]+)[\"']?[^[:space:]\"']*($fixonce)"
mutate="$mutate"'|\bg?awk\b.*[[:space:]](-i|--include)[=[:space:]]*["'\'']?inplace\b|\bruby\b.*[[:space:]]-[a-z]*i'
redirect="(^|[^>])>[|]?[[:space:]]*[\"']?[^[:space:]>]*($fixonce)"
runner='\.claude[/\\](guards|checks)\.(sh|ps1|cmd|bat)\b'   # appending to these can switch a guard off
# Running a guard runner (pwsh -File <runner>, bash <runner>, & <runner>) is not an interpreter edit.
runexec="((pwsh|powershell)(\\.exe)?([[:space:]].*)?[[:space:]]-f(ile)?|(^|[^a-z0-9_-])(ba|z|da|k)?sh|&)[[:space:]]+[\"']?[^[:space:]\"']*($runner)"
# Env switches of the ledger's append-only check (guards.sh / guards.ps1 / CI).
bypass='allow_guard_change|guard_base_ref'
# git commands that revert the whole tree (or .claude/ or brand/) - they never name the ledger.
revert='\bgit\b.*[[:space:]](checkout|restore)\b.*[[:space:]]["'\'']?(\.|\.[/\\]|\.[/\\]\*[^[:space:]]*|\*[^[:space:]]*|:[^[:space:]]*|\.claude[/\\]?|brand[/\\]?)["'\'']?([[:space:]]|$)'
revert="$revert"'|\bgit\b.*[[:space:]]reset\b.*[[:space:]]--hard\b|\bgit\b.*[[:space:]](checkout|switch)\b.*[[:space:]](-f|--force|--discard-changes)([[:space:]]|$)'

case "$tool" in
Bash|PowerShell|Monitor)
  cmd="$(field '.tool_input.command')"
  if [ -z "$cmd" ]; then
    ws="$(field '.tool_input.ws.url')"   # Monitor can stream a WebSocket instead of a command
    [ -n "$ws" ] && decide "ask" "Monitor opens a network connection ($ws) - confirm this does not move data off the machine."
    exit 0
  fi
  lc="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')"

  # 1. Secret read/copy -> deny. Code idioms like process.env / import.meta.env are not .env
  #    files, so they are neutralised before the secret match (a real .env path still matches).
  lcs="$(printf '%s' "$lc" | sed -E 's/(process|import\.meta|deno|bun)\.env([^a-z0-9_]|$)/\1_envref\2/g')"
  if has "$lc" "$readers" && has "$lcs" "$secrets"; then
    decide "deny" "Blocked: shell or interpreter read/copy of a protected secret path. The Read deny-list covers only some shell readers and paths - this guard covers the rest."
  fi

  # 2. Fix-once files overwritten/moved/deleted from the shell -> ask (checked per command
  #    segment split on ; && || and newlines; appends to the ledger or banned list pass).
  if has "$lc" "$bypass"; then
    decide "ask" "This command sets or passes ALLOW_GUARD_CHANGE / GUARD_BASE_REF: this bypasses or re-bases the fix-once ledger check - needs the owner's explicit OK."
  fi
  segs="${lc//"&&"/$nl}"; segs="${segs//"||"/$nl}"; segs="${segs//";"/$nl}"
  if has "$lc" "$revert"; then   # whole-tree revert: can drop uncommitted ledger rows / guard edits
    top="${cwd:-$PWD}"
    [ -f "$top/REGRESSIONS.md" ] || top="$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null)"
    if [ -n "$top" ] && [ -f "$top/REGRESSIONS.md" ]; then
      while IFS= read -r seg; do
        has "$seg" "$revert" || continue
        # 'git restore --staged <paths>' only unstages: the working tree is untouched.
        if has "$seg" '\brestore\b.*[[:space:]]--staged\b' && ! has "$seg" '[[:space:]](--worktree|-w)\b|\b(checkout|reset|switch)\b'; then continue; fi
        decide "ask" "This git command reverts the whole working tree (or .claude/, brand/) in a repo with a REGRESSIONS.md - it can silently drop uncommitted ledger rows, banned phrases or guard changes. Guards are never weakened without the owner's explicit OK - confirm."
      done <<< "$segs"
    fi
  fi
  if has "$lc" "$fixonce"; then
    while IFS= read -r seg; do
      has "$seg" "$fixonce" || continue
      hit=0
      has "$seg" "$mutate" && hit=1
      has "$seg" "$redirect" && hit=1
      if has "$seg" "$interp"; then     # an interpreter can rewrite any file it names
        n_all="$(printf '%s\n' "$seg" | grep -Eo -- "$fixonce" | wc -l)"
        n_run="$(printf '%s\n' "$seg" | grep -Eo -- "$runexec" | wc -l)"
        [ "$((n_run + 0))" -lt "$((n_all + 0))" ] && hit=1   # unless it only runs a guard runner
      fi
      if has "$seg" "(^|[^a-z0-9_-])tee[[:space:]][^|]*($fixonce)" && ! has "$seg" 'tee[[:space:]]+(-a|--append)'; then hit=1; fi
      if has "$seg" 'out-file' && ! has "$seg" '-append'; then hit=1; fi
      if has "$seg" "$runner"; then                 # runners: appends count as edits too
        has "$seg" ">>[[:space:]]*[\"']?[^[:space:]>]*($runner)" && hit=1
        has "$seg" "(^|[^a-z0-9_-])tee[[:space:]][^|]*($runner)" && hit=1
        has "$seg" 'add-content|\bac\b|out-file' && hit=1
      fi
      [ "$hit" -eq 1 ] && decide "ask" "This command may change, move or delete a fix-once file (REGRESSIONS.md, .claude/guards.*, .claude/checks.*, banned-phrases.txt). Guards are never weakened without the owner's explicit OK - confirm. Appends to REGRESSIONS.md or banned-phrases.txt (>>, tee -a, Add-Content) pass without asking."
    done <<< "$segs"
  fi

  # 3. Network egress -> ask.
  if has "$lc" "$egress"; then
    decide "ask" "Possible network egress detected - confirm this does not move data off the machine."
  fi
  if has "$lc" "$interp"; then
    hosts="$(printf '%s' "$lc" | grep -Eo "(https?|ftps?|wss?)://[^/[:space:]?#\"'<>]+" | sed -E 's#^[a-z]+://([^@]*@)?##')"
    if printf '%s\n' "$hosts" | grep -Evq '^$|^(localhost|127\.[0-9.]+|0\.0\.0\.0|\[::1\])(:[0-9]+)?$'; then
      decide "ask" "Interpreter command with a network URL - possible egress that the curl/wget deny rules do not see. Confirm this does not move data off the machine."
    fi
  fi
  exit 0
  ;;
esac

if [ "$tool" = "Write" ] || [ "$tool" = "Edit" ]; then
  path="$(field '.tool_input.file_path')"
  [ -z "$path" ] && exit 0

  # --- Fix-once files -----------------------------------------------------------------------
  lp="/$(printf '%s' "$path" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')"
  kind=""
  case "$lp" in
    */regressions.md) kind="ledger" ;;
    */.claude/guards.log|*/.claude/checks.log) : ;;
    */.claude/guards.*|*/.claude/checks.*)
      decide "ask" "Editing a guard runner or checks wrapper ($path). Guards are never weakened without the owner's explicit OK - confirm this change keeps every guard at least as strict." ;;
    */brand/banned-phrases.txt) kind="phrases" ;;
  esac
  if [ -n "$kind" ]; then
    abs="$path"
    case "$abs" in /*|[A-Za-z]:*) : ;; *) abs="${cwd:-.}/$path" ;; esac
    before=""
    if [ -f "$abs" ]; then before="$(tr -d '\r' < "$abs" 2>/dev/null; printf '#')"; before="${before%#}"; fi
    after=""
    if [ "$tool" = "Write" ]; then
      raw_field after '.tool_input.content'
    else
      raw_field old '.tool_input.old_string'
      raw_field new '.tool_input.new_string'
      if [ -n "$old" ] && [[ "$before" == *"$old"* ]]; then   # replay the edit on the file
        # Literal split at the first match (not ${before/"$old"/"$new"}: bash <= 4.2, e.g. macOS
        # /bin/bash 3.2, keeps the quotes of "$new" there, so every pure append looked like a rewrite).
        if [ "$(field '.tool_input.replace_all')" = "true" ]; then
          rest="$before"; after=""
          while [[ "$rest" == *"$old"* ]]; do
            after="$after${rest%%"$old"*}$new"; rest="${rest#*"$old"}"
          done
          after="$after$rest"
        else
          after="${before%%"$old"*}$new${before#*"$old"}"
        fi
      else                                                     # can't place it: compare the snippets
        before="$old"; after="$new"
      fi
    fi
    if [ "$kind" = "ledger" ]; then filter='^[[:space:]]*\|[[:space:]]*R-[0-9]+'; else filter='^[[:space:]]*[^#[:space:]]'; fi
    rows="$(printf '%s\n' "$before" | grep -E -- "$filter")"
    if [ -n "$rows" ]; then
      gone="$(printf '%s\n' "$rows" | grep -Fxv -f <(printf '%s\n' "$after"))"
      if [ -n "$gone" ]; then
        if [ "$kind" = "ledger" ]; then
          ids="$(printf '%s\n' "$gone" | grep -Eo 'R-[0-9]+' | head -n 5 | tr '\n' ' ')"
          decide "ask" "This edit removes or changes existing REGRESSIONS.md row(s): ${ids}- rows are never deleted or rewritten without the owner's explicit OK (retire with 'retired:'). Pure appends pass without asking."
        else
          first="$(printf '%s\n' "$gone" | head -n 3 | tr '\n' ';')"
          decide "ask" "This edit removes or changes banned phrase line(s) in brand/banned-phrases.txt ($first). Banned phrases are never removed without the owner's explicit OK."
        fi
      fi
    fi
    exit 0
  fi

  # --- Generated specialists (unchanged policy) -------------------------------------------
  case "$path" in
    *.claude/agents/*-expert.md) : ;;   # only police generated specialists
    *) exit 0 ;;
  esac

  case "$path" in
    /*)
      if [ -n "$cwd" ]; then
        case "$path" in
          "$cwd"*) : ;;
          *) decide "deny" "Blocked: refusing to write a generated agent outside the project workspace ($path)." ;;
        esac
      fi
      ;;
  esac

  if [ "$tool" = "Write" ]; then
    content="$(field '.tool_input.content')"
  else
    content="$(field '.tool_input.new_string')"
  fi

  if [ -n "$content" ]; then
    tools_line="$(printf '%s\n' "$content" | grep -m1 -Ei '^[[:space:]]*tools[[:space:]]*:')"
    if [ -z "$tools_line" ]; then
      # A whole agent file with no tools: line inherits every tool (incl. Bash) - not allowed here.
      [ "$tool" = "Write" ] && decide "deny" "Blocked: generated agent has no tools: line, so it would inherit every tool (incl. Bash). Declare tools: with only Read/Write/Edit/Grep/Glob."
    else
      decl="$(printf '%s' "$tools_line" | sed -E 's/^[[:space:]]*[Tt][Oo][Oo][Ll][Ss][[:space:]]*:[[:space:]]*//')"
      if [ -z "$(printf '%s' "$decl" | tr -d '[:space:]')" ]; then
        decide "ask" "Generated agent declares tools: as a multi-line list - put it on one line (Read, Write, Edit, Grep, Glob) so it can be checked, or review the file before enabling it."
      fi
      bad=""
      old_ifs="$IFS"; IFS=','
      for t in $decl; do
        t="$(printf '%s' "$t" | tr -d "\"'[:space:]" | sed 's/[][]//g')"   # also accepts [Read, Grep] / "Read"
        [ -z "$t" ] && continue
        case "$t" in
          Read|Write|Edit|Grep|Glob) : ;;
          *) bad="$bad $t" ;;
        esac
      done
      IFS="$old_ifs"
      if [ -n "$bad" ]; then
        decide "deny" "Blocked: generated agent requests disallowed tool(s):$bad. Generated specialists may use only Read/Write/Edit/Grep/Glob."
      fi
    fi
    if ! printf '%s' "$content" | grep -Eiq '^[[:space:]]*##[[:space:]]*Guardrails'; then
      decide "ask" "Generated agent is missing a Guardrails section - review the file before enabling it."
    fi
  fi
  exit 0
fi

exit 0
