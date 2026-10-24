import GitHubKit
import LicenceCore
import Register
import SwiftUI
import UniformTypeIdentifiers

/// Screen 10: revoking needs no signature, so typing REVOKE is the
/// deliberate step. It is recorded like a licence.
struct RevokeSheet: View {
    @Bindable var flow: RevokeFlow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if flow.recording == .notStarted {
                SwiftUI.Section {
                    TextField("Reason", text: $flow.reason, prompt: Text("The contract clause or the letter"))
                    DatePicker(
                        selection: $flow.effective, in: flow.entry.licence.notBefore.start...flow.entry.licence.notAfter.start,
                        displayedComponents: .date
                    ) {
                        Label("Stops from", systemImage: "calendar")
                    }
                } header: {
                    header
                } footer: {
                    Text(
                        "Their FerroEHR keeps running; an offline licence cannot be switched off. This records that it no longer counts, as evidence if their data is checked later. The record can never be changed."
                    )
                    .foregroundStyle(.secondary)
                }
                SwiftUI.Section {
                    TextField("Type REVOKE", text: $flow.typed, prompt: Text(""))
                        .autocorrectionDisabled()
                }
                if let problem = flow.problem ?? (flow.reason.isEmpty ? nil : flow.draft.problem(for: flow.entry)) {
                    SwiftUI.Section { StatusRow(.failure, problem) }
                }
            } else {
                SwiftUI.Section {
                    ChangeProgress(recording: flow.recording, recorded: "The revocation is recorded in the register.")
                } header: {
                    header
                }
            }
        }
        .formStyle(.grouped)
        .environment(\.timeZone, TimeZone(identifier: "UTC")!)
        .frame(width: 520)
        .toolbar {
            if flow.recording == .notStarted {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Revoke", role: .destructive) { Task { await flow.revoke() } }
                        .tint(.red)
                        .disabled(!flow.canRevoke)
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    var header: some View {
        SheetTitle(
            title: "Revoke \(shortName(flow.entry.licence.licensee))", symbol: "xmark.seal", color: .red,
            subtitle: "Licence \(span(flow.entry.licence)), \(flow.entry.licence.use.inSentence)"
        )
        .foregroundStyle(.primary)
        .padding(.bottom, 6)
    }
}

/// Stop Using a Key…: handed over to a successor, or lost, keeps it trusted
/// and its licences working; retire (someone else may hold the YubiKey and
/// its PIN) makes FerroEHR stop trusting it from its next release.
struct StopKeySheet: View {
    @Bindable var flow: StopKeyFlow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if flow.recording == .notStarted {
                SwiftUI.Section {
                    Picker("Key", selection: $flow.fingerprint) {
                        ForEach(flow.model.keys.trusted, id: \.fingerprint) { a in
                            Text("\(flow.model.keys.holder(a.fingerprint)) · \(short(a.fingerprint))").tag(a.fingerprint)
                        }
                    }
                    Picker("Why", selection: $flow.reason) {
                        Text("Handed over to someone with their own key").tag(KeyStatus.handedOver).disabled(!inUse)
                        Text("Lost, and nobody else has the PIN").tag(KeyStatus.lost).disabled(!inUse)
                        Text("Someone else may have it and its PIN").tag(KeyStatus.retired)
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: flow.fingerprint, initial: true) { if !inUse { flow.reason = .retired } }
                } header: {
                    header
                } footer: {
                    Text(footer)
                        .foregroundStyle(.secondary)
                }
                SwiftUI.Section {
                    TextField("Type \(flow.word)", text: $flow.typed, prompt: Text(""))
                        .autocorrectionDisabled()
                }
                if let problem = flow.problem { SwiftUI.Section { StatusRow(.failure, problem) } }
            } else {
                SwiftUI.Section {
                    ChangeProgress(recording: flow.recording, recorded: "The change is recorded in the register.")
                } header: {
                    header
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .toolbar {
            if flow.recording == .notStarted {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle, role: flow.reason == .retired ? .destructive : nil) { Task { await flow.record() } }
                        .tint(flow.reason == .retired ? .red : nil)
                        .disabled(!flow.confirmed)
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    /// The chosen key still signs; one that stopped can only be retired.
    var inUse: Bool { flow.model.keys.signer(flow.fingerprint)?.status == .active }

    var confirmTitle: LocalizedStringResource {
        switch flow.reason {
        case .handedOver: "Mark as Handed Over"
        case .retired: "Retire Key"
        default: "Mark as Lost"
        }
    }

    /// Licences this key signed that still count today.
    var stillValid: [Entry] {
        flow.model.register.entries.filter { e in
            guard e.record.signer.caseInsensitiveCompare(flow.fingerprint) == .orderedSame, e.revocation == nil else { return false }
            if case .ended = e.standing(on: flow.model.today) { return false }
            return true
        }
    }

    /// Whole sentences per case, so each translates with its own word order.
    var footer: LocalizedStringResource {
        let n = stillValid.count
        switch (flow.reason, n) {
        case (.retired, 0):
            return
                "Retiring moves its public key to keys/retired/, and FerroEHR stops trusting it from its next release. No licence it signed still counts."
        case (.retired, 1):
            return
                "Retiring moves its public key to keys/retired/, and FerroEHR stops trusting it from its next release. The one licence it signed that still counts must be issued again with the other key."
        case (.retired, _):
            return
                "Retiring moves its public key to keys/retired/, and FerroEHR stops trusting it from its next release. The \(n) licences it signed that still count must be issued again with the other key."
        case (.handedOver, 0):
            return "A handed-over key stays trusted and signs nothing new. Trust the successor's key first, with Trust a New Key… in Keys."
        case (.handedOver, 1):
            return
                "A handed-over key stays trusted and signs nothing new; the one licence it signed that still counts keeps working. Trust the successor's key first, with Trust a New Key… in Keys."
        case (.handedOver, _):
            return
                "A handed-over key stays trusted and signs nothing new; the \(n) licences it signed that still count keep working. Trust the successor's key first, with Trust a New Key… in Keys."
        case (_, 0):
            return "A lost key stays trusted, and nobody signs with it again."
        case (_, 1):
            return "A lost key stays trusted, and nobody signs with it again. The one licence it signed that still counts keeps working."
        default:
            return "A lost key stays trusted, and nobody signs with it again. The \(n) licences it signed that still count keep working."
        }
    }

    var header: some View {
        SheetTitle(
            title: "Stop Using a Key", symbol: "key.horizontal", color: .orange,
            subtitle: "Record why it signs nothing new, so the register says which licences it may still sign."
        )
        .foregroundStyle(.primary)
        .padding(.bottom, 6)
    }
}

/// Trust a New Key…: the key someone set up on their own Mac, from the file
/// Set Up a YubiKey saved for an owner. Its fingerprint is read out between
/// the two before TRUST is typed.
struct TrustKeySheet: View {
    @Bindable var flow: TrustKeyFlow
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false

    var body: some View {
        Form {
            if flow.recording == .notStarted {
                SwiftUI.Section {
                    LabeledContent("Key file") {
                        HStack {
                            if flow.request != nil { Text(verbatim: flow.fileName).foregroundStyle(.secondary) }
                            Button(flow.request == nil ? "Choose File…" : "Choose Another…") { choosing = true }
                        }
                    }
                    if let r = flow.request {
                        LabeledContent("Holder", value: r.holder)
                        LabeledContent("GitHub", value: r.github)
                        LabeledContent("Where", value: r.medium)
                        LabeledContent("Fingerprint") {
                            Text(verbatim: r.fingerprint.map(grouped) ?? "–").monospaced().textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    header
                } footer: {
                    if flow.request != nil {
                        Text(
                            "Ask the new holder to read out the fingerprint Set Up a YubiKey showed them, and compare it with this one. Trusting it lets them sign licences from their own GitHub account."
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                if flow.request != nil {
                    SwiftUI.Section {
                        TextField("Type TRUST", text: $flow.typed, prompt: Text(""))
                            .autocorrectionDisabled()
                    }
                }
                if let problem = flow.problem { SwiftUI.Section { StatusRow(.failure, problem) } }
            } else {
                SwiftUI.Section {
                    ChangeProgress(recording: flow.recording, recorded: "The key is recorded in the register.")
                } header: {
                    header
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { flow.open(url) }
        }
        .toolbar {
            if flow.recording == .notStarted {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Trust Key") { Task { await flow.record() } }
                        .disabled(!flow.confirmed)
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    var header: some View {
        SheetTitle(
            title: "Trust a New Key", symbol: "key.horizontal", color: .accentColor,
            subtitle: "Record a YubiKey that someone else set up, from the key file they sent you."
        )
        .foregroundStyle(.primary)
        .padding(.bottom, 6)
    }
}

/// A revocation or key change on its way through GitHub, as rows of a form.
struct ChangeProgress: View {
    let recording: Recording
    /// The sentence once it is merged, such as "The revocation is recorded in the register."
    let recorded: LocalizedStringResource

    var body: some View {
        switch recording {
        case .recorded(let done):
            StatusRow(kind: .success, text: recorded) { PullRequestLink(number: done.number, url: done.url) }
        case .failed(let why):
            StatusRow(.failure, why)
        default:
            let done = recording.stepsDone
            StepRow(number: 1, text: "Pull request opened on GitHub", state: done >= 2 ? .done : .running) {
                if let pr = recording.pullRequest { PullRequestLink(number: pr.number, url: pr.url) }
            }
            StepRow(number: 2, text: "Merge into main", state: done >= 3 ? .done : done == 2 ? .running : .todo)
        }
    }
}
