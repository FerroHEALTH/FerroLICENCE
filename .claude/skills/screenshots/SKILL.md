---
name: screenshots
description: Run and review the FerroLICENCE app's screenshot tour. Use after any change to a view, a sheet, a window or the app's text, and whenever asked to run the app, look at a screen or check the UI for overflow, truncation, padding or bad layout, in English or Dutch.
---

# The screenshot tour

The debug app has a fixture mode (no network, no YubiKey, a fixed date).
`scripts/ui/screenshots.sh` builds the UI tests once, then runs the UI test
`TourTests` once per screen: each screen in light and dark, at the smallest
window (860 by 560) and a large one (1280 by 800), photographed through
XCUITest so Liquid Glass, padding and toolbars are drawn exactly as people
see them. Sheet screens photograph the sheet.

It needs UI automation allowed once on the Mac:
`sudo automationmodetool enable-automationmode-without-authentication`.
Without it, `CAMERA=1` uses the app's own camera, which needs no permission
but cannot draw glass (sidebar items, prominent buttons and popovers come
out blank).

1. Run the tour, for every screen or just the ones you changed (names are
   the cases of `Screen` in `FerroLICENCE/FerroLICENCE/App/Launch.swift`):

   ```bash
   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   OUT="$SCRATCH/shots" DERIVED="$SCRATCH/dd" bash scripts/ui/screenshots.sh customers revoke
   OUT="$SCRATCH/shots-nl" DERIVED="$SCRATCH/dd" EXTRA="-AppleLanguages (nl) -AppleLocale nl_NL" bash scripts/ui/screenshots.sh
   ```

   `SIZES`, `APPEARANCES` and `EXTRA` (more launch arguments, such as a
   12-hour clock: `-AppleLocale en_US -AppleICUForce12HourTime YES`) narrow
   or vary it. Put `OUT` and `DERIVED` in the scratchpad, never in the
   repository. A screen that fails is retried once, then named.
2. Tile each screen's variants into one image:
   `swift scripts/ui/contact-sheet.swift "$SCRATCH/shots" "$SCRATCH/sheets"`.
3. Read every contact sheet with the Read tool and look for: text cut off or
   wrapped mid-phrase (Dutch runs longer), controls that overlap or leave
   the window, toolbar items merged into the wrong glass group, dead space,
   tinted boxes or custom chrome where the system has a native control, ISO
   dates or raw identifiers where a person reads, untranslated English in
   the Dutch run, duplicated actions, buttons not where the macOS HIG puts
   them, and anything that differs between light and dark.
4. Fix, rerun the tour for that screen, and look again. Report what you saw
   and what you changed.

A new screen gets a `Screen` case and a branch in `AppModel.apply(_:)`, so
the tour photographs it from then on.
