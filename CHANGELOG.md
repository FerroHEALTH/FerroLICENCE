# Changelog

All notable changes to the `ferrolicence` tooling are recorded here. The
format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/)
and the tooling follows [Semantic Versioning](https://semver.org/).

Two things are versioned independently of the tooling and are called out
when they change:

- the **token format** (`ferrolicence-core::licence`, `::token`): a change
  that an older product verifier would refuse is a format major bump and is
  named in the entry;
- the **stamp** (`ferrolicence-core::stamp`): the key derivation prefixes end
  in `/v1`; a change there is named in the entry and never silent, because
  every identifier already minted keeps the old stamp.

## [Unreleased]

### Added

- **The FerroLICENCE app for macOS.** A native app (SwiftUI, macOS 27,
  Apple Silicon) replaces the command line: sign in with GitHub, then
  Customers (who needs attention, every customer, renew, send, revoke),
  Activity (every merged change, linked to its pull request), Check a File,
  Attest Data and Keys (the YubiKey in this Mac, Trust a New Key, Stop
  Using a Key, and Set Up a YubiKey in seven resumable steps, all done by
  GnuPG). Every write still has its check step: the PIN and a touch to
  issue, `REVOKE` to revoke, `TRUST` to trust a key, `HANDOVER`, `LOST` or
  `RETIRE` to stop using one.
- **No clone, no git commands.** The app reads the register through the
  GitHub API with the FerroLICENCE GitHub App (`docs/github-app.md`) and
  records each licence, revocation or key change as a pull request. The
  Register check, a GitHub Actions job built from `main`, judges the pull
  request; when it passes the app squash-merges it, and when it fails the
  pull request is closed and nothing reaches `main`. The register is kept
  offline on the Mac for Check and Attest.
- **Updates from GitHub releases** through Sparkle, signed with EdDSA and
  a Developer ID and notarised. Test versions come only to those
  who turn them on, on Sparkle's beta channel. The update's signature is
  checked before it is unpacked, and every release is checked against the
  key inside its own app before it is published. Each release carries its
  debug symbols.
- **Download to Downloads** saves a licence file straight into the
  Downloads folder, ready to attach to a mail; Copy Setup Instructions
  copies the text for the customer's IT.
- `signers.json` gains each holder's GitHub login, so the app knows who is
  signed in. The Register check binds each change to it: a licence is
  recorded only from the GitHub account of the holder whose key signed it,
  a revocation or key change only from an active key holder's account, and
  a push by anyone but the pull request's author fails.
- **Trust a New Key…** (Keys menu, and Change Keys in Keys): a new owner's
  Set Up a YubiKey saves their key as a file, and an owner records it from
  their own account after comparing the fingerprint. Handing over is that,
  then marking the old key handed over (`handed-over` in `signers.json`): it
  stays trusted, its licences keep working, and it signs nothing new.
- **English and Dutch.** The app follows the language of macOS, or the one
  chosen in Settings, General, Language. Dates and numbers follow the
  reader's language; what goes to GitHub stays English.
- Renewal: a licence can name the licence it renews, and the form for a
  renewal starts the day after the current licence ends.
- A contract reference per licence, kept in the register and never in the
  token.

- `scripts/issue-licence.sh`: issue a licence by answering questions one at
  a time. It shows a summary, waits for `yes`, then runs `ferrolicence
  issue`, so signing, the self-check and the register write are unchanged.
  Its delivery copy goes to the git-ignored `deliveries/`.
- Two master keys, one per owner of Cadasto B.V., each generated on its
  owner's YubiKey 5 (Ed25519, certify and sign, no expiry, no backup: each
  is the other's backup). Each signs licences directly. `ferrolicence
  add-key <FINGERPRINT>` exports a master key's public certificate to
  `keys/` from its holder's keyring. `docs/manuals/` holds the step-by-step
  manuals (what to buy, install, generate the key on the YubiKey, issue, a
  lost key, revoke a licence, retire the first key), and `docs/signers.md`
  maps each key to its holder.

- `ferrolicence revoke <licence-id> --reason ... [--effective <day>]`
  records, once, that a licence no longer counts, as
  `<id>.revoked.json` beside it in the register. The product never sees it.
  `attest` reports identifiers minted on or after the effective day, and
  `inspect` ends with a `register:` line (issued, revoked, or not in this
  register). Manual: `docs/manuals/05-revoke-licence.md`. The core's
  attestation `Candidate` and `Finding` gain `revoked_from` and
  `matched_from_revocation`; the token format and the stamp are unchanged.

- `docs/manuals/00-what-to-buy.md`: which YubiKey to buy (YubiKey 5C NFC,
  or 5 NFC for USB-A), how many, where, and what not to buy, with Yubico's
  prices of 2026-10-01.

- **An install window.** The `.dmg` opens as a designed window: the app on
  the left, Applications on the right, an arrow between them, and the
  instruction in English and Dutch, on the app's teal.

### Changed

- **The register has its own private repository.** FerroLICENCE is now
  public under the Business Source License 1.1; the register, the keys and
  `signers.json` live in the private `FerroHEALTH/FerroLICENCE-register`,
  which the app reads and writes. Updates still come from FerroLICENCE's
  releases.
- **The Register check runs in the app.** Before it opens a pull request,
  the app checks the change against the register's `main` as it is just
  then; when it refuses, nothing is opened and the sheet says why. The
  register's repository runs no CI, and the app merges at once, so a
  licence is recorded in seconds. The step "Register check running on
  GitHub" is gone from the Recording lines.
- **Register layout, breaking:** `register/<customer>/<licence-id>/` with
  `licence.asc`, `record.json` and, if revoked, `revocation.json`. Records
  carry `"schema": 2` with `signer` (was `primary`), `token_sha256`, and
  optional `contract` and `renews`; `token_file` and `signing_subkey` are
  gone. The two existing records moved, their licence files byte for byte.
  Loading the register checks every licence file against its hash.
- `signers.json` at the repository root replaces `docs/signers.md`.
- Signing uses the key on the YubiKey plugged in now (`gpg --card-status`),
  when it is trusted, instead of any trusted key whose stub the keyring
  holds.
- The manuals follow the app: install, set up a YubiKey, licences, check and
  attest, a lost key.
- The token format and the stamp are unchanged; `ferrolicence-core` is not
  touched.

- **Token format, breaking:** the verifier accepts a licence only when it
  is signed by the anchor's primary key itself, which must be certified for
  signing. A token signed by a subkey, which every token before this change
  is, is refused (`UnknownSigner`); a certify-only primary is refused
  (`NotSigningCapable`). A token must carry exactly one signature
  (`ExtraSignatures`), and it must be a text signature (`NotTextSignature`). Whether the key may sign and when it expires are read
  from the trusted anchor certificate, never from the copy the token
  bundles; `verify` takes the anchors as certificates (`SignedPublicKey`)
  instead of key packets. The envelope, the licence document and the stamp
  are unchanged. `Verified` reports `signer` and `signer_expires_at` in
  place of `primary`, `signing_subkey` and `subkey_expires_at`. A product
  release must carry this core, the two master keys and a re-minted
  embedded token together (`docs/manuals/06-retire-first-key.md`).
- `ferrolicence issue` signs with the one master key under `keys/` whose
  secret the current keyring holds; `--key <FINGERPRINT>` names one when
  the keyring holds several. `--primary` and `--subkey` are gone, and
  register records carry `primary` only.

- The Licensor and copyright holder is Cadasto B.V., which replaces Vernum
  Projecten B.V. in `NOTICE`, `README.md`, `CONTRIBUTING.md` and the SPDX
  headers. The licence terms, the signing key identity, the token format
  and the stamp are unchanged.
- The repository moved to `FerroHEALTH/FerroLICENCE` (still private); clone
  URLs, the `cargo install --git` line and the changelog links follow. The
  organisation's GitHub Free plan leaves the tag and branch rulesets
  unenforced until it moves to GitHub Team (`docs/releasing.md`).
- `ferrolicence issue --not-after` is optional and defaults to one year:
  the day before the first valid day's anniversary. The guided script
  offers the same default.
- `scripts/checks/no-secret-material.sh` also refuses GnuPG's own key-file
  format and any file inside a GnuPG keyring directory, so a forced
  `git add .keyring` is refused by the pre-commit hook and CI.

- The embedded non-commercial grant is re-minted with master key
  `F2D214FC30698BA65A846B2BF2EA48D4C316406D`: licence
  `01a1175c-cd67-777d-bdc0-c95bf1c900d3`, valid 2026-10-07 to 2099-12-31.
  The first key `5834C101…5F712E51` moves to `keys/retired/`; its grant
  `01a090a8-…` stays in the register and no longer verifies here.
- `docs/design.md` §2 draws the components in Mermaid.

### Removed

- All Rust: the crates, the terminal app, the fuzz targets and cargo-deny.
  The Swift checker agrees with the Rust one on every test vector made
  before it was removed; the token format and the stamp are unchanged.
- `ykman`: GnuPG now changes the PINs and sets the touch policy.
- The subcommands `add-key`, `issue`, `inspect`, `revoke` and `attest`, the
  `--repo` and `--gnupghome` flags and `clap`. The app finds the repository
  from where it starts, or from `FERROLICENCE_REPO`; `GNUPGHOME` still
  applies.
- `scripts/issue-licence.sh` and `scripts/setup-master-key.sh`: the app does
  both.
- `deliveries/`: the customer gets the register's own `licence.asc`.
- `docs/ceremony.md`, `docs/operations.md`, `docs/signers.md` and
  `docs/manuals/06-retire-first-key.md`, folded into the manuals or done.

- `ferrolicence keygen` and `ferrolicence rotate`: a master key is generated
  on its YubiKey with GnuPG and never rotated.
- Any use of a key on disk: `add-key` and `issue` accept a master key only
  when its secret is on a YubiKey. The hidden `--loopback-passphrase` flag
  is gone; the software-key path the GnuPG interop test needs exists only
  in test builds.
- `--gnupghome` no longer defaults to `<repo>/.keyring`; the tooling uses
  GnuPG's own home, where each owner's card stub lives. The old keyring is
  kept only until the first key is retired.

### Fixed

- **Updates install again.** Sparkle accepts only http(s) addresses, so the
  local copy of the feed that 0.2.0-beta.1 and beta.2 handed it was refused
  ("An error occurred in retrieving update information"). The app now gives
  Sparkle GitHub's signed storage links to the feed and the update, which
  need no token; Sparkle never holds the GitHub token. Those two betas cannot
  update themselves: install the next release from its `.dmg` once.
- **The sidebar stays where you put it.** Hiding it in Customers and then
  opening another section brought it back, because each section rebuilds
  its split view; the window now remembers it. View › Hide Sidebar (⌃⌘S)
  is in the menu bar, as in every Mac app with a sidebar.

## [0.1.0] - 2026-09-11

### Added

- The first licensing primary `5834C101A3F48578FD3CD1796C65DDBC5F712E51`
  (certify-only, no expiry; signing subkey
  `5C670D288D16652D9A7193A9F26E27030546EB5F`, valid to 2028-09-10) and the
  embedded non-commercial grant `01a090a8-59e4-76da-92f5-3f7e4ea9d7c0`
  (valid to 2099-12-31), from the ceremony of 2026-09-11.
- `--gnupghome` defaults to `<repo>/.keyring` when that git-ignored directory
  exists, so the ceremony keyring can live beside the working copy without
  ever being committed.
- The licence document carries one of two use classes, `commercial` (a paid
  grant for production use in the course of a business) and `non-commercial`
  (what BUSL-1.1 gives everyone; the grant every product build embeds, minted
  with `issue --use non-commercial`).
- `ferrolicence-core`: the licence document (six fields, canonical JSON), the
  two-block token (cleartext-signed licence plus bundled issuer certificate),
  the verifier (embedded primary → bundled signing subkey → signature →
  validity window, every refusal typed), the 16-bit HMAC-SHA256 identifier
  stamp in the last two bytes of a UUIDv7, and the binomial-tail attestation
  statistics.
- `ferrolicence` CLI: `keygen` (offline certify-only Ed25519 primary plus
  first signing subkey, through GnuPG), `rotate`, `issue` (self-verified with
  the product's verifier before anything is written, appended to the
  register), `inspect`, `attest`.
- `keys/` trust anchors and the append-only `register/`.
- GnuPG interoperability test (GnuPG signs, rPGP verifies) required in CI;
  five cargo-fuzz targets; secret-material guard in pre-commit and CI;
  cargo-deny with adjudicated advisories.
- Design, research, threat model, ceremony, operations and FerroEHR
  integration documents.

### Fixed

- `binomial_upper_tail` accumulated rounding error when summing the large
  tail directly, breaking monotonicity in `k` near 1 (found by the
  `binomial_tail` fuzz target at n = 65535, k = 65500, p ≈ 1 − 5·10⁻⁷). It
  now sums the small tail and derives the other.

[Unreleased]: https://github.com/FerroHEALTH/FerroLICENCE/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/FerroHEALTH/FerroLICENCE/releases/tag/v0.1.0
