import AppKit
import GitHubKit
import Register
import Signing
import SwiftUI

/// Screen 1: the only login. One button copies the code and opens GitHub;
/// the app notices the approval and continues by itself.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var signingIn: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Sign in with GitHub")
                .font(.title2.bold())
            Text("FerroLICENCE reads the register and opens pull requests on \(Launch.repository.owner)/\(Launch.repository.name) as you.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if Launch.clientID.isEmpty && !Launch.current.fixtures {
                Label {
                    Text("This build has no GitHub App client id. An organisation owner creates the app once: see docs/github-app.md.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .frame(maxWidth: 360)
            } else if let code = model.deviceCode {
                Text(verbatim: code.userCode)
                    .font(.system(.largeTitle, design: .monospaced, weight: .semibold))
                    .tracking(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: 360)
                    .padding(.vertical, 18)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 14))
                    .accessibilityLabel(Text("Code \(code.userCode.map(String.init).joined(separator: " "))"))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.userCode, forType: .string)
                    NSWorkspace.shared.open(code.verificationURL)
                } label: {
                    Label("Copy Code and Open GitHub", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                Text("Waiting for GitHub… the code works for \(minutes(until: code.expiresAt)) minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Sign In with GitHub") { start() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            if let error = model.signInError {
                Label {
                    Text(error)
                } icon: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
                .frame(maxWidth: 360)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { signingIn?.cancel() }
    }

    func start() {
        signingIn = Task { await model.signIn() }
    }

    func minutes(until date: Date) -> Int { max(1, Int(date.timeIntervalSinceNow / 60)) }
}

/// Screen 2: Ready to Issue. Shown on first launch and whenever something
/// is missing; without a YubiKey, Check, Attest and Activity still work.
struct ReadyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            SwiftUI.Section {
                Row(
                    symbol: "person.crop.circle", title: "Signed in as \(model.login ?? "…")",
                    detail: model.me.map { "\($0.holder) in signers.json" } ?? "Not a key holder: this Mac can check and attest only",
                    ok: model.me != nil)
                Row(
                    symbol: "arrow.triangle.pull", title: model.canPush ? "Can open pull requests" : "Cannot open pull requests",
                    detail: "\(Launch.repository.owner)/\(Launch.repository.name)", ok: model.canPush)
                Row(
                    symbol: "terminal", title: gnupgTitle, detail: "\(model.tools?.gnupgFolder ?? "brew install gnupg pinentry-mac")",
                    ok: model.tools?.gnupgVersion != nil && model.tools?.pinentryMac == true,
                    copy: model.tools?.gnupgVersion == nil || model.tools?.pinentryMac != true ? "brew install gnupg pinentry-mac" : nil)
                Row(
                    symbol: "key.horizontal", title: cardTitle,
                    detail: "\(model.card?.signatureKey.map(short) ?? String(localized: "Plug in your YubiKey"))",
                    ok: model.cardReady)
                Row(
                    symbol: "arrow.triangle.2.circlepath",
                    title: model.sync.lastSynced == nil ? "Register not synced" : "Register synced",
                    detail: "\(model.register.entries.count) licences on main", ok: model.sync.lastSynced != nil)
            } header: {
                Text("Ready to Issue").font(.title2.bold()).foregroundStyle(.primary).padding(.bottom, 6)
            } footer: {
                HStack {
                    Button("Check Again") { Task { await model.afterSignIn(showChecklist: true) } }
                    Spacer()
                    Button("Continue") { model.phase = .ready }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
                .padding(.top, 8)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var gnupgTitle: LocalizedStringResource {
        guard let v = model.tools?.gnupgVersion else { return "GnuPG is not installed" }
        return model.tools?.pinentryMac == true ? "GnuPG \(v) and pinentry-mac" : "GnuPG \(v), but no pinentry-mac"
    }

    var cardTitle: LocalizedStringResource {
        guard let card = model.card else { return "No YubiKey plugged in" }
        return model.cardReady ? "YubiKey \(card.serial) holds your key" : "YubiKey \(card.serial) does not hold your key"
    }

    struct Row: View {
        let symbol: String
        let title: LocalizedStringResource
        let detail: LocalizedStringResource
        let ok: Bool
        var copy: String?

        var body: some View {
            LabeledContent {
                HStack(spacing: 8) {
                    if let copy {
                        Button("Copy Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(copy, forType: .string)
                        }
                        .controlSize(.small)
                    }
                    Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(ok ? .green : .orange)
                        .accessibilityLabel(ok ? Text("Ready") : Text("Needs attention"))
                }
            } label: {
                Label {
                    Text(title)
                    Text(detail).lineLimit(1).truncationMode(.middle)
                } icon: {
                    Image(systemName: symbol).foregroundStyle(.tint)
                }
            }
        }
    }
}
