# 01. Install the app

For everyone who issues or checks licences. Once per Mac. About ten
minutes. The app needs macOS 27 on a Mac with Apple silicon.

## What you install

| What | Why |
|---|---|
| FerroLICENCE | the app: customers, licences, checks, attestation, keys |
| GnuPG | does every key operation: reads the YubiKey, creates the key on it, signs |
| pinentry-mac | the window in which GnuPG asks for your PIN |

Nothing else. The app reads the register from GitHub, so there is no clone
and no terminal work after this page. People who only check licences and
attest data can skip GnuPG.

## 1. GnuPG and its PIN window

Install [Homebrew](https://brew.sh) if the Mac does not have it, then in
Terminal:

```bash
brew install gnupg pinentry-mac
```

If GPG Suite (MacGPG) is also installed, remove it: two GnuPGs fight over
the YubiKey.

## 2. The app

1. Open the latest release on
   <https://github.com/FerroHEALTH/FerroLICENCE/releases> and download
   `FerroLICENCE-<version>.dmg`. Where the Mac is managed by Intune, the app
   arrives through Intune instead; skip to step 3.
2. Open the `.dmg` and drag FerroLICENCE to Applications.
3. Open FerroLICENCE from Applications.

The app is signed with Ruben Daniël Talstra's Developer ID and notarised by Apple, so
macOS opens it without a warning.

## 3. Sign in with GitHub

The app opens on **Sign in with GitHub**.

1. Click **Sign In with GitHub**. A code appears, such as `WDJB-MJHT`.
2. Click **Copy Code and Open GitHub**. GitHub opens in your browser at
   github.com/login/device.
3. Paste the code there and approve FerroLICENCE.
4. Go back to the app. It notices the approval by itself and continues.

The code works for fifteen minutes. The sign-in lasts six months; the token
stays in your login Keychain. Settings › General shows the account and has
**Sign Out**.

The app speaks English and Dutch and follows the language of macOS. To pick
one for FerroLICENCE alone, choose it under Settings › General › Language;
it applies the next time the app opens.

## 4. Ready to Issue

After signing in the app shows **Ready to Issue**, a list of what signing
needs, each with a green tick or an orange warning:

| Row | When it is green |
|---|---|
| Signed in as … | your GitHub login is a key holder in `signers.json` |
| Can open pull requests | your account may push to FerroHEALTH/FerroLICENCE-register |
| GnuPG … and pinentry-mac | both are installed; otherwise **Copy Command** copies the `brew` line above |
| YubiKey … holds your key | your YubiKey is plugged in and holds your trusted key |
| Register synced | the app has read `main` |

Click **Continue**. Without a YubiKey, or for someone who holds no key,
Check a File, Attest Data and Activity still work; only signing waits.
**Check Again** reads everything again. The list comes back at launch
whenever something is missing.

A new owner has no key yet, so the YubiKey row stays orange until
`02-yubikey.md` is done.

## Updates

The app updates itself from FerroLICENCE's GitHub releases. When a new
version exists, the sync popover in the toolbar says so and **Update…**
opens the update window; FerroLICENCE › **Check for Updates…** asks at any
time. Settings › Updates holds the switches: check automatically, download
and install automatically, and include test versions (releases marked as
pre-release). An update is installed only when its signatures check out.

## Next

- Owners: `02-yubikey.md`, with your own YubiKey.
- Everyone else: done. `04-check-and-attest.md` covers what you can do.
- Contributors who change the app itself: the repository's `README.md`.
