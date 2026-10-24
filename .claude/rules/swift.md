---
paths:
  - "**/*.swift"
  - "FerroLicenceKit/Package.swift"
  - "FerroLICENCE/**"
---

# Writing Swift here

The app and the kit are written for Swift 6.4, Xcode 27 and macOS 27, and
nothing older. When an API has a current form and an old one, use the
current one. When unsure whether an API exists or how it is spelled, read
the SDK's `.swiftinterface` (under
`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/<F>.framework/Modules/`)
or Apple's documentation before writing it. Never guess an API from memory.

Apple's own guidance ships with Xcode as agent skills: run
`bash scripts/dev/xcode-skills.sh` once per Mac (and after an Xcode update)
to export them into `.claude/skills/`. `swiftui-specialist` and
`swiftui-whats-new-27` supersede anything here that disagrees; read their
references before writing views, data flow or user-facing text.

Always set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`:
`xcode-select` points at the Command Line Tools on this machine.

## Language and concurrency

- Swift 6 language mode, strict concurrency, no `@preconcurrency` or
  `nonisolated(unsafe)` to silence the compiler.
- The kit enables `ExistentialAny`, `InternalImportsByDefault`,
  `MemberImportVisibility`, `NonisolatedNonsendingByDefault` and
  `InferIsolatedConformances` (`FerroLicenceKit/Package.swift`). The app
  target builds with approachable concurrency and `MainActor` as the
  default isolation. Mark work that must leave the caller's actor
  `@concurrent`.
- `async`/`await`, `Task`, task groups and `AsyncSequence` only. No
  `DispatchQueue`, no completion handlers, no Combine, no `Timer`, no
  `NotificationCenter` observers where an async sequence exists.
- Shared mutable state lives in an `actor`, or in `Mutex` from
  `Synchronization`. Never `NSLock`, never `@unchecked Sendable` outside
  tests.
- Time is `Duration`, `ContinuousClock` and `Task.sleep(for:)`.
- Errors are typed where the caller switches on them:
  `throws(GnuPGError)`. Every error a person may see has a
  `message: LocalizedStringResource` saying what to do; its `description`
  resolves that message.
- `any P` for existentials, `some P` for opaque types, `if`/`switch`
  expressions instead of temporary variables.

## Foundation and the system

- Processes go through `swift-subprocess` (`Command.run` in
  `Signing/GnuPG.swift`), never `Process` or `Pipe` in the app or the kit.
  A cancelled run is torn down and returns; check `Task.isCancelled` after it.
- `URL(filePath:)`, `appending(path:)`, `url.path()`; dates with
  `FormatStyle` (`Date.ISO8601FormatStyle`, `.formatted(...)`), never
  `DateFormatter` or `ISO8601DateFormatter`.
- JSON with `Codable`. GitHub's snake_case is handled by
  `.convertFromSnakeCase`/`.convertToSnakeCase`; Swift names stay
  camelCase. Readers that must refuse unknown fields use a `Decodable`
  init over `JSONKey`. `JSONSerialization` only in tests.
- The token lives in the Keychain (`KeychainTokenStore`), settings in
  `@AppStorage`, the offline copy in SwiftData. Never a file of secrets,
  never `UserDefaults` for a token.

## SwiftUI

- Observation: `@Observable` models, `@State` to own them, `@Environment`
  to pass them, `@Bindable` to bind. Never `ObservableObject`,
  `@Published`, `@StateObject` or `@EnvironmentObject`.
- SwiftData `@Model` and `@Query` for the cache; no Core Data.
- `NavigationSplitView`, `Inspector`, `.sheet`, `.confirmationDialog`,
  `Table`, `Form` with `.formStyle(.grouped)`, `ContentUnavailableView`,
  `ShareLink`, `.searchable`, `Settings` scene, `Window` and `WindowGroup`
  with `.defaultSize` and `.windowResizability`.
- Liquid Glass comes from the system: standard toolbars, sidebars, sheets
  and controls get it without code. Use `.glassEffect` and
  `GlassEffectContainer` only for a custom floating control, never as a
  background on content. Follow the macOS HIG: system fonts and text
  styles, semantic colours (`.primary`, `.secondary`, `.tint`), SF Symbols
  by their real names (check them in the SF Symbols app), Dynamic Type,
  keyboard shortcuts on every menu command, VoiceOver labels on every
  icon-only button.
- Views draw and send intents; the model changes state. No GnuPG or
  network calls from a view's body. Long work runs in `.task` or in the
  model and shows progress.
- Previews use `#Preview` with fixture data from the app's `Fixtures`,
  never the network or the YubiKey.
- Native layout, not hand-made: Customers is a three-column
  `NavigationSplitView`; other sections are two columns. Actions live in
  the toolbar of the column they act on, grouped with `ToolbarSpacer(.fixed)`
  (one prominent `.glassProminent` action per view, everything else plain).
  State in a form is a `StatusRow` (a symbol in the state's colour, one
  sentence, at most one trailing button), never a tinted box. Empty states
  are `ContentUnavailableView`. Sheets are one grouped `Form` with their
  buttons in `.cancellationAction` and `.confirmationAction`.
- No soft-deprecated APIs (the list is in `swiftui-specialist`): for
  example `dropDestination(for:isEnabled:action:)` with a `DropSession`,
  `overlay(alignment:content:)`, `Section(content:header:footer:)`.

## Text and languages

The app speaks English and Dutch.

- SwiftUI literals (`Text("…")`, `Button("…")`, `.help("…")`) localise by
  themselves; never wrap them in `String(localized:)`.
- Text that travels through models and components is
  `LocalizedStringResource`, resolved when it is shown. `String(localized:)`
  only where a `String` is required (notifications, the pasteboard).
- The kit has its own String Catalog per module; its strings are
  `LocalizedStringResource("…", bundle: #bundle)`.
- A sentence is one string, never assembled from pieces, so each language
  keeps its word order; counts get plural variations in the catalog. Never
  lowercase or uppercase a translated string at run time.
- Days interpolate as `CivilDate` (it formats itself for the reader's
  language); dates and numbers through `format:`.
- Text that goes to GitHub (pull request titles and bodies, the Register
  check's report) stays English: it is the audit record.
- After changing user-facing text, run `bash scripts/dev/sync-strings.sh` and
  add the Dutch for every new entry in the catalogs, then check the screens
  in Dutch: `EXTRA="-AppleLanguages (nl) -AppleLocale nl_NL" bash scripts/ui/screenshots.sh`.

## Tests

- Swift Testing only: `@Suite`, `@Test`, `#expect`, `#require`,
  parameterised `arguments:`, `.enabled(if:)`, `.serialized` where tests
  share a process. No XCTest outside the UI test target.
- Network tests go through `MockGitHub` (a `URLProtocol`), never GitHub.
  GnuPG tests use a throwaway home under `/tmp` and never the developer's
  keyring.
- The UI is checked by the screenshot tour (`.claude/skills/screenshots`):
  every screen, light and dark, smallest and large window, English and
  Dutch, rendered through XCUITest so Liquid Glass is real. Look at every
  image before calling UI work done.

## Formatting

`swift format` with the root `.swift-format` (140 columns, 4 spaces). The
Claude hook formats each edited file and the pre-commit hook runs
`swift format lint --strict`. Comments follow CLAUDE.md: one-sentence
summary, blank line, detail; `///` for documentation.
