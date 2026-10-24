import AppKit
import GitHubKit
import Register
import Signing
import SwiftUI

/// Screen 14: the YubiKey in this Mac, and who holds which key.
struct KeysView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            SwiftUI.Section("This Mac") {
                thisMac
            }
            SwiftUI.Section("Trusted Keys") {
                ForEach(model.keys.trusted, id: \.fingerprint) { KeyRow(fingerprint: $0.fingerprint, trusted: true) }
            }
            if !model.keys.retired.isEmpty {
                SwiftUI.Section("No Longer Trusted") {
                    ForEach(model.keys.retired, id: \.fingerprint) { KeyRow(fingerprint: $0.fingerprint, trusted: false) }
                }
            }
            if !model.keys.problems.isEmpty {
                SwiftUI.Section("Needs Attention") {
                    ForEach(model.keys.problems, id: \.self) { StatusRow(.warning, "\($0)") }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem {
                Menu("Change Keys", systemImage: "key.horizontal") {
                    Button("Trust a New Key…", systemImage: "checkmark.seal") { model.startTrustKey() }
                        .disabled(!model.isActiveHolder || !model.canPush)
                    Button("Stop Using a Key…", systemImage: "key.slash") { model.startStopKey() }
                        .disabled(model.me == nil || !model.canPush || model.keys.trusted.isEmpty)
                }
                .labelStyle(.titleAndIcon)
                .help("Trust a YubiKey someone else set up, or stop using one")
            }
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .primaryAction) {
                Button("Set Up a YubiKey…", systemImage: "plus") { openWindow(id: "setup") }
                    .buttonStyle(.glassProminent)
                    .labelStyle(.titleAndIcon)
                    .disabled(model.login == nil || !model.canPush)
            }
        }
    }

    @ViewBuilder var thisMac: some View {
        if let card = model.card {
            LabeledContent("YubiKey") { Text(verbatim: card.serial).monospacedDigit() }
            if model.cardReady {
                StatusRow(.success, "Holds the key of \(model.me?.holder ?? ""). Ready to sign.", symbol: "key.horizontal.fill")
            } else if let fpr = card.signatureKey {
                StatusRow(.warning, "Holds \(short(fpr)), which is not your trusted key.")
            } else {
                StatusRow(.info, "Has no key yet. Set it up to sign licences.", symbol: "key.horizontal")
            }
            if let tries = card.pinTriesLeft { LabeledContent("PIN tries left") { Text(tries, format: .number) } }
        } else {
            StatusRow(.info, "No YubiKey plugged in. Checking and attesting work without one.", symbol: "key.horizontal")
        }
    }
}

struct KeyRow: View {
    let fingerprint: String
    let trusted: Bool
    @Environment(AppModel.self) private var model

    var signer: Signer? { model.keys.signer(fingerprint) }

    var body: some View {
        LabeledContent {
            Text(status).foregroundStyle(statusColor)
        } label: {
            Label {
                Text(signer?.holder ?? short(fingerprint))
                HStack(spacing: 4) {
                    Text("\(medium(signer?.medium ?? "–")) · \(short(fingerprint))")
                    if let pr = model.pullRequest(trusting: fingerprint) {
                        Text("· added in")
                        PullRequestLink(number: pr.number, url: pr.url)
                    }
                }
            } icon: {
                Image(systemName: "key.horizontal")
                    .foregroundStyle(trusted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
        }
        .help(grouped(fingerprint))
    }

    var status: LocalizedStringResource {
        guard let s = signer else { return trusted ? KeyStatus.active.label : KeyStatus.retired.label }
        if let since = s.since, s.status != .active { return "\(s.status.label) \(since)" }
        return s.status.label
    }

    var statusColor: Color {
        switch signer?.status ?? (trusted ? .active : .retired) {
        case .active: .green
        case .lost, .handedOver: .orange
        case .retired: .secondary
        }
    }
}

/// Setting up a YubiKey, in its own window: seven steps, each PIN asked in
/// GnuPG's window, ending with the public key recorded like a licence.
struct SetupWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let flow = model.setup {
                SetupSteps(flow: flow)
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 560, minHeight: 600)
        .task {
            if model.setup == nil { model.setup = SetupFlow(model: model) }
            await model.setup?.refresh()
        }
    }
}

struct SetupSteps: View {
    @Bindable var flow: SetupFlow

    var body: some View {
        Form {
            SwiftUI.Section {
                ForEach(SetupStep.allCases) { step in
                    StepRow(number: step.rawValue + 1, text: step.title, state: state(step))
                }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set Up a YubiKey").font(.title2.bold()).foregroundStyle(.primary)
                    Text("About fifteen minutes. Each step is read back from the YubiKey, so you can stop and come back.")
                        .font(.body).fontWeight(.regular).foregroundStyle(.secondary)
                }
                .padding(.bottom, 6)
            }
            if let current = flow.probe?.current {
                SwiftUI.Section {
                    Text(current.explanation).fixedSize(horizontal: false, vertical: true)
                    if current == .trust {
                        TextField("Holder", text: $flow.holder, prompt: Text("Your full name"))
                    }
                    if let status = flow.status, flow.running != nil {
                        StatusRow(.info, status)
                    }
                    if let problem = flow.problem { StatusRow(.failure, problem) }
                    if current == .trust, flow.recording != .notStarted {
                        ChangeProgress(recording: flow.recording, recorded: "The key is recorded in the register.")
                    }
                    if current == .trust, let saved = flow.savedForOwner {
                        StatusRow(
                            kind: .success,
                            text:
                                "Saved as \(saved.lastPathComponent) in Downloads. Send it to an owner, who trusts it with Trust a New Key… in Keys."
                        ) {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([saved]) }
                        }
                        LabeledContent("Read them this fingerprint") {
                            Text(verbatim: flow.savedFingerprint.map(grouped) ?? "–").monospaced().textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text(current.title)
                } footer: {
                    if !(current == .trust && flow.recording != .notStarted) { actions(current) }
                }
            } else if flow.probe != nil {
                SwiftUI.Section {
                    StatusRow(.success, "This YubiKey is set up and its key is trusted. FerroEHR trusts it from its next release.")
                }
            }
        }
        .formStyle(.grouped)
    }

    func actions(_ current: SetupStep) -> some View {
        HStack {
            Button("Check Again") { Task { await flow.refresh() } }
                .disabled(flow.running != nil)
            if current == .changePINs {
                Button("PINs Already Changed") { Task { await flow.pinsAlreadyChanged() } }
                    .disabled(flow.running != nil)
                    .help("This YubiKey's PINs are no longer the factory PINs")
            }
            Spacer()
            Button(primaryTitle(current)) {
                Task {
                    switch current {
                    case .trust: await flow.trust()
                    case .checkCard: await flow.refresh()
                    default: await flow.run(current)
                    }
                }
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(flow.running != nil || (current == .trust && flow.holder.trimmingCharacters(in: .whitespaces).isEmpty))
        }
        .padding(.top, 4)
    }

    func primaryTitle(_ step: SetupStep) -> LocalizedStringResource {
        switch step {
        case .trust: flow.model.isActiveHolder ? "Record the Key" : "Save the Key for an Owner"
        case .checkCard: "Check the YubiKey"
        default: "Run This Step"
        }
    }

    func state(_ step: SetupStep) -> StepRow<EmptyView>.State {
        guard let probe = flow.probe else { return .todo }
        if probe.isDone(step) { return .done }
        return probe.current == step && flow.running == step ? .running : .todo
    }
}

/// Screen 17: General, Signing and Updates.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Signing", systemImage: "key.horizontal") { SigningSettings() }
            Tab("Updates", systemImage: "arrow.down.circle") { UpdateSettings() }
        }
        .frame(width: 520)
        .scenePadding()
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            LabeledContent("GitHub account") {
                if let login = model.login {
                    Text(verbatim: model.name.map { "\(login) (\($0))" } ?? login)
                } else {
                    Text("Not signed in")
                }
            }
            LabeledContent("Repository") {
                Link(destination: model.repository.repositoryURL) {
                    Text(verbatim: "\(Launch.repository.owner)/\(Launch.repository.name)")
                }
            }
            LabeledContent("Key holder") {
                if let me = model.me { Text(verbatim: me.holder) } else { Text("No: check and attest only") }
            }
            LanguagePicker()
            HStack {
                Spacer()
                Button("Sign Out") { Task { await model.signOut() } }
                    .disabled(model.login == nil)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The app's language: the system's, English or Dutch. macOS applies it the
/// next time the app opens, as for every app (System Settings, Language
/// & Region, Applications, does the same).
struct LanguagePicker: View {
    @AppStorage("FLLanguage") private var language = ""

    var body: some View {
        Picker(selection: $language) {
            Text("Same as macOS").tag("")
            Text(verbatim: "English").tag("en")
            Text(verbatim: "Nederlands").tag("nl")
        } label: {
            Text("Language")
            Text("Takes effect the next time FerroLICENCE opens.")
        }
        .onChange(of: language) { _, code in
            if code.isEmpty {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([code], forKey: "AppleLanguages")
            }
        }
    }
}

struct SigningSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            LabeledContent("GnuPG") {
                if let v = model.tools?.gnupgVersion { Text(verbatim: v) } else { Text("Not installed") }
            }
            LabeledContent("Folder") { Text(verbatim: model.tools?.gnupgFolder ?? "brew install gnupg pinentry-mac") }
            LabeledContent("PIN window") {
                model.tools?.pinentryMac == true ? Text(verbatim: "pinentry-mac") : Text("Not installed")
            }
            LabeledContent("YubiKey") {
                if let card = model.card {
                    Text(verbatim: "\(card.serial)\(card.signatureKey.map { " · \(short($0))" } ?? "")")
                } else {
                    Text("None plugged in")
                }
            }
            LabeledContent("PIN tries left") {
                if let tries = model.card?.pinTriesLeft { Text(tries, format: .number) } else { Text(verbatim: "–") }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .task { await model.refreshSigning() }
    }
}

struct UpdateSettings: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        @Bindable var updater = updater
        Form {
            Toggle("Check for updates automatically", isOn: $updater.checkAutomatically)
            Toggle("Download and install automatically", isOn: $updater.installAutomatically)
            Toggle(isOn: $updater.includePrereleases) {
                Text("Include test versions")
                Text("Releases marked as pre-release on GitHub")
            }
            LabeledContent("Version") { Text(verbatim: "\(Updater.version) (\(Updater.build))") }
            LabeledContent("Last checked") {
                if let last = updater.lastChecked { Text(last, format: .relative(presentation: .named)) } else { Text("Not yet") }
            }
            LabeledContent("Source") { Text("GitHub releases, \(Launch.repository.owner)/\(Launch.repository.name)") }
            if let problem = updater.problem { StatusRow(.failure, problem) }
            HStack {
                Link(destination: URL(string: "https://github.com/\(Launch.repository.owner)/\(Launch.repository.name)/releases")!) {
                    Label("Release Notes", systemImage: "arrow.up.forward.app")
                }
                Spacer()
                Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                    .disabled(updater.checking)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}
