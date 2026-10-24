#!/usr/bin/env bash
# scripts/dev/sync-strings.sh
#
# Builds the app and writes every string the compiler extracted into the
# String Catalogs: the app's and each kit module's Localizable.xcstrings.
# Xcode does this on every build in the IDE; xcodebuild only extracts, so
# run this after changing user-facing text outside Xcode, then translate
# the new entries (Dutch) and build again.

set -euo pipefail
root="$(git rev-parse --show-toplevel)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
derived="${DERIVED:-$root/build/DerivedData}"

build=(-project "$root/FerroLICENCE/FerroLICENCE.xcodeproj" -scheme FerroLICENCE -configuration Debug
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived"
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
if [ -n "${SPM:-}" ]; then build+=(-clonedSourcePackagesDirPath "$SPM"); fi
xcodebuild build -quiet "${build[@]}"

intermediates="$derived/Build/Intermediates.noindex"
sync() {
  local catalog="$1" built="$2"
  local data=()
  while IFS= read -r f; do data+=("$f"); done < <(find "$intermediates/$built" -name '*.stringsdata')
  if ((${#data[@]})); then
    xcrun xcstringstool sync "$catalog" --stringsdata "${data[@]}"
    echo "$(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["strings"]))' "$catalog") strings in ${catalog#"$root"/}"
  fi
}
sync "$root/FerroLICENCE/FerroLICENCE/Localizable.xcstrings" "FerroLICENCE.build/Debug/FerroLICENCE.build"
for module in LicenceCore Register Signing GitHubKit; do
  sync "$root/FerroLicenceKit/Sources/$module/Localizable.xcstrings" "FerroLicenceKit.build/Debug/$module-t.build"
done
