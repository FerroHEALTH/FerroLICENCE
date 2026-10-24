# register/

Every licence ever issued, one folder per customer and one folder per
licence inside it, written by the app and never edited afterwards:

```text
<customer>/<licence-id>/licence.asc      the file exactly as the customer gets it
<customer>/<licence-id>/record.json      the signed licence, the key that signed it,
                                         the SHA-256 of licence.asc, the contract
                                         reference and the licence it renews
<customer>/<licence-id>/revocation.json  only when revoked: the day it stopped
                                         counting and why, written once
```

The customer folder is the licensee's name as a folder name; the licence id
is a UUIDv7, so folders sort in issue order. `record.json` carries
`"schema": 2`. The app checks every `licence.asc` against its record's hash
when it reads the register.

The register is what Attest matches a recovered stamp against. A licence id
that is not here was not issued by us.

A licence is issued once. Renewal is a new licence with a new id, linked to
the one it renews; the old folder stays, because identifiers minted under it
stay in the licensee's data. The installation never sees a revocation;
Attest and Check report against it.

A mistake noticed before the commit, on a licence that never left the
signer's computer, may be deleted and issued again; after the commit or the
delivery it never is (`docs/manuals/03-licences.md` §Mistakes). The
`signer` in each record names its holder through `../signers.json`.

The first record, the non-commercial grant of 2026-09-11, was signed by the
retired first key. It no longer checks out against `keys/`; the re-minted
grant of 2026-10-07 beside it does. The two records moved to this layout on
2026-10-23 with their licence files unchanged.
