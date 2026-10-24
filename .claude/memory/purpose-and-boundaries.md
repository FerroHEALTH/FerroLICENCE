---
name: purpose-and-boundaries
description: "FerroLICENCE (FerroHEALTH/FerroLICENCE) is the licensor side of FerroEHR commercial licences (created 2026-09-11): YubiKey setup, issue, renew, revoke, check, attest. Public under BSL 1.1 since 2026-10-24; the register lives in the private FerroHEALTH/FerroLICENCE-register. FerroEHR has its own checker, matched by test vectors. FerroEHR's public tree never names this repository."
metadata:
  node_type: memory
  type: project
  originSessionId: c42e0bc5-5284-4a27-b5b1-1b4a8555455d
  modified: 2026-10-01T15:41:54.930Z
---

On 2026-10-24 the owner split it: the code is public at `FerroHEALTH/FerroLICENCE` (BSL 1.1, no additional use grant, a fresh history), and the register, the keys and `signers.json` are in the private `FerroHEALTH/FerroLICENCE-register` (the old repository renamed, with its history), which runs no CI. Created 2026-09-11 by the owner's decision to keep licensor tooling out of the public FerroEHR repository. GnuPG signs on the YubiKey, the Swift checker in `FerroLicenceKit/LicenceCore` verifies; the stamp is 16 HMAC-SHA256 bits in the last two bytes of every server-minted UUIDv7 (`docs/design.md`).

**Why:** the product must accept exactly what is issued; FerroEHR verifies with its own checker and this repository proves agreement with shared test vectors instead of shared code (owner, 2026-10-23: nothing moves to FerroEHR). The register is confidential; the code is not. The Register check runs in the app before every change; a person with write access to the register could still merge by hand outside the app (accepted, `docs/threat-model.md`).

**How to apply:** never mention FerroLICENCE, its paths or its existence in FerroEHR's code, docs, commits or memory; read `docs/design.md` and `docs/ferroehr-integration.md` before touching the token format or the stamp; a change to either needs new vectors from FerroEHR's checker.
Release lane: the owner decided the internal tool needs no SBOM or artifact-signing lane (GitHub artifact attestations were refused for the then user-owned private repository, probed 2026-09-11); do not re-add one. Release immutability is a repository setting the owner flips in the UI.
