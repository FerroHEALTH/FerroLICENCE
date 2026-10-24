# Setting up FerroLICENCE, and the end-to-end run

Everything that has to be configured outside the code before the app can
issue a real licence, in the order to do it, followed by the end-to-end run
that proves each part works. An organisation owner of FerroHEALTH does parts
1 to 5 once; each key holder does part 6 on their own Mac.

| Part | What | Who | Where |
|---|---|---|---|
| 1 | Repository settings and labels | organisation owner | GitHub |
| 2 | The FerroLICENCE GitHub App | organisation owner | GitHub |
| 3 | Developer ID certificate and notarisation key | Apple Developer account holder | Apple |
| 4 | Sparkle's update key | an owner | a Mac |
| 5 | The release secrets | organisation owner | GitHub |
| 6 | Each key holder's Mac | each key holder | their Mac |
| 7 | The end-to-end test repository | organisation owner | GitHub |
| 8 | The end-to-end run | both key holders | the app |

## 1. Repository settings and labels

On `FerroHEALTH/FerroLICENCE`, Settings, General:

- **Pull Requests**: Allow squash merging on (the app merges this way);
  Automatically delete head branches on. Both are on already.
- **Releases**: Enable release immutability on (`docs/releasing.md`).

Settings, Actions, General: Allow all actions (on already). Workflow
permissions can stay at "Read repository contents"; each workflow asks for
what it needs.

Then, from a clone, with `gh` signed in as an owner:

```bash
bash scripts/gh/labels.sh               # adds licence, revocation and key, which the app uses
bash scripts/release/protect-tags.sh    # the v* tag ruleset
```

Both rulesets are enforced (the organisation is on GitHub Team). The `main`
ruleset requires the **Register check** and `secrets and shell`, no review
(the app merges its own pull requests), signed commits, and no force push or
deletion. The `v*` ruleset
keeps release tags from being moved or deleted. Release immutability is on.

## 2. The FerroLICENCE GitHub App

**Done on 2026-10-24**: the app exists and its client id
(`Iv23lihEWl5vWGdUno3R`) is in `FerroLICENCE/App.xcconfig`. Check that it is
installed on `FerroLICENCE` (and on the test repository of part 7).

Create it with the exact settings in `docs/github-app.md` (Device Flow on;
Contents read and write; Pull requests read and write; Checks read; Metadata
read; no webhook), and install it on `FerroLICENCE` only. Copy its Client ID
into `FerroLICENCE/App.xcconfig`:

```text
FL_GITHUB_CLIENT_ID = Iv23li...
```

and land that through a pull request. The client id is public.

## 3. Apple: Developer ID and notarisation

The app is signed and notarised under Ruben Daniël Talstra's developer team
`A8S2486A44` (owner, 2026-10-24). Needs the Account Holder of that team
(only they can create a Developer ID certificate). Done on 2026-10-24: the
certificate is in Ruben's login keychain.

**Developer ID Application certificate.** Xcode, Settings, Accounts, the
team, Manage Certificates, the + button, Developer ID Application. Then in
Keychain Access, under My Certificates, select "Developer ID Application:
Ruben Daniël Talstra (A8S2486A44)" with its private key, File, Export Items, save as
`developer-id.p12` with a strong password.

**Notarisation key.** App Store Connect, Users and Access, Integrations, App
Store Connect API, Team Keys, the + button, name "FerroLICENCE notarisation",
access Developer. Download the `.p8` (only once possible) and write down the
Key ID and the Issuer ID shown above the list.

No App ID, provisioning profile or App Store record is needed: the app is
distributed outside the App Store.

## 4. Sparkle's update key

**Done on 2026-10-24**: the key pair was made on Ruben Talstra's Mac; the
public key is in `FerroLICENCE/App.xcconfig`, the private key in the
`SPARKLE_PRIVATE_KEY` secret and in that Mac's login Keychain. The steps
below are for making it again on another Mac.

On an owner's Mac, after opening the project in Xcode once (so the Sparkle
package is downloaded):

```bash
cd ~/Library/Developer/Xcode/DerivedData/FerroLICENCE-*/SourcePackages/artifacts/sparkle/Sparkle/bin
./generate_keys                 # stores the private key in your login Keychain and prints the public key
./generate_keys -x sparkle.key  # exports the private key for the secret in part 5
```

Put the printed public key in `FerroLICENCE/App.xcconfig`:

```text
SPARKLE_PUBLIC_ED_KEY = <the public key generate_keys printed>
```

The private key stays in that Keychain as the backup. If it is lost, the
next release must ship a new public key and people install it from the
`.dmg` once.

## 5. The release secrets

**Done on 2026-10-24**: all six secrets are set (`gh secret list -R
FerroHEALTH/FerroLICENCE`). The notarisation key's `.p8` is kept in a
password manager. To set them again, run the commands below, or the setup
script that checks each file and password before it stores it.

From the folder holding the files of parts 3 and 4:

```bash
R=FerroHEALTH/FerroLICENCE
base64 -i developer-id.p12 | gh secret set DEVELOPER_ID_P12 -R $R
gh secret set DEVELOPER_ID_P12_PASSWORD -R $R          # paste the export password
gh secret set NOTARY_KEY -R $R < AuthKey_XXXXXXXXXX.p8
gh secret set NOTARY_KEY_ID -R $R --body XXXXXXXXXX
gh secret set NOTARY_ISSUER_ID -R $R --body xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
gh secret set SPARKLE_PRIVATE_KEY -R $R < sparkle.key
rm developer-id.p12 sparkle.key                         # keep the .p8 only in a password manager
gh secret list -R $R                                     # six names, no values
```

None of these files ever goes into the repository; the secret scan refuses
them anyway.

## 6. Each key holder's Mac

- macOS 27 on Apple Silicon.
- `brew install gnupg pinentry-mac`. No Xcode, Rust or `ykman` needed.
- Their YubiKey, set up and trusted (both are: `keys/` and `signers.json`).
- Their GitHub login in `signers.json` (`rubentalstra`, `AlessandroTorrisi`).
- The app: from the release `.dmg`, or for the end-to-end run, built from the
  branch (part 7).

To run the UI tests on a Mac, allow UI automation once:
`sudo automationmodetool enable-automationmode-without-authentication`.

## 7. The end-to-end test repository

**Done on 2026-10-24**: `FerroHEALTH/FerroLICENCE-e2e` exists, private, with
the app's labels, and the GitHub App is installed on it. Left: copy `main`
into it once PR #38 is merged (the `git push` below).

The run signs real licences and merges real pull requests. The register is
append-only, so the run happens in a copy of the register's repository,
never in `FerroLICENCE-register` itself. The copy holds the register's
files (`keys/`, `signers.json`, `register/`) and the same `main` ruleset;
like the register, it runs no CI.

```bash
gh repo create FerroHEALTH/FerroLICENCE-e2e --private --description "End-to-end runs of the FerroLICENCE app"
git push git@github.com:FerroHEALTH/FerroLICENCE-e2e.git main:main     # after PR #38 is merged
GH_REPO=FerroHEALTH/FerroLICENCE-e2e bash scripts/gh/labels.sh
```

On the GitHub App's page, Install App, FerroHEALTH, Configure, add
`FerroLICENCE-e2e` to the selected repositories. The app runs the same
Register check on the copy as on the real register.

Build the app against the copy, from a clone of the branch:

```bash
xcodebuild -project FerroLICENCE/FerroLICENCE.xcodeproj -scheme FerroLICENCE -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/e2e \
  FL_REPOSITORY=FerroHEALTH/FerroLICENCE-e2e FL_GITHUB_CLIENT_ID=Iv23li... \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
open build/e2e/Build/Products/Release/FerroLICENCE.app
```

## 8. The end-to-end run

Each step names what it proves. Note anything that differs and file it.

| # | Step | Proves |
|---|---|---|
| 1 | Open the app, Sign In with GitHub, Copy Code and Open GitHub, approve | the device flow and the Keychain token |
| 2 | Ready to Issue shows every row green, then Continue | GnuPG, pinentry-mac, the card, the sync, `signers.json` logins |
| 3 | New Licence: customer "E2E Test B.V.", one day, contract "E2E-1", Continue | the draft |
| 4 | Check Before Signing, open Exact text the YubiKey signs, Sign with YubiKey | the canonical text |
| 5 | Type the PIN in the pinentry window, touch the key | signing on the card, PIN on every signature, touch policy |
| 6 | Watch Recording: pull request opened, merged | the Register check in the app, the recorder, the squash merge as you |
| 7 | On GitHub: the pull request is merged and labelled `licence`, the branch deleted, the merge commit on `main` shows Verified | the audit record |
| 8 | Licence Recorded, Download to Downloads; then Copy Setup Instructions | `licence.asc` lands in Downloads (a second click makes `… 2.licence.asc`); the setup text is on the pasteboard |
| 9 | Check a File, drop that `licence.asc` | the checker on a real file: Valid, Signed by you, in the register |
| 10 | Revoke it: reason "End-to-end run", type REVOKE, Revoke | a revocation through the same pull request flow |
| 11 | Activity shows the licence and the revocation with their pull requests | sync of merged pull requests |
| 12 | Sign a second licence and type a wrong PIN once, then Cancel | "Wrong PIN. 2 tries left." from the card's counter |
| 13 | The other key holder signs in on their Mac and sees both entries; they issue and revoke one of their own | two owners, two cards, one register |
| 14 | On GitHub, try to push a commit straight to `main` of the copy | the ruleset refuses it |
| 15 | Settings, General, Sign Out; sign in again | sign-out removes the token and the offline copy |

**Releases and updates.** Once parts 2 to 5 are done and PR #38 is merged,
cut a test version on the real repository: `MARKETING_VERSION = 0.2.0`, an
`[Unreleased]` changelog section, then `git tag -s v0.2.0-beta.1` and push
it. `release.yml` signs, notarises and publishes it as a pre-release.
Install the `.dmg`, turn on Include test versions (Settings, Updates), tag
`v0.2.0-beta.2`, and choose FerroLICENCE, Check for Updates…: the update
window offers it, installs it and relaunches. That proves the Developer ID
signature, notarisation, the EdDSA signature, the beta channel and the
private-repository download in one go. With Include test versions off,
Check for Updates… offers nothing for a beta. If an update does not arrive,
Console.app shows Sparkle's log (filter on `Sparkle`), and the release run's
step "the update verifies with the key inside the app" says whether the key
in the app and the signing key belong together. How the updater is set up,
and why it differs from Sparkle's defaults, is in `docs/releasing.md`.

When everything holds, the copy can be archived (Settings, Archive this
repository); its register is test data and is never merged back.
