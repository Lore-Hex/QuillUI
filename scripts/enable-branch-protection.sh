#!/bin/bash
# Enable GitHub branch protection on main with required status checks.
# This policy enforces that both Linux and macOS CI must pass before merging.
#
# Required checks:
# - 'Swift Linux Backends' (from .github/workflows/linux-ci.yml)
# - 'Build all 4 apps + test' (from .github/workflows/macos-ci.yml)

set -e

REPO="Lore-Hex/QuillUI"
BRANCH="main"

echo "Enabling branch protection for $REPO branch $BRANCH..."

gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" \
  --input - <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "Swift Linux Backends",
      "Build all 4 apps + test"
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
EOF

echo "Branch protection enabled successfully."
