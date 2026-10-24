# Research record

What was read before the design was fixed (2026-09-11), what it said, and
what was taken from it. Every claim here has its source beside it; where a
source was read first-hand it says so.

## 1. Licence token formats in commercial practice

**Keygen** (licensing SaaS; docs read first-hand). License files are
base64 certificates with a JSON payload of `enc` (data), `sig` (signature)
and `alg`; license keys are `{prefix}/{base64url(data)}.{base64url(sig)}`.
Signing schemes offered: Ed25519, ECDSA P-256, RSA-2048 PSS and PKCS#1
v1.5. Their recommendation: "Ed25519, due to its smaller signature size and
higher security level when compared to 2048-bit RSA." Expiry is in the
payload (`issued`, `expiry`, `ttl`) and checked by the client clock;
encryption (AES-256-GCM) is optional. Keys are immutable: a change is a new
key.
Sources: <https://keygen.sh/docs/api/cryptography/>,
<https://keygen.sh/docs/choosing-a-licensing-model/offline-licenses/>.

**license-guard-rs** (Rust, Ed25519 offline licences; README read
first-hand, cited as prior art only, not a dependency). Public key hardcoded
as hex in the binary, licence carries subject, entitlements, expiry; the
README states plainly that "an attacker with write access to the binary can
bypass checks". Source: <https://github.com/sassman/license-guard-rs>.

**Taken:** signed JSON with issued/not-before/not-after, Ed25519, verified
offline with an embedded public key, immutable tokens. **Departed from:**
the envelope is OpenPGP rather than a bespoke `data.sig` string, because the
product already carries rPGP and OpenPGP supplies key flags, expiry and
certificate transport (design §6, §11). The licensor side first verified with
rPGP too; since 2026-10-24 it verifies with its own Swift reader on CryptoKit
in `FerroLicenceKit/LicenceCore`, which must agree with FerroEHR's checker on
the shared test vectors (design §12).

## 2. OpenPGP key hierarchy and rotation

**RFC 9580** (OpenPGP, current standard). Cleartext signature framework
(§7), transferable public keys (§10.1), key flags (§5.2.3.29: certify,
sign), key expiration time subpacket (§5.2.3.13), v4 fingerprints are SHA-1
(§5.5.4). Source: <https://www.rfc-editor.org/rfc/rfc9580.html>.

**Sequoia PGP book, Keys and subkeys.** Keep the primary "stored offline
where no one can have access to it"; use it for certification only;
publish and use subkeys for daily work; rotate subkeys "faster and letting
them expire earlier than the primary key"; do not back up signing subkeys
(a lost signing key costs nothing, past signatures stay valid).
Source: <https://book.sequoia-pgp.org/bckgrnd_key_subkeys.html>.

**IETF draft, OpenPGP Key Replacement** (`draft-ietf-openpgp-replacementkey`).
A Replacement Key subpacket lets a primary announce its successor; verifiers
must still validate the replacement through their own trust path and "MUST
NOT" treat the pointer as a certification. Source:
<https://datatracker.ietf.org/doc/html/draft-ietf-openpgp-replacementkey-06>.

**Taken (2026-09-11):** certify-only offline primary, expiring signing
subkeys, primary rotation by shipping a new anchor in the next product
release (the draft's model without depending on the draft).

**Revised (2026-10-07):** two master keys, each generated on one owner's
YubiKey, each certifying and signing licences itself; no subkeys, no
rotation, no offline primary. The Sequoia advice protects a primary that
lives on a disk and has a single holder. Here each key is created on a
card that cannot export it, so there is nothing to keep offline and no
secret to rotate away from, and a licensor of two people gains nothing
from a hierarchy between them. Two anchors give the redundancy a backup
would: either owner issues if the other's card is lost. Replacing a key
still follows the draft's model: a new anchor in the next product
release.

**GnuPG manual, Agent Options.** `ignore-cache-for-signing` makes the agent
bypass the passphrase cache for every signing operation;
`no-allow-external-cache` stops pinentry from offering an external store
such as the macOS Keychain. Both are listed by `gpgconf --list-options
gpg-agent` on GnuPG 2.5. Source:
<https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html>.

**Yubico, OpenPGP on YubiKey.** The YubiKey 5 series runs the OpenPGP card
application; Ed25519 keys are supported from firmware 5.2.3; touch policy
and signature PIN policy are set per key with `ykman openpgp`, or through
GnuPG itself (`forcesig` and `uif` in `gpg --card-edit`, and the PINs with
`gpg-connect-agent "SCD PASSWD"`), which is how the app sets them since
2026-10-24, so ykman is no longer needed. GnuPG moves
an existing key onto the card with `keytocard`, or generates one on the card
with `gpg --card-edit` and `generate`, in which case the secret never exists
outside it. Source:
<https://developers.yubico.com/PGP/>.

**Apple, Protecting keys with the Secure Enclave.** The Secure Enclave
stores only 256-bit elliptic curve (P-256) private keys, created inside it.
Source:
<https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave>.

**Taken (2026-09-11):** one signing subkey per signer, on a YubiKey 5;
passphrase cache off for signing on every keyring; the Secure Enclave
rejected because our keys are Ed25519 and GnuPG cannot reach it.

**Revised (2026-10-07):** one master key per owner, generated on the
YubiKey 5 itself, with `forcesig` and touch on every signature. The agent
options above matter only for keys on disk, which the design no longer
has. The Secure Enclave stays rejected for the same reason.

## 3. Expiry behaviour in comparable products

**Elastic.** On expiry the cluster reverts to Basic; "all data operations
(read and write) continue to work"; premium features return a licence error.
The former 7-day grace period was removed in favour of clear state
(elastic/elasticsearch PR #67316). Sources:
<https://www.elastic.co/docs/deploy-manage/license/manage-your-license-in-eck>,
<https://github.com/elastic/elasticsearch/pull/67316>.

**HashiCorp Vault Enterprise.** Production licences do not terminate on
expiry; an expired licence blocks starting *newer* binaries, and running
nodes continue. Only evaluation licences seal. Sources:
<https://developer.hashicorp.com/vault/docs/license>,
<https://support.hashicorp.com/hc/en-us/articles/48860621531923-Vault-Enterprise-Licensing-Expiration-Termination-and-What-to-Expect>.

**Keygen, cryptographic license files.** Offline licence files carry a
time-to-live; once it passes, a new file must be checked out. Keygen
recommends an expiry "for eventual consistency, ensuring that changes to the
license state (like updates, renewals, or suspensions) are reflected in
subsequent license files". An offline file cannot be withdrawn; the next one
is simply not issued. Source: <https://keygen.sh/docs/api/cryptography>.

**Taken:** nobody stops a production system on a licence date. FerroEHR
goes further: no behaviour depends on the licence at all (design §1, §9).
Licences run one year by default and are renewed; a licence that must stop
counting earlier is revoked in the register (a write-once
`revocation.json`), which attesting and checking report against, and its
renewal is not issued.

## 4. Database watermarking and fingerprinting

**Agrawal and Kiernan, Watermarking Relational Databases, VLDB 2002** (PDF
read first-hand). A keyed hash of the primary key selects which tuples and
which bits carry a mark; detection recomputes the selection and applies a
significance test against the chance-match rate; the paper's property list
is imperceptibility, robustness to updates and deletions, security without
the key, and low overhead. Source:
<https://www.vldb.org/conf/2002/S05P03.pdf>.

**Li, Swarup, Jajodia, Fingerprinting relational databases, ACM SAC 2006.**
Extends the scheme to embed a multi-bit fingerprint identifying the
recipient, so a leaked copy names its source. Source:
<https://dl.acm.org/doi/10.1145/1141277.1141391>. Survey:
<https://arxiv.org/pdf/1801.08271>.

**Taken:** the whole attestation model (design §8). The identifier's own
timestamp plays the role of the tuple key; the licence id is the
fingerprint; the binomial tail is the significance test.

## 5. UUIDv7 randomness requirements

**RFC 9562** (read first-hand). §5.7: `rand_a` is "12 bits of pseudorandom
data to provide uniqueness … and/or optional constructs to guarantee
additional monotonicity"; `rand_b` is "the final 62 bits of pseudorandom
data to provide uniqueness … and/or an optional counter". §6.9:
implementations "SHOULD utilize a cryptographically secure pseudorandom
number generator". The often-repeated "at least 32 bits must stay random" is
not in the RFC. Source: <https://www.rfc-editor.org/rfc/rfc9562.html>.

**`uuid` crate 1.26, `v7.rs`** (read first-hand). The counter is merged into
the leading bits of the 74; the remainder is `rng::u128()` output, so the
trailing two bytes are always CSPRNG under every counter width.

**Taken:** stamp in the last two bytes; 46 CSPRNG bits remain (design §7).

## 6. BUSL enforcement in practice

**FOSSA on BSL 1.1; MariaDB, HashiCorp, Sentry, CockroachDB.** Enforcement
of the production-use restriction is contractual; the Additional Use Grant
draws the line; no adopter gates production with a technical key. Sources:
<https://fossa.com/blog/business-source-license-requirements-provisions-history/>,
<https://www.hashicorp.com/en/license-faq>, <https://mariadb.com/bsl11/>.

**Taken:** FerroEHR goes one step beyond the field by making production data
self-describing. That is exactly why the mechanism is disclosed and named in
the licence agreement (design §10).

## 7. Transparency obligations

**EU Cyber Resilience Act** (in force 2024-12-10, reporting duties from
2026-09-11). Requires documented security properties, SBOMs, and
transparent documentation of a product's behaviour. A hidden data-marking
mechanism in a clinical product would sit badly against it. Source (summary
read): <https://www.mend.io/blog/eu-cyber-resilience-act-compliance-guide/>.

**Taken:** the product-side module is plainly named and its config key
documented; nothing is disguised (design §10, `ferroehr-integration.md` §6).
