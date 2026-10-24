# keys/

Public certificates of the master keys, one `<FINGERPRINT>.asc` per key,
exactly as `gpg --armor --export` writes them: the master key (Ed25519,
certify and sign), its user id and self-signature, and the encryption and
authentication subkeys the YubiKey generated beside it, which play no part
in licensing.

These files are the trust anchors. The app checks every licence against
them, and the product embeds the same files. Two owners, two master keys,
two files; `../signers.json` says whose each one is.

Nothing secret is ever here. Each master key lives on its owner's YubiKey
and cannot leave it. `scripts/checks/no-secret-material.sh` refuses a commit
that would change that.

Written by the last step of the YubiKey setup in the app, on the key
holder's computer (`docs/manuals/02-yubikey.md`); never edited by hand.

`retired/` holds certificates the product no longer trusts: the first key
(`5834C101…`, retired on 2026-10-07) and any key retired after a theft
(`docs/manuals/05-lost-key.md`). Only the top level of `keys/` is trusted,
so a file in `retired/` verifies nothing.
