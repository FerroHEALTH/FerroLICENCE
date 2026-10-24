# Contributing to FerroLICENCE

This repository is private and proprietary: the licensor-side tooling for
FerroEHR commercial licences, owned by Cadasto B.V. (see `NOTICE`).
Contributions come by invitation from the maintainer named in the Cargo
manifest. The working discipline is in [`CLAUDE.md`](CLAUDE.md).

## Pull requests

- Branch from `main` with a conventional-type name; every commit is signed.
- The pull request body declares `Closes #<n>` for the issue it answers.
- No AI or assistant attribution anywhere in the commits or the pull request.

## Licensing of contributions

FerroLICENCE is source-available under the Business Source License 1.1
(`LICENSE`, `NOTICE`). By submitting a contribution you:

1. certify that you wrote it, or otherwise have the right to submit it under
   these terms;
2. license it under the project licence of the version it lands in; and
3. grant Cadasto B.V., the Licensor, a perpetual, irrevocable, worldwide,
   royalty-free, transferable right to use, reproduce, modify, distribute,
   sublicense and relicense the contribution as part of the work under any
   terms.

You keep your copyright. There is no separate agreement to sign: the pull
request template carries a checkbox recording your acceptance of these terms,
and a pull request from a person does not merge without it (the
`contribution-licence-guard` check, backed by
`scripts/checks/contribution-licence.sh`).
