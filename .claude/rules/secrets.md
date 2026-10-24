# Secret material

What is secret: each master key's secret (it never leaves its YubiKey), the
retired first key and its subkey (destroyed with `.keyring/` on 2026-10-07),
every revocation certificate, and every PIN, Admin PIN and passphrase.
What is not: the public certificates (`keys/*.asc`, `keys/retired/*.asc`, in
the register's repository and in `FerroLicenceKit/Tests/RegisterSnapshot/`),
`signers.json`, every issued licence, every register record, every
fingerprint.

## Where the secrets live

- Each **master key** is generated on its owner's YubiKey and cannot be
  exported from it. Two owners, two cards, two keys. There is no backup:
  each key is the other's backup (`docs/design.md` §6). The owner's
  `~/.gnupg` holds only a stub that points at the card.
- The **revocation certificate** GnuPG writes at generation
  (`~/.gnupg/openpgp-revocs.d/<FINGERPRINT>.rev`) is printed and kept with
  the Admin PIN, away from the card.
- The **retired first key** (`5834C101…`) and its subkey lived in the
  git-ignored `.keyring/`, destroyed on 2026-10-07. `.gitignore` still
  refuses that directory and the secret scan still refuses a forced add, in
  case one is ever made again.
- **No keyring is ever committed**, whole or in part, however private the
  repository. A committed keyring is in every clone and every backup for
  good; removing it later does not withdraw it.

## What the tooling never does

- It never reads secret material into the app. `Signing/GnuPG.swift` calls
  `gpg`, `gpgconf` and `gpg-connect-agent` and consumes public exports, colon
  listings, the card status, status lines and armored signatures only.
- It never reads a PIN. GnuPG asks in its pinentry-mac window, for signing
  and for every setup step.
- It never exports a secret key, and a card key cannot be exported at all.
  The Claude Bash hook refuses secret-key export and deletion in a session.
- It never signs with, or trusts, a key on disk. Trusting a key (the last
  setup step) takes the fingerprint from the card plugged in, and only
  `GnuPG.signingKey`, which reads the YubiKey plugged in, makes a
  `SigningKey`. The only path that signs with a software key
  (`SigningKey.softwareForTests`, with a loopback passphrase) is compiled
  into debug builds alone, for the tests' throwaway keyring.
- Release signing secrets (the Developer ID certificate, the notarisation
  key, Sparkle's private key) live only in the repository's Actions secrets
  (`docs/releasing.md`), never in a file in the tree.

## Enforcement

- `scripts/checks/no-secret-material.sh` scans every tracked file (CI) and
  the index (`.githooks/pre-commit`) for armored private key blocks and for
  GnuPG's own key-file format, refuses any file inside a GnuPG keyring
  directory (`.keyring/`, `private-keys-v1.d/`, `openpgp-revocs.d/`), and
  refuses any `.asc` in a `keys/` folder that is not a `PUBLIC KEY BLOCK`.
- `.claude/hooks/protect_secrets.sh` refuses a Write/Edit whose content
  carries a private key block, or that puts anything but a public
  certificate under `keys/`.
- `.gitignore` refuses the common secret-file shapes as a backstop.

Three layers because the cost of one slip is a new primary and the reissue
of every licence.