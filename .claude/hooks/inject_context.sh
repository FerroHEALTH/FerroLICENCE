#!/usr/bin/env bash
# .claude/hooks/inject_context.sh
#
# Claude Code SessionStart hook. Prints the state a session needs to orient:
# open issues, the trust anchors, the register size, git status.

set -uo pipefail

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$root" || exit 0

echo "=== FerroLICENCE (private) — read CLAUDE.md and docs/design.md first ==="
echo
echo "=== open issues ==="
# <Type/Priority> is the native issue type and the Priority field (CLAUDE.md
# § Workflow); read one issue with: gh issue view <n> --json title,body,comments
# shellcheck disable=SC2016 # $labels is a jq binding
gh issue list --state open --limit 50 --json number,title,labels \
  --jq '.[] | ([.labels[].name] | join(", ")) as $labels | "#\(.number)  \(.title)  [\($labels)]"' 2>/dev/null |
  while IFS= read -r line; do
    n="${line%%  *}"
    tp="$(bash scripts/gh/fields.sh show "${n#\#}" 2>/dev/null | awk '/^  type:/ { t = $2 } /^  priority:/ { p = $2 } END { printf "%s/%s", t, p }')"
    echo "${line/  \[/  <${tp:-?/?}>  [}"
  done || echo "(gh unavailable)"
echo
echo "=== trust anchors (keys/*.asc) ==="
ls -1 keys/*.asc 2>/dev/null || echo "(none yet: the key ceremony has not run)"
echo
echo "=== register ==="
count="$(find register -mindepth 3 -maxdepth 3 -name record.json 2>/dev/null | wc -l | tr -d ' ')"
echo "$count issued licence(s)"
echo
echo "=== git status ==="
git status --short --branch 2>/dev/null
echo
echo "=== last 5 commits ==="
git log --oneline -5 2>/dev/null