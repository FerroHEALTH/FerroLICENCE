# Releasing the app

FerroLICENCE is released as a signed, notarised macOS app (Apple Silicon,
macOS 27) attached to an immutable GitHub release. People install the
`.dmg` once; after that the app updates itself from the same releases
through Sparkle (`docs/design.md` §12).

## Versioning

- The **app** follows SemVer: `MARKETING_VERSION` in
  `FerroLICENCE/App.xcconfig`. The build number (`CURRENT_PROJECT_VERSION`)
  is the release run's number plus 100, so it only goes up, also past the
  builds released from the repository before the split (up to 4); Sparkle
  compares build numbers and never installs a lower one.
- The **token format** and the **stamp** are FerroEHR's and are named in the
  changelog when they change (`CHANGELOG.md` preamble).

## What a release holds

A release is titled with its tag alone, such as `v0.2.0` or
`v0.2.0-beta.1`, and its files carry the same version.


| Asset | For |
|---|---|
| `FerroLICENCE-X.Y.Z.dmg` | people installing the app for the first time, or Intune |
| `FerroLICENCE-X.Y.Z.zip` | the updater |
| `appcast.xml` | the update feed: version, build number, minimum macOS, the `.zip`'s size and EdDSA signature, the release notes |
| `FerroLICENCE-X.Y.Z-dSYMs.zip` | the debug symbols, to read a crash report from that build |
| the release attestation | signed by GitHub when the release is published: the tag and each file's SHA-256 |

Every update must carry three signatures: Sparkle's EdDSA signature over the
`.zip`, the Developer ID signature of team `A8S2486A44` (Ruben Daniël Talstra) on the app, and Apple's
notarisation, stapled to the app. An update missing any of them is refused.

## How the updater is set up

The setup follows Sparkle's documentation
(<https://sparkle-project.org/documentation/>), with one difference: the app
finds each release through the GitHub API, so the same code serves a private
repository too.

- **Info.plist** (`FerroLICENCE/FerroLICENCE/Info.plist`): `SUPublicEDKey`
  from `App.xcconfig`; `SUVerifyUpdateBeforeExtraction` on, so the EdDSA
  signature is checked before the archive is unpacked; `SUEnableAutomaticChecks`
  off, because the app runs its own daily check (below); `SUAllowsAutomaticUpdates`
  on, behind the Download and install automatically switch. The app is not
  sandboxed, so none of Sparkle's XPC service keys apply.
- **No `SUFeedURL` and no signed feed.** Sparkle cannot read a private
  repository's release. The app asks GitHub's API for the latest release
  with the signed-in token, downloads `appcast.xml` and the `.zip`, writes a
  local copy of the feed whose enclosure points at the downloaded `.zip`,
  and gives Sparkle that feed (`Updater.feedURLString`). Rewriting the
  enclosure would break a signed feed, so `SURequireSignedFeed` stays off;
  the archive's EdDSA signature, the Developer ID signature and the
  notarisation are all still checked by Sparkle before it installs.
- **Test versions** are on Sparkle's `beta` channel; `allowedChannels` admits
  it only when Include test versions is on.
- **A build without a public key** (one built from source) never offers an
  update.
- **Archives**: the `.zip` is made by `ditto -c -k --sequesterRsrc
  --keepParent`, the `.dmg` is APFS with lzfse (`diskutil image create from
  --format ULFO`) and holds an Applications link, as Sparkle's publishing
  guide asks. It opens as an install window: the app and the Applications
  link on a background `scripts/release/dmg-background.swift` draws (in the
  app's teal, normal and Retina), laid out by Finder in a writable image
  before it is compressed. The app is exported with `xcodebuild -exportArchive` for
  Developer ID, so Sparkle's own helpers are signed with it.
- **The feed** is written by Sparkle's `generate_appcast`, with the private
  key on stdin (`--ed-key-file -`), the release notes embedded, and the
  download prefix of the release. `scripts/release/verify-update.swift` then
  checks the `.zip` against the feed's signature and length with the
  public key inside the exported app, so a release whose app carries the
  wrong key, or none, is never published.

## Secrets and settings, once

The release workflow needs these Actions secrets (repository Settings,
Secrets and variables, Actions). None of them ever enters the repository.

| Secret | What |
|---|---|
| `DEVELOPER_ID_P12` | the Developer ID Application certificate and its private key, exported from Keychain Access as `.p12`, base64-encoded |
| `DEVELOPER_ID_P12_PASSWORD` | the password chosen at that export |
| `NOTARY_KEY` | an App Store Connect API key (Users and Access, Integrations, Team Keys, role Developer): the contents of its `.p8` file |
| `NOTARY_KEY_ID` | that key's id |
| `NOTARY_ISSUER_ID` | the issuer id shown above the team keys |
| `SPARKLE_PRIVATE_KEY` | Sparkle's EdDSA private key, as `generate_keys -x` exports it |

Sparkle's key pair is made once, on an owner's Mac, with the tool that comes
with the Sparkle package (Xcode resolves it under the project's
`SourcePackages/artifacts/sparkle/Sparkle/bin/`):

```bash
generate_keys                    # stores the private key in your login Keychain, prints the public key
generate_keys -x sparkle.key     # exports the private key for the secret
gh secret set SPARKLE_PRIVATE_KEY < sparkle.key && rm sparkle.key
```

The private key stays in that owner's login Keychain as the only copy that
can be read back (an Actions secret cannot). With
`SUVerifyUpdateBeforeExtraction` on, a lost key cannot be rotated through an
update `.zip`: the next release ships a new public key and everyone installs
that one `.dmg` by hand.

Put the printed public key in `SPARKLE_PUBLIC_ED_KEY` in
`FerroLICENCE/App.xcconfig`, and the GitHub App's client id in
`FL_GITHUB_CLIENT_ID` (`docs/github-app.md`). `check-version.sh` refuses a
release while either is empty.

## Immutability

Two settings make a release final:

1. **Release immutability** (repository Settings, General, Releases): once
   published, a release's tag and assets cannot change. The lane therefore
   creates a *draft*, attaches everything, checks every asset and its
   checksum, and publishes last. A bad cut is fixed by the next patch
   version, never by editing.
2. **The tag ruleset** (`v*`): tags cannot be deleted or moved. Set once
   through the repository rulesets; `scripts/release/protect-tags.sh`
   creates it idempotently.

Both are on (2026-10-24): FerroHEALTH is on GitHub Team, so the `v*`
ruleset and the `main` ruleset are enforced, and release immutability is
enabled for the repository.

## Cutting a release

On a `release/vX.Y.Z` branch:

1. Move the `[Unreleased]` entries under `## [X.Y.Z] - YYYY-MM-DD`, re-add an
   empty `[Unreleased]`, update the link references at the bottom.
2. Set `MARKETING_VERSION = X.Y.Z` in `FerroLICENCE/App.xcconfig`.
3. Run every gate (`CLAUDE.md` §Gates), the screenshot tour, and
   `bash scripts/release/check-version.sh vX.Y.Z`.
4. Merge the PR. Tag the merge commit and push the tag:

   ```bash
   git tag -s vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   ```

5. `.github/workflows/release.yml` runs on the Apple Silicon `xcode-27`
   image: `plan` (tag = version, changelog section, build settings),
   `build` (archive, Developer ID signature, notarisation and stapling,
   `.dmg`, `.zip` and symbols, the signed `appcast.xml` and its check
   against the app's key, no cache), `publish` (a draft with all four
   assets, then published, then every file checked against GitHub's
   attestation). Watch it with `gh run watch`.

A test version is a tag `vX.Y.Z-beta.N` on the release branch before the
final tag, with `MARKETING_VERSION` already at `X.Y.Z`. The same lane builds
it, takes its notes from `[Unreleased]`, and publishes it as a GitHub
pre-release; only people who turned on Include test versions (Settings,
Updates) are offered it. Its build number is lower than the final
release's, so the final release replaces it.

## Installing

Download `FerroLICENCE-X.Y.Z.dmg` from the release page, check it against GitHub's release
attestation if you like (`gh release verify-asset vX.Y.Z
FerroLICENCE-X.Y.Z.dmg -R FerroHEALTH/FerroLICENCE`), open it and drag
FerroLICENCE to Applications. For managed Macs, Intune can push the same `.dmg`. After the
first install, the app finds new releases itself (FerroLICENCE, Check for
Updates…).
