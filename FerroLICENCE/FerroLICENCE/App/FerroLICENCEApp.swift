import AppKit
import GitHubKit
import Register
import SwiftUI

@main
struct FerroLICENCEApp: App {
    @State private var model: AppModel
    @State private var updater: Updater
    private let launch = Launch.current

    init() {
        let (model, updater) = makeModel(Launch.current)
        _model = State(initialValue: model)
        _updater = State(initialValue: updater)
    }

    var body: some Scene {
        Window("FerroLICENCE", id: "main") {
            RootView(launch: launch)
                .environment(model)
                .environment(updater)
        }
        .defaultSize(launch.windowSize ?? CGSize(width: 1100, height: 700))
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            AppCommands(model: model, updater: updater)
        }

        Window("Set Up a YubiKey", id: "setup") {
            SetupWindow()
                .environment(model)
        }
        .defaultSize(width: 600, height: 660)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(model)
                .environment(updater)
        }
    }
}

/// The menu bar: every toolbar action has a menu command and a shortcut,
/// enabled by the same rules as its button.
///
/// File holds what makes or opens a file; Licence what acts on the licence
/// of the selected customer; Keys the YubiKey; View the sections and sync.
/// While a sheet is open the menus start no second change.
struct AppCommands: Commands {
    let model: AppModel
    let updater: Updater
    @Environment(\.openWindow) private var openWindow

    var ready: Bool { model.phase == .ready && !model.sheetIsOpen }
    var entry: Entry? { ready ? model.selectedEntry : nil }
    var file: String? { entry.flatMap { $0.integrity == .intact ? model.snapshot.text($0.licenceFile) : nil } }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Task { await updater.check(userInitiated: true) } }
                .disabled(updater.checking || model.phase == .signedOut)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Licence…") {
                model.section = .customers
                model.newLicence()
            }
            .keyboardShortcut("n")
            .disabled(!ready || model.cannotSign != nil)
            Button("Open…") {
                if model.section != .attest { model.section = .checkFile }
                model.openFileRequested = true
            }
            .keyboardShortcut("o")
            .disabled(!ready)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Download to Downloads") {
                guard let e = entry, let text = file else { return }
                do {
                    _ = try model.download(text, named: "\(e.customer).licence.asc")
                } catch {
                    model.downloadProblem = message(error)
                }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(file == nil || entry?.revocation != nil)
            Button("Copy Setup Instructions") {
                guard let e = entry else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(localized: setupMessage(e.licence)), forType: .string)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(entry == nil || entry?.revocation != nil)
        }
        CommandGroup(after: .toolbar) {
            Button("Sync Now") { Task { await model.syncNow() } }
                .keyboardShortcut("r")
                .disabled(model.phase == .signedOut || model.sync.syncing)
            Divider()
            ForEach(Section.allCases) { section in
                Button(section.title) { model.section = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(section.index + 1)")))
                    .disabled(model.phase != .ready)
            }
        }
        CommandMenu("Licence") {
            Button("Renew…") { if let e = entry { model.renew(e) } }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(entry.map { !model.canRenew($0) } ?? true || model.cannotSign != nil)
            Button("Revoke…") { if let e = entry { model.startRevoke(e) } }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(entry.map { !model.canRevoke($0) } ?? true || model.me == nil || !model.canPush)
            Divider()
            Button("Open Pull Request") {
                if let e = entry, let pr = model.pullRequest(recording: e.id) { NSWorkspace.shared.open(pr.url) }
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            .disabled(entry.flatMap { model.pullRequest(recording: $0.id) } == nil)
        }
        CommandMenu("Keys") {
            Button("Set Up a YubiKey…") { openWindow(id: "setup") }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!ready || model.login == nil || !model.canPush)
            Button("Trust a New Key…") {
                model.section = .keys
                model.startTrustKey()
            }
            .disabled(!ready || !model.isActiveHolder || !model.canPush)
            Button("Stop Using a Key…") {
                model.section = .keys
                model.startStopKey()
            }
            .disabled(!ready || model.me == nil || !model.canPush || model.keys.trusted.isEmpty)
        }
    }
}

extension Section {
    var index: Int { Section.allCases.firstIndex(of: self) ?? 0 }
}

extension AppModel {
    /// The current licence of the customer selected in Customers.
    var selectedEntry: Entry? {
        guard section == .customers, let slug = selectedCustomer, let c = register.customer(slug) else { return nil }
        return register.current(c, on: today)
    }
}
