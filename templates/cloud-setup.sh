#!/bin/bash
# claude-md -> every Claude Code cloud session (claude.ai/code on the web, the Claude app on your phone,
# Desktop's cloud environment, `claude --cloud`). Paste this whole file into the cloud environment's
# Setup script: open a cloud session, click the environment menu in the session's title bar -> Edit ->
# Setup script. Every NEW session in that environment then starts with the claude-md user layer in its
# container's ~/.claude: the security baseline (deny + ask rules, bypass disabled; no Plan default, so
# phone sessions and routines don't stall), the global working agreement (CLAUDE.md) and the base pack
# as a plugin (agents, skills, /spec, /implement-plan, the SessionStart rule), the model pins (Opus 5.5,
# Sonnet 5, Haiku 4.5) and the review-gate hook (no commit until the diff has been reviewed). A session you continue on
# your phone is the same container, so it keeps all of it. Sessions that were already running when you
# saved the script don't change - start a new one.
#
# Replace <owner> with the GitHub owner of your claude-md repo. The repo must be public (this script
# runs before any GitHub credentials exist in the container) and the environment's network access must
# allow github.com (the default Trusted level does). It installs from the reviewed main branch - protect
# main on GitHub (require a PR), because whatever lands there runs in every new cloud session.
# More packs: change --packs base to e.g. --packs base,council (marketing also needs its API keys as
# environment secrets; avoid ecc here - about 15k tokens in every session).
# A failure never blocks the session: it prints why and the session starts without the packs.

CLAUDE_MD_REPO="https://github.com/<owner>/claude-md.git"
CLAUDE_MD_REF="main"
CLAUDE_MD_SRC="$HOME/.claude-md-src"   # kept for the session: the base plugin loads from this clone

if [ -d "$CLAUDE_MD_SRC" ]; then rm -r "$CLAUDE_MD_SRC"; fi
# A stalled connection must not hang the session start: abort below 1 KB/s for 30 s, and after 3 minutes overall.
CLAUDE_MD_TIMEOUT=""; command -v timeout >/dev/null 2>&1 && CLAUDE_MD_TIMEOUT="timeout 180"
if GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=30 $CLAUDE_MD_TIMEOUT git clone -q --depth 1 --branch "$CLAUDE_MD_REF" "$CLAUDE_MD_REPO" "$CLAUDE_MD_SRC"; then
  bash "$CLAUDE_MD_SRC/scripts/install-user-config.sh" --cloud --packs base --hooks review-gate \
    || echo "claude-md: install finished with errors (see the ERROR lines above)"
else
  echo "claude-md: could not clone $CLAUDE_MD_REPO ($CLAUDE_MD_REF) - check the repo is public and github.com is allowed; the session starts without the packs"
fi
exit 0
