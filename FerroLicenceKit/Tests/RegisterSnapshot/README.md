# RegisterSnapshot

The register's `keys/`, `signers.json` and `register/` as they were on
2026-10-24, when the register moved to its own private repository
(`FerroHEALTH/FerroLICENCE-register`). The tests read them as real data: the
two licences verify against the two trust anchors, every file matches its
record, and the register checks against itself. The live register is
checked the same way in its own repository after every merge.

Fixed: never updated from the live register, so customer data never comes
here.
