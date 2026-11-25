# FerroEHR integration contract

What the product side consists of, what it does, and what it does not do.
This is the specification the FerroEHR change is built to.

## 1. Where the code lives

FerroEHR implements the product side in its own code, with its own checker
(rPGP). This repository has its own implementation of the same checks in
Swift (`FerroLicenceKit/Sources/LicenceCore`), used by the licensor app and
the Register check. Nothing moves between the two repositories (owner,
2026-10-23).

The two implementations are kept in agreement by a shared file of test
vectors (`FerroLicenceKit/Tests/LicenceCoreTests/Vectors`): licences that are
accepted, a refusal at each of the nine checks, stamp values and
attestation tail values. The vectors were generated from the Rust checker
before it was removed from this repository. When FerroEHR's checker changes,
FerroEHR's tests produce a new file and it is copied here; FerroEHR never
names this repository (CLAUDE.md, Hard rules).

The ID 30 vectors (`Vectors/id30`) go the other way: no product checker
answered them first, so this repository wrote them from software test keys
(`writeTheID30Vectors`) with the result each case must get, and FerroEHR's
checker copies the folder and must give the same answers. `ferrohealth-sop`,
the family's ID 30 signer, verifies them too (`SOPInteropTests`). The folder
`Vectors/rfc9980` keeps the RFC 9980 Appendix A.3 sample key and its
detached signature, an oracle neither side wrote. That signature is a
version 6 text signature (type 0x01) over `Testing\n`, so it is hashed as
`Testing\r\n` (RFC 9580 §5.2.4); `Vectors/rfc9980/vectors.json` says so.

## 1a. ID 30 tokens

A master key may be an RFC 9980 algorithm ID 30 key (ML-DSA-65+Ed25519). The
token frame and the licence document stay as they are; the key and the
signature change:

- The key is a version 6 key (RFC 9580 §5.5.2.3, RFC 9980 §3.5). Its
  material is the 32-octet Ed25519 public key followed by the 1952-octet
  ML-DSA-65 public key (RFC 9980 §5.3.2.1). Its fingerprint is SHA-256 over
  `0x9B`, a four-octet length and the body (RFC 9580 §5.5.4.3), 64 hex
  digits under `keys/`.
- The anchor carries a direct key signature (type 0x1F), and the signing
  flag and any expiry are read from its newest one (RFC 9580 §5.2.3.10). An
  anchor without one fails check 2 (`BrokenBindings`).
- The licence signature is a version 6 text signature: the salt of the size
  RFC 9580 Table 23 gives its hash, hashed before the text (§5.2.4), and an
  Issuer Fingerprint subpacket of version 6 (§5.2.3.35). A version 6
  signature that names its issuer only by key id fails check 4 (`NoIssuer`).
  The cleartext frame carries no `Hash:` header (§6.2.2.3).
- The signature is the 64-octet Ed25519 signature followed by the
  3309-octet ML-DSA-65 signature (RFC 9980 §5.3.1). Check 7 verifies both
  over the same digest, PureEdDSA and pure ML-DSA with an empty context
  (§5.1.1, §5.1.2, §5.2.3); either half failing is `BadSignature`.
- A digest under 256 bits is refused at check 7 before any cryptography, as
  `WeakDigest` (RFC 9980 §5.3.1). The signer uses SHA3-256; SHA2-256,
  SHA2-384, SHA2-512 and SHA3-512 verify too.
- A version 4 anchor never accepts a version 6 signature, and the reverse.

The two Ed25519 master keys stay in force until a token can hold ML-DSA-65
(#12). Until then both checkers accept version 4 Ed25519 tokens
and ID 30 tokens alike.

## 2. Configuration

```toml
[licence]
file = "/etc/ferroehr/licence.asc"   # optional
```

Environment form follows the existing grammar: `FERROEHR__LICENCE__FILE`.
Unset means unlicensed. The loader validates the path is readable when set;
a missing file at boot is logged and treated as unlicensed, not a boot
failure.

## 3. Boot

Two string constants in `app/ferroehr/src/licence/mod.rs`, both pasted from
the register's repository after the ceremony (never files, never assets):

- `ANCHOR_CERTIFICATES: &[&str]`: the public certificates of both master
  keys, each `keys/<FINGERPRINT>.asc` verbatim. They are the trust
  anchors as whole certificates: a token's bundled certificate must match
  one by primary key packet, and the anchor's own self-signature decides
  whether the key may sign and when it expires.
- `EMBEDDED_TOKEN: &str`: the `non-commercial` token, signed by a master
  key (the register repository's `manuals/03-licences.md`, §The free licence
  every build embeds).

The verifier accepts a licence that carries exactly one signature, made by
an anchor itself, and refuses one signed by a subkey. Builds that embed the first key
(`5834C101A3F48578FD3CD1796C65DDBC5F712E51`) and its subkey-signed token
keep working, since each verifies its own embedded token with its own
verifier. Moving to the master keys is one FerroEHR release that carries
the core at the new tag, both master key certificates in
`ANCHOR_CERTIFICATES` (the first key dropped) and the re-minted
`EMBEDDED_TOKEN` together: any one of the three without the others fails
`the_embedded_token_verifies_as_non_commercial_when_present`. A later
change of anchors (a new key after a loss, a compromised key dropped) is a
release as well.

```rust
let anchors = ferroehr::licence::anchors()?;       // a parse failure here is a build defect
let licence = LicenceState::load_now(&config.licence, EMBEDDED_TOKEN, &anchors);
tracing::info!(licence = %licence, "licence");     // exactly one line
let service = FerroEhrService::new(pool).with_licence(licence);   // derives the StampKey
```

Precedence inside `load`: a configured `[licence] file` that verifies is in
force (`source: Configured`); one that is unreadable, malformed or refused is
recorded as `configured_failure` and the embedded token is in force
(`source: Embedded`); a build whose embedded token is empty or does not
verify has `NoLicence` and mints with the fail-safe key. The unit test
`the_embedded_token_verifies_as_non_commercial_when_present` keeps that last
state unshippable.

`GET /rest/status` serves the public summary:
`"licence": {"state": "licensed" | "none", "use": "commercial" |
"non-commercial", "licensee": …, "not_after": …, "configured_token":
"absent" | "in-force" | "refused"}`. Never a refusal reason, which can name a
path. Nothing else reads the state.

## 4. Identifier minting

The stamp key is a field on `FerroEhrService`, set by `with_licence` and
threaded into the commit path through `SigningCtx.stamp`. Every server-minted
identifier that reaches the wire goes through it:

| Identifier | Minted by |
|---|---|
| EHR id | `EhrId::minted(service.stamp())` |
| versioned-object id | `VoId::minted(ctx.stamp)` |
| contribution id, when the client supplied none | `ctx.stamp.mint()` (also on the import path) |

The unstamped constructors `EhrId::new()` / `VoId::new()` no longer exist, so
a new minting site cannot bypass the key by accident. `audit` and
`vo_attestation` row ids stay on the database default: they are internal
surrogate keys that never reach the wire and are not part of any openEHR
identity, so stamping them would add a bind to four CTE statements for no
forensic gain (a dump exposes the stamped `contribution.id` beside them).

Client-supplied identifiers (`PUT /ehr/{id}`, compositions with a client
uid) pass through untouched. They carry no stamp by design and the
attestation report shows the sampled fraction.

Moving the audit and attestation ids from the DB default to app-minted
values keeps their tie-breaking semantics: the `uuid` crate's counter
preserves ordering within a millisecond and the stamp lives in bytes the
counter never uses.

## 5. Tests the FerroEHR change carries

- Chain verification and every refusal arm (moved with the core).
- Boot with no file, an unreadable file, a malformed file, an expired token,
  a valid token: the server starts in every case; `/rest/status` shows the
  right state.
- Every minting site produces ids that `StampKey::carries`; a mutation test
  that deletes the stamping call fails.
- A property test: stamping preserves bytes 0..14 and the version.
- Fuzz targets for token parsing move to FerroEHR's `fuzz/` workspace.

## 6. Disclosure footprint

The product side is plainly named and documented at the honest minimum:

- module `licence`, config section `[licence]`;
- one `CHANGELOG.md` line under Added;
- one sentence in the configuration reference for the key;
- doc comments in the module that state what the token holds and what the
  stamp is (no patient data, a licence id or a constant, in identifier
  entropy).

Nothing about this repository, the register, or the attestation tooling
appears in FerroEHR. The commercial licence agreement names the mechanism
(design §10).

## 7. Installation instruction for licensees

Delivered with the token:

> Place the file at a path the server can read and set
> `FERROEHR__LICENCE__FILE=/path/to/licence.asc` (or `[licence] file` in
> `ferroehr.toml`). Restart. `GET /ferroehr/rest/status` reports the
> licence state. The server runs identically without it.
