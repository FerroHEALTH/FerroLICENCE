# CLAUDE.md

The licensor side of FerroEHR commercial licences. **Public repository**
(BSL 1.1); the register itself is the private
`FerroHEALTH/FerroLICENCE-register`, which only the app writes.
Everything a licence needs that the product itself does not: trusting the
two master keys, licence issuance, the register of issued licences, and
attestation (recovering the identifier stamp from a sample and matching it
to the register). FerroEHR verifies licences and stamps identifiers with its
own code; `docs/ferroehr-integration.md` is the contract between the two.

Read `docs/design.md` before changing anything. It is the design authority
for this repository; `docs/research.md` records why each choice was made and
where the industry practice it follows is documented. Swift is written as
`.claude/rules/swift.md` says.

## Repository map

- `FerroLICENCE/`: the macOS app (SwiftUI, macOS 27, Apple Silicon).
  `App/` holds the state: `AppModel.swift` is the only place it changes,
  `Flows.swift` the issue, revoke, lost-key and setup flows, `Services.swift`
  the GitHub and GnuPG services behind protocols, `Updater.swift` Sparkle.
  `Views/` only draws. `Fixtures/` (debug builds only) is the example data,
  the launch scenarios and the screenshot camera. `App.xcconfig` holds the
  version, the GitHub App's client id and Sparkle's public key.
- `FerroLicenceKit/`: a local Swift package with everything the app does
  without a window. `LicenceCore`: the licence format, the token, the nine
  checks FerroEHR runs, the stamp and the attestation statistics, tied to
  FerroEHR's checker by `Tests/LicenceCoreTests/Vectors`. `Register`: the
  register in memory, drafts, renewals, revocations, key changes and the
  Register check. `Signing`: every GnuPG call and the YubiKey setup steps.
  `GitHubKit`: device-flow sign-in, sync, the recorder (branch, pull request,
  check, merge) and releases. `register-check`: the command CI runs.
- The register is not here. `FerroHEALTH/FerroLICENCE-register` (private)
  holds `keys/` (PUBLIC certificates of the two master keys, the trust
  anchors; `keys/retired/` for certificates no longer trusted), `register/`
  (`<customer>/<licence-id>/` with `licence.asc`, `record.json` (schema 2)
  and, if revoked, `revocation.json`) and `signers.json` (which owner holds
  which master key, and their GitHub login). It runs no CI; its `main`
  ruleset lets only the owners merge, signed, with no force push.
  `FerroLicenceKit/Tests/RegisterSnapshot/` is a fixed copy of those files
  from 2026-10-24, for the tests and the app's fixtures; never refreshed, so
  no customer data comes here.
- `docs/`: design, research, threat model, FerroEHR integration contract,
  releasing, the GitHub App's settings (`github-app.md`).
- The manuals (one per task, following the app's screens) are `manuals/` in
  the private register repository, with the procedures they describe. Keep
  them in step with the code.
- `scripts/checks/`: the guards CI and the git hooks run. `scripts/ui/`:
  the screenshot tour and its contact sheets. `scripts/release/`: the
  release lane's helpers. `scripts/dev/`: regenerates the app's fixtures.
- `scripts/gh/`: the tracker helpers: `fields.sh` (issue type, priority and
  effort), `labels.sh` (the label set) and `rel.sh` (sub-issue and dependency
  edges).
- `.githooks/`: `pre-commit` (secret scan + `swift format lint`) and
  `commit-msg` (attribution strip). Installed by
  `git config core.hooksPath .githooks`.

## Hard rules

- **Secret key material never enters this repository.** Not a master key,
  not the retired first key or its subkey, not a revocation certificate,
  not a PIN or passphrase, not a signing certificate or Sparkle's private
  key, and no customer data: the register stays in its private repository.
  Every `keys/` folder holds `PUBLIC KEY BLOCK` files only.
  `scripts/checks/no-secret-material.sh` refuses the commit and the CI run;
  the Claude `protect_secrets.sh` hook refuses the write. Do not weaken any
  of the three.
- **Two master keys, each generated on its owner's YubiKey.** One per owner
  of Cadasto B.V., Ed25519, certify and sign, no expiry, no backup (each is
  the other's backup), and each signs licences directly. No subkeys, no
  rotation, no offline primary. The owners chose this on 2026-10-07 over the
  per-signer subkey design; do not reintroduce subkeys or a software key.
- **No keyring is ever committed, in either repository.** The
  owner asked for a committed keyring once (2026-10-01) and chose otherwise
  after the trade-offs; do not offer it again.
- **GnuPG does every key operation.** The card generates each master key
  (`gpg --card-edit`, driven by `GnuPG.cardEdit`); listing, export, signing
  and the PIN changes go through `FerroLicenceKit/Sources/Signing/GnuPG.swift`,
  with the exact arguments visible there. Never write key generation or
  signing in Swift; the app and the kit only verify. The one exception is
  `Tests/LicenceCoreTests/Fixture.swift`, which builds the refusal cases
  GnuPG will not produce and is never part of a build. The app never reads a PIN:
  GnuPG asks in its pinentry-mac window.
- **A token is verified with FerroEHR's checks before it is recorded.**
  `licenceChange` refuses a signed file that `verify` would not accept, and
  the Register check (`RegisterCheck.check`) verifies it again in the app,
  against the register's `main` as it is just then, before anything is
  opened on GitHub. Never bypass either. Only `GnuPG.signingKey`, which reads the YubiKey plugged in,
  makes a `SigningKey`.
- **Every write has a check step before it.** Issuing is confirmed by the
  PIN and the touch; revoking by typing `REVOKE`; trusting a new key by
  `TRUST`; stopping a key by `HANDOVER`, `LOST` or `RETIRE`. Cancel or
  Escape before that step writes nothing. Keep it that
  way for every new action.
- **Every change to the register passes the Register check in the app and
  reaches `main` through a pull request, and nothing else.** The app checks
  the change, opens the pull request in `FerroLICENCE-register` and
  squash-merges it at once; there is no review, no CI on the register and
  no local clone (owner, 2026-10-24). A new kind of change gets its rule in
  `RegisterCheck` first.
- **The register is append-only.** A licence folder is written once at
  issue (a revocation once) and never edited. Renewal is a new licence
  with a new id. Revocation never reaches the product: no kill switch, no
  deny-list in FerroEHR (design §1, decision log).
- **The token format and the stamp are FerroEHR's.** The Swift checker must
  agree with FerroEHR's on the vectors; a change to either needs new vectors
  from FerroEHR's checker and a changelog entry that names it.
- **This repository is never referenced from FerroEHR's public tree.** Not
  in code, docs, memory files, comments or commit messages. FerroEHR's side
  stands on its own; the existence of a licensor tool is not the product's
  business.
- **Never weaken, skip or delete a test** to make a build pass.
- **No AI attribution in commits, PRs or issues.** No `Co-authored-by`, no
  "Generated with", no robot emoji. The `commit-msg` hook strips it and the
  Claude Bash hook refuses the command.
- **Every commit is signed** (global `commit.gpgsign` is on). Branches use
  conventional types: `feat/`, `fix/`, `chore/`, `docs/`, `refactor/`,
  `test/`, `ci/`. The app's own branches are `licence/`, `revocation/` and
  `key/`; never use those by hand.
- **Prose has no AI tells**: no em dashes, no "not X but Y", no triads for
  rhythm, no buzzwords. Comments follow RFC 505/1574: one-sentence summary,
  blank line, detail; `// TODO(#N):` names an issue; no essays in code.

## Gates (run before every commit)

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # xcode-select points at the CLT here
swift format lint --strict --recursive FerroLicenceKit FerroLICENCE scripts/ui/contact-sheet.swift scripts/release/verify-update.swift scripts/release/dmg-background.swift
FERROLICENCE_REQUIRE_GPG=1 swift test --package-path FerroLicenceKit     # includes the GnuPG interop tests
xcodebuild test -project FerroLICENCE/FerroLICENCE.xcodeproj -scheme FerroLICENCE -destination 'platform=macOS,arch=arm64'
bash scripts/checks/no-secret-material.sh
actionlint .github/workflows/*.yml
```

The GnuPG interop tests (`FerroLicenceKit/Tests/SigningTests/InteropTests.swift`)
are the proof that GnuPG-signed tokens pass the checker and the Register
check. They use a throwaway GnuPG home under `/tmp` and a software key, and
never touch the developer's keyring; they also prove a software key never
becomes a `SigningKey`. CI sets `FERROLICENCE_REQUIRE_GPG=1` so they can never
silently skip there.

**Every UI change is looked at.** `bash scripts/ui/screenshots.sh [screen…]`
opens the debug app in fixture mode (no network, no YubiKey) once per screen,
light and dark, at the smallest window (860 by 560) and a large one, and saves
every window; `swift scripts/ui/contact-sheet.swift <shots> <out>` tiles them
per screen. Look at every image for overflow, truncation and anything that
reads badly before calling the work done. The in-app camera cannot draw
Liquid Glass (sidebar, toolbar buttons, popovers); the UI tests' screenshots
in CI can.

The app speaks English and Dutch through String Catalogs. After changing
user-facing text, `bash scripts/dev/sync-strings.sh` writes the new keys into
the catalogs; add the Dutch for each before committing, and run the tour in
Dutch too (`.claude/rules/swift.md`, Text and languages).

The UI tests (`FerroLICENCE/FerroLICENCEUITests`) walk the sections in fixture
mode. Locally they need UI automation allowed once:
`sudo automationmodetool enable-automationmode-without-authentication`.

## Toolchain and pins

Xcode 27.1, Swift 6.4, macOS 27, Apple Silicon only (`ARCHS = arm64`), for
development, the app's CI (the `xcode-27` runner image) and releases. The kit is
`swift-tools-version: 6.4` with swift-subprocess 1.0; the app adds Sparkle 2.
Verify any bump against its release notes first.

Everything Swift runs on GitHub's macOS runners, free on a public
repository; the shell-only jobs (the guards, the contribution check, the
release's plan and publish) run on `ubuntu-latest`. Never give this
repository a self-hosted runner: anyone's pull request would run on it.

## Workflow

The tracker is this repository's GitHub Issues. The type (Bug, Feature,
Task), the priority (Urgent, High, Medium, Low) and the effort (High, Medium,
Low) of an issue are GitHub's native issue type and the FerroHEALTH
organisation's `Priority` and `Effort` issue fields, never labels.
`scripts/gh/fields.sh` sets each by issue number (`type`, `priority`,
`effort`, `show`), and `scripts/gh/fields.sh new <type> <priority> <effort>
<gh issue create args>` files an issue with all three, so no issue is filed
with a bare `gh issue create`. Every open issue carries an effort: `Low` is
one sitting, `Medium` one pull request, `High` more than one. A Task carries
exactly one work-kind label (`documentation`, `chore`, `refactor`, `perf`,
`test`, `ci`); a Bug and a Feature carry none. The app labels its own pull
requests `licence`, `revocation` or `key`. `scripts/gh/labels.sh` bootstraps
the label set, and `scripts/gh/rel.sh` sets sub-issue and dependency edges.
Read an issue with `gh issue view <n> --json title,body,comments`, never
`--comments`, which prints nothing for an issue without comments. A code
change lands through a PR on a conventional-type branch (a Bug is `fix/`, a
Feature `feat/`, a Task its work kind); the PR body says what changed and
why. Design decisions go into `docs/design.md` (the decision log at its
end), never into code comments.

## Changelog and releases

- **Every PR with a user-visible change adds a line under `[Unreleased]`**
  in `CHANGELOG.md` (Keep a Changelog 1.1.0). A change to the token format or
  the stamp derivation is named as such in the entry; neither is ever
  silent.
- **Releases are immutable, and so are their tags.** `docs/releasing.md` is
  the procedure: set `MARKETING_VERSION` in `FerroLICENCE/App.xcconfig`, move
  the changelog section, merge, sign the tag, push it. `release.yml` checks
  tag = version = changelog section, signs the app with the Developer ID,
  notarises it, signs the update with Sparkle's key, and publishes a draft
  only after every asset is attached. A bad release is fixed by the next
  patch version, never edited or retagged.
- Run `bash scripts/release/protect-tags.sh` once per repository to create
  the `v*` tag ruleset; release immutability is a one-click repository
  setting the owner turns on.
