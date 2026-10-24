#!/usr/bin/env bash
# scripts/release/protect-tags.sh [owner/repo]
#
# Creates (once) the repository ruleset that makes release tags immutable:
# v* tags cannot be deleted or moved. Idempotent: exits 0 if a ruleset named
# "release-tags" already exists.

set -euo pipefail

repo="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

if gh api "repos/$repo/rulesets" --jq '.[].name' | grep -qx 'release-tags'; then
  echo "ok: ruleset 'release-tags' already exists on $repo"
  exit 0
fi

gh api --method POST "repos/$repo/rulesets" \
  --input - <<'JSON' >/dev/null
{
  "name": "release-tags",
  "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "update" },
    { "type": "non_fast_forward" }
  ]
}
JSON
echo "ok: ruleset 'release-tags' created on $repo (v* tags: no delete, no move)"
