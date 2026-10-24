# The FerroLICENCE GitHub App

The app signs people in through a GitHub App that belongs to the FerroHEALTH
organisation and is installed on two repositories: the register's
(`FerroLICENCE-register`, which the app reads and writes) and this one
(whose releases the app updates from). An organisation owner
creates it once with the settings below. The device flow needs no client
secret, so nothing secret goes into the app.

## Create it

Organisation settings, Developer settings, GitHub Apps, New GitHub App:

| Field | Value |
|---|---|
| GitHub App name | FerroLICENCE |
| Homepage URL | `https://github.com/FerroHEALTH/FerroLICENCE` |
| Callback URL | none |
| Expire user authorization tokens | on (tokens last 8 hours and renew themselves for 6 months) |
| Request user authorization (OAuth) during installation | off |
| Enable Device Flow | **on** |
| Webhook | off (Active unticked) |
| Where can this GitHub App be installed? | Only on this account |

Repository permissions, and nothing else:

| Permission | Access | Why |
|---|---|---|
| Contents | Read and write | read the register and keys; blobs, trees, commits and branches for a change; squash merge; delete the branch; read releases for updates |
| Pull requests | Read and write | open the pull request, label it, merge it, list merged ones for Activity |
| Metadata | Read-only | required by GitHub |

No organisation or account permissions.

## Install it

On the new app's page, Install App, FerroHEALTH, **Only select
repositories**, FerroLICENCE-register and FerroLICENCE.

## Give the app its client id

Copy the **Client ID** from the app's General page (it starts with `Iv`) into
`FerroLICENCE/App.xcconfig`:

```text
FL_GITHUB_CLIENT_ID = Iv23li...
```

and land it through a pull request. The client id is public; it identifies
the app and grants nothing by itself.

## What a token can do

A token the app gets is a user-to-server token: it acts as the person who
signed in, limited to what both that person and the GitHub App may do on
the register's repository. A person without write access can sign in and use Check,
Attest and Activity, but cannot open pull requests. Only a person whose
GitHub login is in `signers.json` and whose YubiKey holds a trusted key can
issue a licence.

The token lives in the login Keychain of the Mac it was issued on. Signing
out (Settings, General) deletes it and the offline copy of the register. To
cut a Mac off, revoke the person's authorisation in their GitHub settings, or
suspend the app's installation.
