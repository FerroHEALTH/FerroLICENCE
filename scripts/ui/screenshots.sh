#!/usr/bin/env bash
# scripts/ui/screenshots.sh [screen ...]
#
# The screenshot tour: opens the app once per screen in fixture mode (no
# network, no YubiKey), in light and dark, at the smallest window and a large
# one, and saves every window as a PNG. Look at every image before calling UI
# work done (.claude/rules/swift.md).
#
# By default it runs the UI test TourTests, so Liquid Glass is drawn exactly
# as people see it; that needs UI automation allowed once
# (sudo automationmodetool enable-automationmode-without-authentication).
# CAMERA=1 uses the app's own camera instead, which needs no permission but
# cannot draw glass.
#
#   OUT=/tmp/shots bash scripts/ui/screenshots.sh customers revoke
#   EXTRA="-AppleLocale en_US -AppleICUForce12HourTime YES" bash scripts/ui/screenshots.sh activity

set -euo pipefail
root="$(git rev-parse --show-toplevel)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
out="${OUT:-$root/build/screenshots}"
derived="${DERIVED:-$root/build/DerivedData}"
sizes="${SIZES:-860x560 1280x800}"
appearances="${APPEARANCES:-light dark}"
screens="$*"
mkdir -p "$out"

# Signed to run here; no certificate needed.
build=(-project "$root/FerroLICENCE/FerroLICENCE.xcodeproj" -scheme FerroLICENCE -configuration Debug
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived"
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
if [ -n "${SPM:-}" ]; then build+=(-clonedSourcePackagesDirPath "$SPM"); fi

all="signIn ready customers draft check sign recording recorded revoke activity checkFile attest keys stopKey trustKey setup sync settings menus"
if [ -z "$screens" ]; then screens="$all"; fi
read -r -a screen_list <<<"$screens"

if [ "${CAMERA:-0}" != 1 ]; then
  # Built once; then each screen is a short test of its own, so one screen
  # that fails names itself and spoils no other.
  xcodebuild build-for-testing -quiet "${build[@]}"
  missing=0
  for screen in "${screen_list[@]}"; do
    # A freshly built app is slow to start the first time; one more try.
    ok=0
    for _ in 1 2; do
      result="$(mktemp -d)/tour.xcresult"
      if TEST_RUNNER_FL_TOUR=1 TEST_RUNNER_FL_TOUR_SCREENS="$screen" TEST_RUNNER_FL_TOUR_SIZES="$sizes" \
        TEST_RUNNER_FL_TOUR_APPEARANCES="$appearances" TEST_RUNNER_FL_TOUR_EXTRA="${EXTRA:-}" \
        xcodebuild test-without-building -quiet "${build[@]}" -only-testing:FerroLICENCEUITests/TourTests \
        -resultBundlePath "$result" >/dev/null 2>&1; then
        ok=1
        break
      fi
    done
    if [ "$ok" = 0 ]; then
      echo "the tour failed on $screen:" >&2
      xcrun xcresulttool get test-results tests --path "$result" 2>/dev/null |
        python3 -I -c 'import json,sys
def walk(n):
    for c in n.get("children", []):
        if c.get("nodeType") == "Failure Message": print("  " + c.get("name", ""))
        walk(c)
for t in json.load(sys.stdin).get("testNodes", []): walk(t)' >&2 || true
      missing=1
    fi
    attachments="$(mktemp -d)"
    xcrun xcresulttool export attachments --path "$result" --output-path "$attachments" >/dev/null 2>&1 || true
    python3 -I - "$attachments" "$out" <<'PY'
import json, os, shutil, sys
src, out = sys.argv[1], sys.argv[2]
manifest = f"{src}/manifest.json"
for test in json.load(open(manifest)) if os.path.exists(manifest) else []:
    for a in test.get("attachments", []):
        name = a.get("suggestedHumanReadableName", "")
        if a["exportedFileName"].endswith(".png") and "--" in name:
            shutil.copy(f"{src}/{a['exportedFileName']}", f"{out}/{name.rsplit('_0_', 1)[0]}.png")
PY
  done
  echo "$(find "$out" -name '*.png' | wc -l | tr -d ' ') images in $out"
  exit "$missing"
fi

xcodebuild build -quiet "${build[@]}"
app="$derived/Build/Products/Debug/FerroLICENCE.app/Contents/MacOS/FerroLICENCE"
read -r -a size_list <<<"$sizes"
read -r -a appearance_list <<<"$appearances"
read -r -a extra <<<"${EXTRA:-}"
missing=0
for screen in "${screen_list[@]}"; do
  for appearance in "${appearance_list[@]}"; do
    for size in "${size_list[@]}"; do
      "$app" -FLFixtures YES -FLScreen "$screen" -FLAppearance "$appearance" -FLWindowSize "$size" \
        -FLCapture "$out" -ApplePersistenceIgnoreState YES -NSQuitAlwaysKeepsWindows NO ${extra[@]+"${extra[@]}"} >/dev/null 2>&1 &
      pid=$!
      for _ in $(seq 1 60); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      if ! compgen -G "$out/$screen-$appearance-$size--*.png" >/dev/null; then
        echo "no image for $screen ($appearance, $size): the app did not start or did not settle" >&2
        missing=1
      fi
    done
  done
done
echo "$(find "$out" -name '*.png' | wc -l | tr -d ' ') images in $out"
exit "$missing"
