#!/usr/bin/env bash
# guard.sh - OPTIONAL PreToolUse guard for Claude Code (Linux / macOS, bash + jq).
#
# Port of guard.ps1. Adds *mechanical* enforcement on top of the settings.json deny-list,
# which only covers the Read tool and is bypassable from a shell:
#   * Bash: PROMPTS on network-egress commands; BLOCKS shell reads/copies of protected
#           secret paths (the Read deny-list cannot see shell reads - this guard can).
#   * Write/Edit of a generated "<framework>-expert.md" agent file: BLOCKS over-privileged
#           tools (anything beyond Read/Write/Edit/Grep/Glob), BLOCKS writes outside the
#           workspace, and PROMPTS if the Guardrails section is missing.
#
# Reads the hook JSON from stdin; prints a permission decision as JSON on stdout.
# ANY unexpected condition exits 0 (defer to the normal permission flow) so it can never
# wedge a session. Requires jq:  sudo apt-get install -y jq
# It deliberately does NOT touch the curated agents - only files ending "-expert.md".

input="$(cat 2>/dev/null || true)"
[ -z "$input" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0   # no jq -> defer

decide() { # $1=decision  $2=reason
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"

if [ "$tool" = "Bash" ]; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
  [ -z "$cmd" ] && exit 0
  lc="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')"

  for p in 'curl' 'wget' 'invoke-webrequest' '\biwr\b' 'invoke-restmethod' '\birm\b' 'bitsadmin' 'ncat' 'telnet' '\bnc\b' '\bscp\b' '\bsftp\b' '\bftp\b'; do
    if printf '%s' "$lc" | grep -Eq "$p"; then
      decide "ask" "Possible network egress detected - confirm this does not move data off the machine."
    fi
  done

  readers='get-content|\bgc\b|\bcat\b|\btype\b|\bsls\b|select-string|\bmore\b|\bhead\b|\btail\b|\bcp\b|\bmv\b'
  if printf '%s' "$lc" | grep -Eq "$readers"; then
    for s in '\.env\b' '\.envrc' '\.ssh' '\.aws' '\.azure' 'gcloud' 'secrets/' '\.git-credentials' '\.pgpass' '\.my\.cnf' '\.tfstate' '\.tfvars' 'id_rsa' 'id_ed25519' '\.pem\b' '\.pfx\b' '\.p12\b' '\.key\b'; do
      if printf '%s' "$lc" | grep -Eq "$s"; then
        decide "deny" "Blocked: shell read/copy of a protected secret path. The Read deny-list does not cover shell reads - this guard does."
      fi
    done
  fi
  exit 0
fi

if [ "$tool" = "Write" ] || [ "$tool" = "Edit" ]; then
  path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
  case "$path" in
    *.claude/agents/*-expert.md) : ;;   # only police generated specialists
    *) exit 0 ;;
  esac

  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
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
    content="$(printf '%s' "$input" | jq -r '.tool_input.content // empty')"
  else
    content="$(printf '%s' "$input" | jq -r '.tool_input.new_string // empty')"
  fi

  if [ -n "$content" ]; then
    tools_line="$(printf '%s\n' "$content" | grep -m1 -E '^[[:space:]]*tools[[:space:]]*:')"
    if [ -n "$tools_line" ]; then
      decl="$(printf '%s' "$tools_line" | sed -E 's/^[[:space:]]*tools[[:space:]]*:[[:space:]]*//')"
      bad=""
      old_ifs="$IFS"; IFS=','
      for t in $decl; do
        t="$(printf '%s' "$t" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
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
