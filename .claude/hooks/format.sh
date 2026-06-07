#!/usr/bin/env bash
# format.sh - OPTIONAL PostToolUse hook (Linux/macOS): format the just-edited file
# using ONLY a formatter already present in the project (no installs, no network).
# Best-effort and silent; always exits 0. Needs jq. Register on matcher "Edit|Write".

input="$(cat 2>/dev/null || true)"
[ -z "$input" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
if [ -z "$path" ] || [ ! -f "$path" ]; then exit 0; fi
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[ -z "$cwd" ] && cwd="$(pwd)"

case "$path" in
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.json|*.css|*.scss|*.less|*.md|*.mdx|*.html|*.yml|*.yaml|*.vue|*.svelte)
    if [ -x "$cwd/node_modules/.bin/prettier" ]; then "$cwd/node_modules/.bin/prettier" --write --log-level warn -- "$path" >/dev/null 2>&1; fi ;;
  *.php)
    if [ -x "$cwd/vendor/bin/pint" ]; then "$cwd/vendor/bin/pint" "$path" >/dev/null 2>&1; fi ;;
  *.py)
    if command -v ruff >/dev/null 2>&1; then ruff format "$path" >/dev/null 2>&1
    elif command -v black >/dev/null 2>&1; then black -q "$path" >/dev/null 2>&1; fi ;;
  *.go)  command -v gofmt   >/dev/null 2>&1 && gofmt -w "$path"  >/dev/null 2>&1 ;;
  *.rs)  command -v rustfmt >/dev/null 2>&1 && rustfmt "$path"   >/dev/null 2>&1 ;;
esac
exit 0
