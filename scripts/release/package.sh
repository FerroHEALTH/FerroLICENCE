#!/usr/bin/env bash
# scripts/release/package.sh <notarised FerroLICENCE.app> <version> <out-dir> [<dSYMs dir>]
#
# The release's files: FerroLICENCE-<version>.dmg for people,
# FerroLICENCE-<version>.zip for the updater, the debug symbols as
# FerroLICENCE-<version>-dSYMs.zip when given. GitHub's release attestation
# vouches for each file once the release is published.
# The app must already be signed, notarised and stapled. The formats are the
# ones Sparkle's publishing guide asks for: a zip made by ditto that keeps
# symlinks, and an APFS disk image compressed with lzfse. The disk image
# opens as an install window that Finder lays out, so this needs a session
# that may script Finder (the macOS runners can).

set -euo pipefail

app="${1:?usage: package.sh <app> <version> <out-dir>}"
version="${2:?usage: package.sh <app> <version> <out-dir>}"
out="${3:?usage: package.sh <app> <version> <out-dir>}"
dsyms="${4:-}"
mkdir -p "$out"

ditto -c -k --sequesterRsrc --keepParent "$app" "$out/FerroLICENCE-$version.zip"

# The install window: the app on the left, an Applications link on the
# right, on the background dmg-background.swift draws. Finder records the
# layout in the volume's .DS_Store while the image is writable; the image is
# then compressed into the read-only .dmg people open.
here="$(cd "$(dirname "$0")" && pwd)"
volume="FerroLICENCE $version"
work="$(mktemp -d)"
swift "$here/dmg-background.swift" "$work/" >/dev/null
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" -out "$work/background.tiff" >/dev/null

writable="$work/writable.dmg"
megabytes=$(($(du -sm "$app" | cut -f1) + 20))
diskutil image create blank --fs APFS --size "${megabytes}m" --volumeName "$volume" "$writable" >/dev/null
if [ -d "/Volumes/$volume" ]; then diskutil eject "/Volumes/$volume" >/dev/null; fi
diskutil image attach "$writable" >/dev/null
mounted="/Volumes/$volume"
[ -d "$mounted" ] || {
  echo "the writable image did not mount at $mounted" >&2
  exit 1
}
ditto "$app" "$mounted/FerroLICENCE.app"
ln -s /Applications "$mounted/Applications"
mkdir "$mounted/.background"
cp "$work/background.tiff" "$mounted/.background/background.tiff"

# Positions match dmg-background.swift: icons at (170, 200) and (490, 200)
# in a 660 by 400 window.
osascript - "$volume" <<'APPLESCRIPT' >/dev/null
on run argv
  tell application "Finder"
    tell disk (item 1 of argv)
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      -- 660 by 400 of content, plus the 28-point title bar.
      set the bounds of container window to {200, 120, 860, 548}
      set options to the icon view options of container window
      set arrangement of options to not arranged
      set icon size of options to 112
      set text size of options to 13
      set background picture of options to file ".background:background.tiff"
      set position of item "FerroLICENCE.app" of container window to {170, 200}
      set position of item "Applications" of container window to {490, 200}
      update without registering applications
      delay 1
      close
    end tell
  end tell
end run
APPLESCRIPT
for _ in $(seq 1 20); do
  [ -f "$mounted/.DS_Store" ] && break
  sleep 0.5
done
[ -f "$mounted/.DS_Store" ] || {
  echo "Finder did not record the window layout" >&2
  exit 1
}
sync
diskutil eject "$mounted" >/dev/null
diskutil image create from --format ULFO "$writable" "$out/FerroLICENCE-$version.dmg" >/dev/null
rm -r "$work"

if [ -n "$dsyms" ]; then
  ditto -c -k --keepParent "$dsyms" "$out/FerroLICENCE-$version-dSYMs.zip"
fi
echo "packaged $(find "$out" -type f | wc -l | tr -d ' ') files in $out"
