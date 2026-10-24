# Threat model

No licensing mechanism on source-available software has zero holes. The
standard this design is held to is different and checkable: **every way
around it leaves evidence, and every evidence path has a test.** This file
lists the attempts, what stops each or what it leaves behind, and where the
test lives.

## Assets

- **Trust in a token.** A token accepted by the product must have been issued
  by us.
- **The register.** A recovered stamp must map to exactly one real grant.
- **The stamp's indelibility.** Production data must keep saying how it was
  minted.
- **Secret keys.** Two master keys, one per YubiKey. Compromise of one
  means a FerroEHR release without it and reissuing the licences it
  signed.

## Attempts

| Attempt | What stops it, or what it leaves | Evidence path / test |
|---|---|---|
| Forge a token | Needs the secret of a master key. Ed25519, 128-bit security. Each master key was generated on its owner's YubiKey and cannot leave it. | `RefusalTests.aChangedLicenceIsRefusedAtTheSignature`; vectors `tampered`, `untrusted` (`VectorTests`) |
| Present a token whose licence id is not in the register | The register is ground truth: an unknown id is a forgery by definition. | Attest Data compares only with register entries; an unknown id never matches |
| Swap the bundled certificate for one's own | The primary must equal an embedded anchor byte for byte; a stranger's certificate is `UntrustedPrimary`; a valid signature under a swapped certificate is `UnknownSigner`. | `RefusalTests.aSignatureByAnotherKeyIsRefused`; vector `untrusted` |
| Sign with a subkey of a trusted key | Refused; only the master key itself signs. This also refuses every token the first key's subkey signed. | vector `subkey_signed` |
| Add a second signature to a valid token | Refused; a token carries exactly one signature, so no check can judge a different signature than the one verified. | vector `two_signatures` |
| Present a master key's binary signature over a licence text | Refused; a licence signature must be a text signature, the type `--clearsign` makes. | vector `binary_signature` |
| Bundle an older or altered certificate of a trusted key | Changes nothing; the signing flag and expiry are read from the embedded anchor, and the bundled copy only has to match its primary key packet. | `RefusalTests.signingRightsComeFromTheAnchorNotTheToken` |
| Sign with a key that may not sign | Refused when the master key's newest self-signature lacks the signing flag. | `RefusalTests.aKeyThatMayNotSignIsRefused` |
| Sign with an expired key | Master keys carry no expiry. Should one ever be set, a signature that postdates it is refused; the signing time is the signer's claim, so this stops honest mistakes, not a thief (see the compromise row). | `RefusalTests.aSignatureAfterTheKeyExpiredIsRefused` |
| Company Y runs company X's token | The stamp says X; the database says Y; X's agreement forbids sharing. Evidence against both. | Attest Data names X's licence; the register names X's licensee |
| Keep running after the contract ends | The installation keeps its token until `not_after` (one year by default); the renewal is not issued. The licensor records a revocation, and `attest` counts identifiers minted on or after its effective day. | `RegisterCheckTests.passesARevocationTheAppMakes`; `Attest.Finding.matchedFromRevocation` |
| Run past `not_after` | The product boots unlicensed and stamps the constant from then on; earlier records still carry X's stamp with their timestamps. | Attest Data notes how many were made after the licence ended |
| Set the clock back | Defeats the window check and corrupts the operator's own audit trail and version ordering. Every offline licensing scheme accepts this; only an online check closes it and that is a non-goal. | documented boundary |
| Supply client-side ids to avoid the stamp | Only server-minted ids are stamped; a database with mostly client-supplied ids is itself unusual for FerroEHR. `attest` reports the sampled fraction. | the attestation report: identifiers read against version 7 identifiers sampled |
| Patch the stamp out of the source | Cannot be prevented on source-available software. Absence of any valid stamp on a FerroEHR-shaped database proves an altered build. Release images are Sigstore-signed, so an unmodified deployment can prove provenance and an altered one cannot. | Attest Data finds no licence; product-side mutation test (integration §5) |
| Rewrite identifiers after the fact | Breaks every version uid, contribution and audit reference; openEHR identity is the uid. Practically destroys the database. | structural |
| Run a release older than the stamp | Releases up to v4.0.17 are MIT; nothing to enforce. | n/a |
| A YubiKey is stolen | The key cannot be exported from the card. Every signature needs the PIN (three wrong tries block it) and a touch. Without the PIN the card signs nothing. | `manuals/02-yubikey.md`; `manuals/05-lost-key.md` |
| A key holder's GitHub account is taken over | It cannot make a licence FerroEHR accepts: that needs the holder's YubiKey, PIN and touch. The register's repository runs no CI (owners, 2026-10-24), so the Register check runs only in the app; an account used outside the app can merge anything into the register, including an edited or removed file or a key change. FerroEHR still verifies every licence against its own anchors, so an unsigned or edited licence file is worthless, and the app's Check flags it; the other owner sees the merged pull request in Activity and the history keeps it. Accepted risk. | `RegisterCheckTests.aRevocationComesFromAnActiveKeyHolder`; `InteropTests` |
| Someone records a licence under another owner's name | Refused in the app: the account recording it must be the GitHub login `signers.json` gives the key that signed. Outside the app, see the taken-over account above. | `InteropTests.aLicenceSignedByGnuPGIsRecordedAndPassesTheRegisterCheck`; `register-check` |
| A laptop is stolen | No master key secret is on it: the keyring holds only a stub pointing at the card. The first key's software keyring was destroyed on 2026-10-07. | `manuals/02-yubikey.md` |
| A YubiKey is lost | Its licences stay valid; the other owner keeps issuing; a new key is generated and trusted from the next release. There is no backup to lose either. | `manuals/05-lost-key.md` |
| A master key is compromised (card and PIN) | Forged tokens verify until a FerroEHR release drops the anchor: the verifier does not consult revocations, and the forger can backdate. The register still exposes them as unknown ids. That key's genuine licences are reissued with the other key. | `manuals/05-lost-key.md` |
| One owner issues without the other | Allowed: either owner issues alone. Every licence reaches the register through a pull request the app merges after its Register check passes; the record names the key that signed it, and `signers.json` names that key's holder; the merged pull request is the audit record. A token outside the register is a forgery by definition. | `Record.signer`; `signers.json`; Activity |
| A keyring is committed to the repository | Refused by `.gitignore`, by the secret scan (any file inside a keyring directory, GnuPG's own key format) in the pre-commit hook and CI, and by the Claude hooks. | `scripts/checks/no-secret-material.sh` |
| Someone signs from an unlocked laptop | The YubiKey forces the PIN and a touch on every signature, and it is not left in the laptop. | `manuals/02-yubikey.md` |
| Tamper with the register | Its own private repository, which only the owners can write; its `main` ruleset takes only pull requests and signed commits, no force push. The app runs the Register check before every change: it refuses a changed or removed register file, a record that does not match its licence file, and a key change other than adding a key or changing a status. There is no check on GitHub itself (owners, 2026-10-24): a change made outside the app is caught only by reading, where every `licence.asc` is checked against its record's hash, and by the git history. | `RegisterCheckTests`; `Integrity` |
| Malformed token crashes the product at boot | FerroEHR's own parser is fuzzed in FerroEHR. Here every refusal is typed (`Token.Failure`, `Licence.Failure`, `VerifyError`) and boot never fails on a token. | vectors `bad_date`, `unknown_field`, `no_certificate`; `CoreTests.licencesAreReadStrictly` |
| Statistical false positive in attestation | 2⁻¹⁶ per id; the threshold is 10⁻⁹; a verdict needs a sample, and the report prints n and p. | `VectorTests` (tail values from the Rust checker) |

## What this does not do

It does not stop anyone. It makes every unlicensed production deployment
self-documenting, and every licensed one attributable to its grant. That is
the ceiling for source-available software, and it is above what BUSL
adopters in the field operate with (`research.md` §6).
