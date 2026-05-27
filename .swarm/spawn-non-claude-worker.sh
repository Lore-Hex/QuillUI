#!/usr/bin/env bash
# Spawn a single non-Claude (Codex or Gemini) worker for one issue.
#
# Usage:
#   spawn-non-claude-worker.sh codex
#   spawn-non-claude-worker.sh gemini
#
# Behavior:
#   1. Picks the oldest unclaimed `loom:issue` ticket that is NOT also
#      labeled `loom:building`, `codex:claimed`, or `gemini:claimed`.
#   2. Adds `<engine>:claimed` to mark the issue ours.
#   3. Creates a git worktree at .swarm/worktrees/issue-N.
#   4. Runs the engine non-interactively with the issue body as prompt.
#   5. Commits anything left in the worktree, pushes a branch, opens a
#      PR labeled `loom:review-requested` so loom's Judge picks it up.
#
# Intended to be run inside a tmux session via the spawn-swarm.sh
# orchestrator. Exits 0 on success, non-zero on failure (caller decides
# whether to retry or move on).

set -euo pipefail

ENGINE="${1:-}"
if [[ "$ENGINE" != "codex" && "$ENGINE" != "gemini" ]]; then
  echo "Usage: $0 codex|gemini" >&2
  exit 64
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Pick an unclaimed loom:issue (filter out any already claimed by anyone)
ISSUE_JSON=$(gh issue list --repo Lore-Hex/QuillUI \
  --label "loom:issue" --state open \
  --json number,title,body,labels --limit 30)

ISSUE_NUMBER=$(echo "$ISSUE_JSON" | python3 -c "
import json, sys
issues = json.load(sys.stdin)
for issue in sorted(issues, key=lambda x: x['number']):
    labels = [l['name'] for l in issue['labels']]
    if any(l in labels for l in ('loom:building', 'codex:claimed', 'gemini:claimed', 'loom:curating', 'loom:treating', 'loom:reviewing')):
        continue
    print(issue['number'])
    break
")

if [[ -z "$ISSUE_NUMBER" ]]; then
  echo "[$ENGINE] No unclaimed issues. Exiting." >&2
  exit 0
fi

echo "[$ENGINE] Claiming issue #$ISSUE_NUMBER..."
gh issue edit "$ISSUE_NUMBER" --repo Lore-Hex/QuillUI --add-label "$ENGINE:claimed" >/dev/null

# Pull issue body fresh (post-claim, in case curator updated it)
ISSUE_TITLE=$(gh issue view "$ISSUE_NUMBER" --repo Lore-Hex/QuillUI --json title --jq '.title')
ISSUE_BODY=$(gh issue view "$ISSUE_NUMBER" --repo Lore-Hex/QuillUI --json body --jq '.body')

# Create a worktree
BRANCH="$ENGINE/issue-$ISSUE_NUMBER"
WORKTREE=".swarm/worktrees/$ENGINE-issue-$ISSUE_NUMBER"
mkdir -p .swarm/worktrees
# Clean up stale worktree if present
if [[ -d "$WORKTREE" ]]; then
  git worktree remove --force "$WORKTREE" 2>/dev/null || rm -rf "$WORKTREE"
fi
git fetch origin main >/dev/null 2>&1 || true
git worktree add -b "$BRANCH" "$WORKTREE" origin/main

echo "[$ENGINE] Worktree at $WORKTREE on branch $BRANCH"

# Construct the prompt
PROMPT_FILE="$WORKTREE/.swarm-prompt.txt"
cat > "$PROMPT_FILE" <<PROMPT
You are an autonomous coding agent implementing GitHub issue #$ISSUE_NUMBER for the Lore-Hex/QuillUI repository.

Your working directory IS a fresh git worktree at this path. Implement the issue's acceptance criteria. When you're done, commit your work to the current branch ($BRANCH). Do NOT push or open a PR — the spawn wrapper will handle that.

Constraints:
- This is a Swift package (Package.swift at the repo root). Use the existing target structure.
- Do not modify Package.swift's existing target list unless the issue explicitly requires a new target.
- Do not touch other targets unless the issue scope requires it.
- The strict Mac-reference verifier targets pixel-perfect macOS appearance via the QuillPaint stack. Don't propose Adwaita or native-Linux feel.
- Write tests when the issue asks for them. Use Swift Testing (\`import Testing\`) and \`@Test\` / \`@Suite\` macros.
- Commit early, commit often. Multiple small commits are better than one big one.
- Final commit message should reference the issue: "Closes #$ISSUE_NUMBER"

ISSUE TITLE: $ISSUE_TITLE

ISSUE BODY:
$ISSUE_BODY

Begin.
PROMPT

cd "$WORKTREE"

# Run the engine
echo "[$ENGINE] Running $ENGINE on issue #$ISSUE_NUMBER..."
case "$ENGINE" in
  codex)
    # Non-interactive Codex with workspace-write sandbox
    codex exec --sandbox workspace-write --skip-git-repo-check "$(cat .swarm-prompt.txt)" \
      2>&1 | tee .swarm-run.log
    ;;
  gemini)
    # Non-interactive Gemini in yolo mode
    gemini --yolo --output-format text -p "$(cat .swarm-prompt.txt)" \
      2>&1 | tee .swarm-run.log
    ;;
esac

# After the agent exits: commit any uncommitted changes (in case the agent
# left some), then push and open PR.
git add -A .
if ! git diff --cached --quiet; then
  git commit -m "$ENGINE: WIP for #$ISSUE_NUMBER (auto-commit by spawn wrapper)" \
    --author "$ENGINE swarm <swarm@quill.local>" 2>&1 | tail -3
fi

# Check if there are any commits ahead of origin/main
AHEAD=$(git rev-list --count origin/main..HEAD)
if [[ "$AHEAD" -eq 0 ]]; then
  echo "[$ENGINE] No commits made — $ENGINE didn't produce any changes."
  gh issue edit "$ISSUE_NUMBER" --repo Lore-Hex/QuillUI --remove-label "$ENGINE:claimed" >/dev/null
  exit 1
fi

# Push and open PR
git push -u origin "$BRANCH"
PR_URL=$(gh pr create --repo Lore-Hex/QuillUI \
  --title "[$ENGINE] $ISSUE_TITLE" \
  --body "$(printf 'Closes #%s\n\nAuto-generated by %s swarm worker.\n\nThis PR needs loom Judge review before merge.' "$ISSUE_NUMBER" "$ENGINE")" \
  --label "loom:review-requested" \
  --base main \
  --head "$BRANCH")
echo "[$ENGINE] Opened PR: $PR_URL"

# Remove the claim so the issue is fully handed off to the PR review flow
gh issue edit "$ISSUE_NUMBER" --repo Lore-Hex/QuillUI --remove-label "$ENGINE:claimed" >/dev/null
echo "[$ENGINE] Done with issue #$ISSUE_NUMBER"
