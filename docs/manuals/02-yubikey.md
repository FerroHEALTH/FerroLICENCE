# 02. Set up your YubiKey

For each of the two owners, on their own Mac, with their own YubiKey. Once
per YubiKey. About fifteen minutes. Needs `01-install.md` done, GnuPG and
pinentry-mac included.

The master key is created inside the YubiKey and can never leave it. There
is no backup and no file to protect. If the key is lost, the other owner's
key keeps issuing (`05-lost-key.md`). Licences are signed with this key
directly, after your PIN and a touch of the key.

## Which YubiKey

A **YubiKey 5** series key; `00-what-to-buy.md` names the model (YubiKey 5C
NFC) and why. Ed25519 keys need firmware 5.2.3 or newer; every YubiKey 5
sold today has it. Older YubiKey 4 and NEO keys and the blue "Security Key"
series do not work. The Mac's Secure Enclave cannot be used: it holds P-256
keys only, and GnuPG cannot reach it.

A key that was used before must start empty (see "A card to wipe" below).

## In the app

1. Plug in only the new YubiKey.
2. Open **Keys** in the sidebar and click **Set Up a YubiKey…** in the
   toolbar (also in the Keys menu). The **Set Up a YubiKey** window
   opens with seven steps.
3. The first step not yet done is shown below the list with what it does.
   Click its button: **Check the YubiKey** for the first step, **Run This
   Step** for the next five, and for the last **Record the Key** if you
   already hold a key, or **Save the Key for an Owner** if you do not.
4. Repeat until every step has a green tick.

You can close the window at any point and come back later. Every step is
read back from the YubiKey, so the window resumes where you stopped.
**Check Again** reads the card again.

| Step | What happens | Who asks for PINs |
|---|---|---|
| Check the YubiKey | one YubiKey 5 is plugged in, with no key on it yet | nobody |
| Ask for PINs in a window | GnuPG asks for PINs in a pinentry-mac window and never keeps one in the macOS Keychain | nobody |
| Change the PINs | a window asks for the current PIN and a new one, then the same for the Admin PIN | pinentry windows |
| Ask for the PIN on every signature | after this the card asks for the PIN for every licence | a window, the Admin PIN once |
| Create the key on the YubiKey | GnuPG creates an Ed25519 key on the YubiKey: no expiry, no copy anywhere else, user id `FerroHEALTH Licensing <licensing@FerroHEALTH.eu>` | windows: the Admin PIN several times, the PIN once; each window is a separate step |
| Require a touch for every signature | after this every licence needs a touch on the YubiKey | a window, the Admin PIN once |
| Add the key to the trusted keys | type your full name as **Holder**; a key holder's app records the public key in `keys/` and you in `signers.json` through a pull request; anyone else's saves it as a file for an owner (below) | nobody |

The app never sees a PIN; GnuPG asks for each one in its own window.

- **PIN** (6 to 127 characters): you type it for every licence. The factory
  PIN is `123456`.
- **Admin PIN** (8 or more): only for setup and to unblock the PIN. The
  factory Admin PIN is `12345678`. Write it down and keep it somewhere other
  than where the YubiKey travels.

Three wrong PINs block the PIN; the Admin PIN unblocks it. Three wrong Admin
PINs block the card for good, and only a reset makes it usable again,
without its key (`05-lost-key.md`). Settings › Signing shows the PIN tries
left.

The key's user id names the licensor, never a person; the fingerprint tells
the two owners' keys apart, and `signers.json` says who holds which.

## The last step: recording the key

Only the GitHub account of someone who already holds an active key may
change the keys; the app's Register check refuses anyone else (`../design.md`,
Key holder and GitHub account). So the last step depends on who you are.

**You already hold a key** (a second YubiKey, or one for yourself before
your old one is marked lost). **Record the Key** opens a pull request with
`keys/<FINGERPRINT>.asc` and your row in `signers.json` after the Register
check, and merges it into `main`, like a licence. The window shows
the three steps and the pull request's number. When it is done, the window
says the YubiKey is set up and its key is trusted.

**You hold no key yet** (a new owner, or an owner whose only key is marked
lost). **Save the Key for an Owner** saves `<your-name>.key.json` in
Downloads: your name, your GitHub login, the YubiKey's serial number and
the public key, nothing secret. The window shows the key's fingerprint.

1. Send the file to an owner who holds a key.
2. They choose **Keys › Trust a New Key…** (or Change Keys in the Keys
   toolbar), pick the file, and see your name, login, YubiKey and
   fingerprint.
3. Read the fingerprint out to them, by phone or in person, from your
   window. They compare it with theirs, type `TRUST` and click **Trust
   Key**. The pull request comes from their account.
4. Once it is merged, your app syncs and the last step ticks. From then on
   you sign licences from your own GitHub account.

FerroEHR trusts the key from the first release that embeds the new `keys/`
file. Until then a licence signed with it checks out in the app but not in a
running FerroEHR.

## After the setup, by hand

GnuPG wrote a revocation certificate to
`~/.gnupg/openpgp-revocs.d/<FINGERPRINT>.rev`. Print it and keep the paper
with the Admin PIN, away from the YubiKey. It never goes into the
repository. Then delete the file.

Next: `03-licences.md`.

## If a step stops

The window shows why in red.

**No YubiKey found, or "Card not present".** GnuPG's card daemon and the
Mac's smart-card service can fight over the key. Tell GnuPG to use the
Mac's service, then click **Check Again**:

```bash
echo disable-ccid >> ~/.gnupg/scdaemon.conf
gpgconf --kill scdaemon
```

**"pinentry-mac is not installed".** Run `brew install gnupg pinentry-mac`
and click **Run This Step** again.

**"GnuPG asked something unexpected".** A GnuPG release changed a question
the app answers by name. Nothing more was answered. Tell a contributor, so
the answer table in `FerroLicenceKit/Sources/Signing/GnuPG.swift` learns the
new question.

**PIN blocked.** In Terminal: `gpg --card-edit`, then `admin`, `passwd`,
choose `2` (unblock PIN) and enter the Admin PIN.

## A card to wipe

A YubiKey that held a key before, or one whose Admin PIN is blocked, starts
again from empty. Its key is gone after this. In Terminal:

```bash
gpg --card-edit
```

At the prompt type `admin`, then `factory-reset`, and confirm. Then start
the setup again.
