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
  key (`docs/manuals/03-licences.md` §The free licence every build embeds).

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
