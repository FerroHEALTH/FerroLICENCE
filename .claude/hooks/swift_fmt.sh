#!/usr/bin/env bash
# .claude/hooks/swift_fmt.sh
#
# Claude Code PostToolUse hook (matcher: Write|Edit). Formats an edited
# .swift file with swift format and lints an edited .sh file with shellcheck
# when it is installed. Formatting never blocks; a lint finding left after
# formatting, or a shellcheck finding, does (exit 2).

set -uo pipefail

payload="$(cat)" || true
if command -v jq >/dev/null 2>&1; then
  file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || true
else
  file_path="$(printf '%s' "$payload" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
fi
[ -f "${file_path:-}" ] || exit 0

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

case "$file_path" in
*.swift)
  swift format format -i --configuration "$root/.swift-format" "$file_path" >/dev/null 2>&1 || true
  findings="$(swift format lint --strict --configuration "$root/.swift-format" "$file_path" 2>&1)" || {
    printf '%s\n' "$findings" >&2
    exit 2
  }
  ;;
*.sh|*/.githooks/*)
  if command -v shellcheck >/dev/null 2>&1; then
    findings="$(shellcheck --severity=style "$file_path" 2>&1)" || {
      printf '%s\n' "$findings" >&2
      exit 2
    }
  fi
  ;;
esac
exit 0
