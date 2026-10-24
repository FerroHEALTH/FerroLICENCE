---
name: the-app
description: "2026-10-24 owner decision: the ratatui app is replaced by a native SwiftUI macOS 27 app that reads and writes the register through a GitHub App; every change is a pull request the app merges once the Register check passes; all Rust removed"
metadata:
  type: project
---

On 2026-10-23 the owner decided to replace the ratatui app (PR #34) with a native macOS app, and on 2026-10-24 approved the build after six rounds of screen designs. Result: `FerroLICENCE/` (the SwiftUI app, Xcode project) over `FerroLicenceKit/` (a local Swift package: `LicenceCore`, `Register`, `Signing`, `GitHubKit`, and the `register-check` command). Every Rust crate is gone; FerroEHR has its own checker, and the Swift checker is tied to the Rust one by the test vectors in `FerroLicenceKit/Tests/LicenceCoreTests/Vectors`, generated before the Rust code was removed.

Owner decisions: macOS 27 and Apple Silicon only; no local clone, the app reads the register through the GitHub API with the signed-in person's GitHub App token; **no review**: the app runs the Register check on each change, then opens a pull request in FerroLICENCE-register, squash-merges it and deletes the branch (no CI on the register since 2026-10-24); app updates through Sparkle from GitHub Releases; the icon is an Icon Composer `.icon` bundle. The token format, the stamp and register schema 2 stay as they are; `signers.json` gains a `github` login per holder.

**Why:** others in the company must be able to issue and check licences without a terminal, and the owner wants the register on GitHub to be the only copy, guarded by a check rather than a reviewer.

**How to apply:** keep a check step before every write (PIN and touch for issuing; typed `REVOKE`, `LOST`, `RETIRE`); never add a review step or a local clone; every new kind of change gets a rule in `RegisterCheck`; follow `.claude/rules/swift.md`, and check every screen with the screenshot tour after a UI change.
