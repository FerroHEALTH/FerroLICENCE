#!/usr/bin/env bash
# scripts/checks/no-secret-material.sh
#
# Refuses secret key material anywhere in the tree. `keys/` may hold PUBLIC
# certificates only; nothing anywhere may carry a private key block or a
# GnuPG key file, and no file may sit inside a GnuPG keyring directory.
#
#   no-secret-material.sh            every tracked file
#   no-secret-material.sh --staged   the index (the pre-commit hook)
#
# Exit 1 with the offending paths on a hit, 0 otherwise.

set -euo pipefail

mode="${1:-}"
if [ "$mode" = "--staged" ]; then
  list() { git diff --cached --name-only --diff-filter=ACMR; }
  read_file() { git show ":$1"; }
else
  list() { git ls-files; }
  read_file() { cat -- "$1"; }
fi

pattern='-----BEGIN (PGP PRIVATE KEY BLOCK|OPENSSH PRIVATE KEY|RSA PRIVATE KEY|EC PRIVATE KEY|DSA PRIVATE KEY|PRIVATE KEY|ENCRYPTED PRIVATE KEY)-----'
# GnuPG's own key store (private-keys-v1.d/*.key) holds S-expressions, not
# armored blocks.
gnupg_pattern='\((protected-|shadowed-)?private-key'
status=0

while IFS= read -r path; do
  [ -n "$path" ] || continue
  # This script names the patterns it hunts; skip itself.
  [ "$path" = "scripts/checks/no-secret-material.sh" ] && continue
  case "$path" in
    .keyring/* | */.keyring/* | *private-keys-v1.d/* | *openpgp-revocs.d/*)
      echo "SECRET MATERIAL: $path is inside a GnuPG keyring" >&2
      status=1
      continue
      ;;
  esac
  if read_file "$path" 2>/dev/null | grep -qE -e "$pattern" -e "$gnupg_pattern"; then
    echo "SECRET MATERIAL: $path carries a private key" >&2
    status=1
  fi
  case "$path" in
    keys/*.asc | */keys/*.asc)
      if ! read_file "$path" | grep -q -- '-----BEGIN PGP PUBLIC KEY BLOCK-----'; then
        echo "NOT A PUBLIC CERTIFICATE: $path must be an armored PGP PUBLIC KEY BLOCK" >&2
        status=1
      fi
      ;;
  esac
done < <(list)

if [ "$status" -ne 0 ]; then
  echo "refused: secret material never enters this repository (CLAUDE.md, .claude/rules/secrets.md)" >&2
fi
exit "$status"
