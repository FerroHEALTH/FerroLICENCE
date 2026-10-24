#!/usr/bin/env bash
# scripts/release/check-version.sh vX.Y.Z | vX.Y.Z-beta.N
#
# The release plan: the tag names the app's version (MARKETING_VERSION in
# FerroLICENCE/App.xcconfig), CHANGELOG.md has a released section for it (a
# beta takes its notes from [Unreleased] instead), and the build settings a
# release needs are filled in. All must hold before anything is built.

set -euo pipefail

tag="${1:?usage: check-version.sh vX.Y.Z}"
if ! [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)(-beta\.[0-9]+)?$ ]]; then
  echo "tag '$tag' is not vX.Y.Z or vX.Y.Z-beta.N" >&2
  exit 1
fi
version="${BASH_REMATCH[1]}"
beta="${BASH_REMATCH[2]}"

setting() { sed -n "s/^$1 = *\(.*\)$/\1/p" FerroLICENCE/App.xcconfig | head -n 1; }

app="$(setting MARKETING_VERSION)"
if [ "$app" != "$version" ]; then
  echo "tag $tag but FerroLICENCE/App.xcconfig says MARKETING_VERSION = $app" >&2
  exit 1
fi

if [ -n "$beta" ]; then
  if [ -z "$(bash "$(dirname "$0")/notes.sh" "$tag")" ]; then
    echo "CHANGELOG.md has nothing under [Unreleased] for the beta's notes" >&2
    exit 1
  fi
elif ! grep -qE "^## \[${version//./\\.}\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" CHANGELOG.md; then
  echo "CHANGELOG.md has no '## [$version] - YYYY-MM-DD' section" >&2
  exit 1
fi

for key in FL_GITHUB_CLIENT_ID SPARKLE_PUBLIC_ED_KEY; do
  if [ -z "$(setting "$key")" ]; then
    echo "FerroLICENCE/App.xcconfig has no $key; a release without it cannot sign in or update (docs/releasing.md)" >&2
    exit 1
  fi
done

echo "ok: $tag matches App.xcconfig $app and CHANGELOG.md has its section"
