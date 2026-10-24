---
name: two-master-keys
description: "2026-10-07 owner decision: two master keys (Ed25519, cert+sign, no expiry), generated ON two YubiKeys, one for Ruben Talstra and one for Alessandro Torrisi (Cadasto B.V. owners); each signs licences directly; no subkeys, rotation, offline primary or backup; first key 5834… to be retired"
metadata:
  type: project
---

On 2026-10-07 the owner received two YubiKeys and replaced the primary + per-signer-subkey design with two master keys, one per business owner of Cadasto B.V. (Ruben Talstra and Alessandro Torrisi). Each key is generated on the card (`gpg --card-edit`, now driven by the app's YubiKey setup; user id `FerroHEALTH Licensing <licensing@FerroHEALTH.eu>` with no personal name, owner's request; FerroHEALTH is the product family; only `signers.json` maps key to holder), signs licences itself, and is the other's backup. The verifier now refuses subkey-signed tokens (`UnknownSigner`) and certify-only primaries (`NotSigningCapable`); Trusting and signing now happen in the app ([[the-app]]); signing uses the trusted key on the YubiKey plugged in.

Retirement of the first key (ceremony of 2026-09-11, certify-only primary 5834C101…5F712E51 with a software signing subkey): both owners generate and add keys, re-mint the embedded non-commercial token with a master key, `git mv` 5834's cert to `keys/retired/`, ship one FerroEHR release with new core + both anchors + new embedded token. Done on 2026-10-07: grant re-minted (licence 01a1175c-cd67-777d-bdc0-c95bf1c900d3, signed on YubiKey 40729502), 5834 moved to `keys/retired/`, and `.keyring/` destroyed early at the owner's decision ("we will not need it anymore"). FerroEHR side committed on its branch `feat/cra-readiness` (PR #3672). Until that FerroEHR release ships, released builds accept no new licence.

**Why:** the owner wanted the key setup "very very simple"; keys that cannot leave a card make rotation and an offline primary unnecessary, and two anchors give redundancy without a backup copy.

**How to apply:** do not reintroduce subkeys, rotation, a software master key or a committed keyring. The YubiKey steps in the register repository's `manuals/02-yubikey.md` had not been run on a real card when written. GPG Suite was removed from the owner's Mac on 2026-10-07; Homebrew GnuPG 2.5.20 is the only one, and git signs with it (`gpg.program`).
