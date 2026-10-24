#!/usr/bin/env bash
# .claude/hooks/block_dangerous.sh
#
# Claude Code PreToolUse hook (matcher: Bash). Refuses:
#   - rm -rf outside the temp directory
#   - force-pushes touching main, and bare force-pushes
#   - deleting or rewriting anything under register/ or keys/ by hand
#   - gpg commands that would export or delete secret keys

set -euo pipefail

payload="$(cat)"
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
else
  cmd="$payload"
fi
[ -n "${cmd:-}" ] || exit 0

if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])rm[[:space:]]+-[a-zA-Z]*([rR][a-zA-Z]*f|f[a-zA-Z]*[rR])'; then
  # shellcheck disable=SC2016 # the literal `$TMPDIR` is a grep pattern, not an expansion
  if ! printf '%s' "$cmd" | grep -qE 'rm[[:space:]]+-[a-zA-Z]+[[:space:]]+"?(/private)?/tmp/|\$TMPDIR'; then
    echo "BLOCKED: 'rm -rf' is not allowed outside the temp directory." >&2
    exit 2
  fi
fi

if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+push[^;|&]*(--force([^-]|$)|--force-with-lease|[[:space:]]-f([[:space:]]|$)|[[:space:]]\+[[:alnum:]])'; then
  if printf '%s' "$cmd" | grep -qE '(^|[[:space:]:/+])(main|master)([[:space:]]|$|["'"'"';&|])'; then
    echo "BLOCKED: force-push touching main is forbidden." >&2
    exit 2
  fi
  if ! printf '%s' "$cmd" | grep -qE '(feat|fix|chore|docs|refactor|perf|test|ci|build|release)/'; then
    echo "BLOCKED: bare force-push refused; name a conventional-type branch." >&2
    exit 2
  fi
fi

if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(git[[:space:]]+rm|rm|mv|>|sed[[:space:]]+-i)[^;|&]*(register|keys)/[^[:space:]]*\.(json|asc)'; then
  echo "BLOCKED: register/ and keys/ are written only by the FerroLICENCE app, through a pull request and the Register check (trust, issue, revoke, a lost key), and a key moves to keys/retired/ only by the owner (append-only record, CLAUDE.md §Hard rules)." >&2
  exit 2
fi

if printf '%s' "$cmd" | grep -qE 'gpg[^;|&]*(--export-secret-keys|--export-secret-subkeys|--delete-secret-keys|--delete-secret-and-public-key)'; then
  echo "BLOCKED: secret key export or deletion is a manual ceremony step for the owner, never run from a session (docs/manuals/05-lost-key.md)." >&2
  exit 2
fi

exit 0