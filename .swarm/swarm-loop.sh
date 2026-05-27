#!/usr/bin/env bash
# Long-running loop that keeps a single non-Claude worker busy.
#
# Picks an unclaimed loom:issue, runs spawn-non-claude-worker.sh, then
# waits a polite interval and picks the next. Designed to be launched
# inside a `tmux -L swarm` session so it survives this session ending.
#
# Usage:
#   tmux -L swarm new-session -d -s codex-1 -c /Users/jperla/claude/QuillUI '.swarm/swarm-loop.sh codex'
#   tmux -L swarm new-session -d -s gemini-1 -c /Users/jperla/claude/QuillUI '.swarm/swarm-loop.sh gemini'

set -euo pipefail

ENGINE="${1:-}"
if [[ "$ENGINE" != "codex" && "$ENGINE" != "gemini" ]]; then
  echo "Usage: $0 codex|gemini" >&2
  exit 64
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ITERATION=0
while true; do
  ITERATION=$((ITERATION + 1))
  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "[$ENGINE swarm] Iteration $ITERATION at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "════════════════════════════════════════════════════════"

  if [[ -f "$REPO_ROOT/.swarm/stop-$ENGINE" ]]; then
    echo "[$ENGINE swarm] Stop signal detected. Exiting."
    rm -f "$REPO_ROOT/.swarm/stop-$ENGINE"
    exit 0
  fi

  # Run one worker iteration; tolerate failures (network blip, etc.)
  ./.swarm/spawn-non-claude-worker.sh "$ENGINE" || \
    echo "[$ENGINE swarm] Iteration $ITERATION failed (continuing)"

  # Polite pause so we don't hammer GitHub if there are no issues.
  sleep 30
done
