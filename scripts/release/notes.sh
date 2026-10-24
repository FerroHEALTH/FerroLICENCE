#!/usr/bin/env bash
# scripts/release/notes.sh vX.Y.Z
#
# Prints the CHANGELOG.md section for the version: the release body. A beta
# (vX.Y.Z-beta.N) prints the [Unreleased] section.

set -euo pipefail

tag="${1:?usage: notes.sh vX.Y.Z}"
version="${tag#v}"
case "$version" in *-beta.*) version="Unreleased" ;; esac

awk -v v="$version" '
  $0 ~ "^## \\[" v "\\]" { on = 1; next }
  on && /^## \[/ { exit }
  on { print }
' CHANGELOG.md | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
