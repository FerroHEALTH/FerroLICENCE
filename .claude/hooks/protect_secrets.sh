#!/usr/bin/env bash
# .claude/hooks/protect_secrets.sh
#
# Claude Code PreToolUse hook (matcher: Write|Edit|NotebookEdit).
# Refuses a write that would put secret key material into the tree, and any
# write under keys/ that is not a public certificate. Exit 2 blocks the tool
# call and returns the stderr text to Claude; exit 0 allows.

set -euo pipefail

payload="$(cat)"

if command -v jq >/dev/null 2>&1; then
  file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
  content="$(printf '%s' "$payload" | jq -r '(.tool_input.content // .tool_input.new_string // "")' 2>/dev/null || true)"
else
  file_path="$(printf '%s' "$payload" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  content="$payload"
fi

if printf '%s' "$content" | grep -qE -- '-----BEGIN (PGP PRIVATE KEY BLOCK|OPENSSH PRIVATE KEY|RSA PRIVATE KEY|EC PRIVATE KEY|DSA PRIVATE KEY|PRIVATE KEY|ENCRYPTED PRIVATE KEY)-----'; then
  echo "BLOCKED: this write carries a private key block. Secret key material never enters this repository (CLAUDE.md §Hard rules)." >&2
  exit 2
fi

case "${file_path:-}" in
*/keys/*|keys/*)
  case "$file_path" in
  *.asc)
    if ! printf '%s' "$content" | grep -q -- '-----BEGIN PGP PUBLIC KEY BLOCK-----'; then
      echo "BLOCKED: keys/*.asc must be an armored PGP PUBLIC KEY BLOCK written by the FerroLICENCE app when it trusts a key." >&2
      exit 2
    fi
    ;;
  *README.md) ;;
  *)
    echo "BLOCKED: keys/ holds public certificates (*.asc) and its README only." >&2
    exit 2
    ;;
  esac
  ;;
esac

exit 0
