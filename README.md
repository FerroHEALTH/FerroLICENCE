# FerroLICENCE

The licensor side of FerroEHR commercial licences: a Mac app with which
Cadasto B.V. signs licences on a YubiKey, records them, checks licence
files and recovers which licence a sample of FerroEHR data was made under.
FerroEHR checks licences with its own code; nothing here is needed to run
FerroEHR.

The app is for Cadasto B.V. alone. A licence is only valid when one of
Cadasto's two master keys signed it, and those keys never leave their
YubiKeys, so this code cannot make a licence by itself. The register of
issued licences is not in this repository.

## Build

macOS 27 on Apple silicon, Xcode 27.1. Open
`FerroLICENCE/FerroLICENCE.xcodeproj`; the kit is a local package inside
it. The gates every change passes are in `CLAUDE.md`, and `docs/design.md`
is the design authority.

## Licence

Business Source License 1.1, with no additional use grant (`LICENSE`,
`NOTICE`). Copyright 2026 Cadasto B.V. Security issues: info@cadasto.com.
