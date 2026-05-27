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
#   3. Creates a git worktree at .swarm/worktrees/issue-N with a local
#      .gitignore so swarm-internal files (.swarm-*) never enter a commit.
#   4. Runs the engine non-interactively with the issue body as prompt.
#   5. **Quality gate** (added 2026-05-28): runs `swift build` on the
#      whole package. If it fails, the iteration ABANDONS — no PR is
#      opened, the claim is released, and the issue goes back to the
#      loom:issue queue for another attempt. This stops the "Codex
#      wrote nothing useful, wrapper auto-committed temp logs as WIP"
#      class of trash PRs.
#   6. Opens a PR labeled `loom:review-requested` only if (a) the engine
#      produced commits with actual code changes (Swift/Python/sh/md/yaml/json,
#      NOT the swarm log files) and (b) the build still passes.
#
# Intended to be run inside a tmux session via swarm-loop.sh.
# Exits 0 on success (PR opened or no work to do).
# Exits non-zero on failure (build failed / no real changes / push error).

set -euo pipefail

ENGINE="${1:-}"
if [[ "$ENGINE" != "codex" && "$ENGINE" != "gemini" ]]; then
  echo "Usage: $0 codex|gemini" >&2
  exit 64
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# -----------------------------------------------------------------------------
# 1. Claim an unclaimed loom:issue ticket
# -----------------------------------------------------------------------------
ISSUE_JSON=$(gh issue list --repo Lore-Hex/QuillUI \
  --label "loom:issue" --state open \
  --json number,title,body,labels --limit 30)

ISSUE_NUMBER=$(echo "$ISSUE_JSON" | ENGINE="$ENGINE" python3 -c "
import json, os, sys
engine = os.environ['ENGINE']
issues = json.load(sys.stdin)
busy = ('loom:building', 'codex:claimed', 'gemini:claimed', 'claude:claimed', 'loom:curating', 'loom:treating', 'loom:reviewing')
simple_label = 'complexity:simple'

def candidates(issues):
    for issue in sorted(issues, key=lambda x: x['number']):
        labels = [l['name'] for l in issue['labels']]
        if any(l in labels for l in busy):
            continue
        yield issue, labels

if engine == 'gemini':
    for issue, labels in candidates(issues):
        if simple_label in labels:
            print(issue['number'])
            break
else:
    complex_pick = None
    simple_pick = None
    for issue, labels in candidates(issues):
        if simple_label in labels:
            if simple_pick is None:
                simple_pick = issue['number']
        else:
            if complex_pick is None:
                complex_pick = issue['number']
        if complex_pick is not None:
            break
    if complex_pick is not None:
        print(complex_pick)
    elif simple_pick is not None:
        print(simple_pick)
")

if [[ -z "$ISSUE_NUMBER" ]]; then
  echo "[$ENGINE] No unclaimed issues. Exiting." >&2
  exit 0
fi

echo "[$ENGINE] Claiming issue #$ISSUE_NUMBER..."
gh issue edit "$ISSUE_NUMBER" --repo Lore-Hex/QuillUI \
  --add-label "$ENGINE:claimed" \
  --remove-label "loom:issue" >/dev/null

ISSUE_TITLE=$(gh issue view "$ISSUE_NUMBER" --repo Lore-Hex/QuillUI --json title --jq '.title')
ISSUE_BODY=$(gh issue view "$ISSUE_NUMBER" --repo Lore-Hex/QuillUI --json body --jq '.body')

# -----------------------------------------------------------------------------
# 2. Create a fresh worktree
# -----------------------------------------------------------------------------
BRANCH="$ENGINE/issue-$ISSUE_NUMBER"
WORKTREE=".swarm/worktrees/$ENGINE-issue-$ISSUE_NUMBER"
mkdir -p .swarm/worktrees
if [[ -d "$WORKTREE" ]]; then
  git worktree remove --force "$WORKTREE" 2>/dev/null || rm -rf "$WORKTREE"
fi
git fetch origin main >/dev/null 2>&1 || true
git worktree add -b "$BRANCH" "$WORKTREE" origin/main

echo "[$ENGINE] Worktree at $WORKTREE on branch $BRANCH"

# Drop a local .gitignore inside the worktree (NOT committed) so the
# wrapper's stuff never enters a commit even if the engine runs `git add -A`.
cat > "$WORKTREE/.git/info/exclude" <<'EXCLUDE'
.swarm-prompt.txt
.swarm-run.log
.swarm-build-after.log
EXCLUDE

# -----------------------------------------------------------------------------
# 3. Build the prompt — now demands build verification before declaring done
# -----------------------------------------------------------------------------
PROMPT_FILE="$WORKTREE/.swarm-prompt.txt"
cat > "$PROMPT_FILE" <<PROMPT
You are an autonomous coding agent implementing GitHub issue #$ISSUE_NUMBER for the Lore-Hex/QuillUI repository.

Your working directory IS a fresh git worktree at this path. Implement the issue's acceptance criteria. When you're done, COMMIT your work to the current branch ($BRANCH). Do NOT push or open a PR — the spawn wrapper will handle that.

QUALITY BAR — read carefully:

1. **The build must pass before you commit.** Run \`swift build\` after every meaningful edit. If it fails, fix it before continuing. The wrapper that runs after you exits will run \`swift build\` itself and ABANDON your PR if it fails — your work is discarded if the build is broken.

2. **Tests must pass for any test you touch.** If the issue says "add tests" or you write tests, run \`swift test --filter <SuiteName>\` and confirm green before committing.

3. **No trash commits.** Do NOT commit \`.swarm-prompt.txt\`, \`.swarm-run.log\`, build artifacts under \`.build/\`, or any other temporary scratch. The wrapper has gitignored these but if you somehow add them, they will be rejected at PR time.

4. **No empty PRs.** If you can't make real progress on this issue — exit WITHOUT committing. The wrapper detects "no commits" and skips the PR, returning the issue to the queue for another engine to try. That is the correct behavior; do not commit a placeholder just to look productive.

5. **If you commit, the commit must contain real source code changes** in at least one of: \`*.swift\`, \`*.py\`, \`*.sh\`, \`*.md\`, \`*.yml\`, \`*.json\`, \`Package.swift\`, \`Package.resolved\`, \`Tests/Fixtures/**\`. A commit that only touches the swarm log files will be rejected.

PROJECT CONSTRAINTS:
- This is a Swift package (Package.swift at the repo root). Use the existing target structure.
- Do not modify Package.swift's existing target list unless the issue explicitly requires a new target.
- Do not touch other targets unless the issue scope requires it.
- The strict Mac-reference verifier targets pixel-perfect macOS appearance via the QuillPaint stack. Don't propose Adwaita or native-Linux feel.
- Tests use Swift Testing (\`import Testing\`) and \`@Test\` / \`@Suite\` macros.
- Final commit message should reference the issue: "Closes #$ISSUE_NUMBER"

ISSUE TITLE: $ISSUE_TITLE

ISSUE BODY:
$ISSUE_BODY

Begin.
PROMPT

cd "$WORKTREE"

# -----------------------------------------------------------------------------
# 4. Run the engine
# -----------------------------------------------------------------------------
echo "[$ENGINE] Running $ENGINE on issue #$ISSUE_NUMBER..."
case "$ENGINE" in
  codex)
    codex exec --sandbox workspace-write --skip-git-repo-check "$(cat .swarm-prompt.txt)" \
      2>&1 | tee .swarm-run.log
    ;;
  gemini)
    gemini --yolo --output-format text -p "$(cat .swarm-prompt.txt)" \
      2>&1 | tee .swarm-run.log
    ;;
esac

# -----------------------------------------------------------------------------
# 5. Quality gate: filter trash, validate build, decide whether to PR
# -----------------------------------------------------------------------------

# 5a. Check the engine made commits (excluding any uncommitted scratch).
COMMITS_AHEAD=$(git rev-list --count origin/main..HEAD)
if [[ "$COMMITS_AHEAD" -eq 0 ]]; then
  echo "[$ENGINE] No commits made — $ENGINE didn't produce any changes. Releasing claim."
  cd "$REPO_ROOT"
  gh issue edit "$ISSUE_NUMBER" --repo Lore-Hex/QuillUI \
    --remove-label "$ENGINE:claimed" \
    --add-label "loom:issue" >/dev/null
  exit 1
fi

# 5b. Check the commits contain at least one real source file change.
# Anything outside this list counts as trash. Note: gitignored files
# (.swarm-*) shouldn't be in commits at all, but double-check.
CHANGED_FILES=$(git diff --name-only origin/main..HEAD)
REAL_CHANGES=$(echo "$CHANGED_FILES" | grep -E '\.(swift|py|sh|md|yml|yaml|json|toml|h|c|cpp|swiftinterface)$|^Package\.(swift|resolved)$|^Tests/Fixtures/' | grep -v '^\.swarm-' || true)
if [[ -z "$REAL_CHANGES" ]]; then
  echo "[$ENGINE] Commits contain no real source file changes:"
  echo "$CHANGED_FILES" | sed 's/^/  /'
  echo "[$ENGINE] Aborting — releasing claim."
  cd "$REPO_ROOT"
  gh issue edit "$ISSUE_NUMBER" --repo Lore-Hex/QuillUI \
    --remove-label "$ENGINE:claimed" \
    --add-label "loom:issue" >/dev/null
  exit 1
fi

# 5c. Build the whole package. If it fails, abandon.
echo "[$ENGINE] Running build gate (swift build)..."
if ! swift build > .swarm-build-after.log 2>&1; then
  echo "[$ENGINE] BUILD FAILED — aborting PR. Last 20 lines of build log:"
  tail -20 .swarm-build-after.log | sed 's/^/  /'
  echo "[$ENGINE] Releasing claim. Issue returns to queue."
  cd "$REPO_ROOT"
  gh issue edit "$ISSUE_NUMBER" --repo Lore-Hex/QuillUI \
    --remove-label "$ENGINE:claimed" \
    --add-label "loom:issue" >/dev/null
  exit 1
fi
echo "[$ENGINE] Build passes."

# -----------------------------------------------------------------------------
# 6. Build passed + real changes present → push branch + open PR
# -----------------------------------------------------------------------------
git push -u origin "$BRANCH"
PR_URL=$(gh pr create --repo Lore-Hex/QuillUI \
  --title "[$ENGINE] $ISSUE_TITLE" \
  --body "$(printf 'Closes #%s\n\nAuto-generated by %s swarm worker.\n\nBuild gate passed: swift build succeeded after the engine'\''s commits.\n\nChanged files:\n%s\n\nThis PR needs loom Judge review before merge.' "$ISSUE_NUMBER" "$ENGINE" "$(echo "$REAL_CHANGES" | sed 's/^/- /')")" \
  --label "loom:review-requested" \
  --base main \
  --head "$BRANCH")
echo "[$ENGINE] Opened PR: $PR_URL"

# Release the claim so the issue is fully handed off to the PR review flow
gh issue edit "$ISSUE_NUMBER" --repo Lore-Hex/QuillUI --remove-label "$ENGINE:claimed" >/dev/null
echo "[$ENGINE] Done with issue #$ISSUE_NUMBER"
