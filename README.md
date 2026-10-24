# FerroLICENCE

Licensor-side tooling for FerroEHR commercial licences, source-available
under the Business Source License 1.1 (`LICENSE`, `NOTICE`). Copyright 2026
Cadasto B.V., the Licensor named in FerroEHR's `LICENSE`.

FerroEHR is BUSL-1.1: production use in the course of a business needs a
commercial licence. This repository issues those licences, keeps the
register of what was issued, and can tell from a sample of identifiers which
licence (or none) a FerroEHR deployment was running under. The product
itself runs identically with or without a licence.

Everything is done in one Mac app, FerroLICENCE, in English or Dutch. You
sign in with GitHub; the app reads the register from its own private
repository, runs the Register check on every change, and records it there as
a pull request, which it merges at once. There is no clone and no terminal work. The
register (every customer and licence) is never in this repository.

## Download

**[Download the latest release](https://github.com/FerroHEALTH/FerroLICENCE/releases/latest)**:
open it and choose `FerroLICENCE-<version>.dmg` under Assets. Every release
is listed on the [releases page](https://github.com/FerroHEALTH/FerroLICENCE/releases).

| Needs | |
|---|---|
| A Mac with Apple silicon | macOS 27 |
| GnuPG and its PIN window | `brew install gnupg pinentry-mac` (only to sign; checking and attesting need nothing) |
| A GitHub account | with access to the register's private repository |
| A YubiKey 5 | only for the two owners, who sign licences |

1. Open the `.dmg` and drag FerroLICENCE to Applications. It is signed with
   a Developer ID and notarised by Apple, so macOS opens it without a
   warning. GitHub signs an attestation of every release; check the
   download against it with
   `gh release verify-asset <tag> FerroLICENCE-<version>.dmg -R FerroHEALTH/FerroLICENCE`.
2. Open FerroLICENCE and click **Sign In with GitHub**; the app gives you a
   code to paste on github.com.
3. **Ready to Issue** lists what signing needs, each with a tick. Without a
   YubiKey you can still check licence files, attest data and read Activity.

After that the app updates itself from these releases (FerroLICENCE ›
Check for Updates…); updates are checked against Sparkle's and Apple's
signatures before they install. `docs/manuals/01-install.md` has every step.

## What the app does

| Section | What |
|---|---|
| Customers | who needs attention, every customer and their licences; New Licence, Renew, Revoke, Download to Downloads, Copy Setup Instructions |
| Activity | every recorded change, linked to its pull request |
| Check a File | whether a licence file passes FerroEHR's nine checks and is in the register |
| Attest Data | whose licence made a sample of FerroEHR identifiers |
| Keys | the YubiKey in this Mac, the trusted keys, Set Up a YubiKey, Trust a New Key, Stop Using a Key |

Issuing asks for the PIN and a touch of the YubiKey; revoking, trusting a
key and stopping one each ask you to type a word first. Nothing is written
before that.

## Manuals

| Manual | For |
|---|---|
| [`00-what-to-buy.md`](docs/manuals/00-what-to-buy.md) | the owners, before anything else |
| [`01-install.md`](docs/manuals/01-install.md) | everyone, once per Mac |
| [`02-yubikey.md`](docs/manuals/02-yubikey.md) | each owner, once per YubiKey |
| [`03-licences.md`](docs/manuals/03-licences.md) | issuing, renewing and revoking licences |
| [`04-check-and-attest.md`](docs/manuals/04-check-and-attest.md) | checking a licence file, finding whose licence made some data |
| [`05-lost-key.md`](docs/manuals/05-lost-key.md) | a lost YubiKey, or handing a key over to someone else |

The design is `docs/design.md`; `docs/research.md` records why each choice
was made, and `docs/threat-model.md` what it defends against.

## Setting it up

`docs/setup.md` lists everything configured outside the code (the GitHub
App, the Developer ID certificate, notarisation, Sparkle's key, the release
secrets, the test repository) and the end-to-end run that proves it.
`docs/releasing.md` is how a release is cut: a signed `v*` tag builds,
signs, notarises and publishes it, and the release is immutable once
published.

## Layout

| Path | What |
|---|---|
| `FerroLICENCE/` | the macOS app (SwiftUI, macOS 27, Apple silicon) and its UI tests |
| `FerroLicenceKit/` | everything the app does without a window: the licence format and FerroEHR's checks, the register, GnuPG and the YubiKey, GitHub, and the `register-check` command |
| `FerroLicenceKit/Tests/RegisterSnapshot/` | a fixed copy of the register's keys, `signers.json` and the two public licences, for the tests |
| `docs/` | design, research, threat model, FerroEHR integration contract, setup, releasing, the GitHub App |
| `docs/manuals/` | one manual per task, following the app's screens |
| `scripts/` | the guards CI and the git hooks run, the screenshot tour, the release helpers |

## Develop

Xcode 27.1 on an Apple silicon Mac. Open `FerroLICENCE/FerroLICENCE.xcodeproj`;
the kit is a local package inside it. How Swift is written here is in
`.claude/rules/swift.md`.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift format lint --strict --recursive FerroLicenceKit FerroLICENCE
FERROLICENCE_REQUIRE_GPG=1 swift test --package-path FerroLicenceKit
xcodebuild test -project FerroLICENCE/FerroLICENCE.xcodeproj -scheme FerroLICENCE -destination 'platform=macOS,arch=arm64'
bash scripts/ui/screenshots.sh          # every screen, light and dark, two sizes
EXTRA="-AppleLanguages (nl) -AppleLocale nl_NL" bash scripts/ui/screenshots.sh   # the same in Dutch
bash scripts/checks/no-secret-material.sh
```

Install the git hooks once: `git config core.hooksPath .githooks`. Every
change reaches `main` through a pull request.

## What never lives here

Secret key material, and no keyring, however private the repository. Each
of the two master keys lives on its owner's YubiKey and cannot leave it;
three independent guards refuse private keys and keyring files in the tree
(`.claude/rules/secrets.md`). The Developer ID certificate, the notarisation
key and Sparkle's private key live in the repository's Actions secrets
(Sparkle's also in the login Keychain of the owner who made it), never in a
file here.
