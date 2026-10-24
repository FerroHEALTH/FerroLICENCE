import GitHubKit
import LicenceCore
import Register
import Signing
import SwiftUI

/// Screens 4 to 7 and 9: draft, check, sign, recording, recorded. Each step
/// is one grouped form; its buttons sit in the sheet's own action slots, so
/// Return and Escape work as on every Mac sheet.
struct IssueSheet: View {
    @Bindable var flow: IssueFlow

    var body: some View {
        Group {
            switch flow.step {
            case .draft: DraftStep(flow: flow)
            case .check: CheckStep(flow: flow)
            case .sign: SignStep(flow: flow)
            case .recording: RecordingProgress(flow: flow)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .interactiveDismissDisabled(flow.step == .sign)
    }
}

/// The title, and the step track while there are steps to show.
struct IssueHeader: View {
    let flow: IssueFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if flow.step == .recording, case .recorded = flow.recording {
                SheetTitle(title: "Licence Recorded", symbol: "checkmark.seal", color: .green)
            } else {
                SheetTitle(
                    title: flow.title,
                    subtitle: flow.step == .recording ? flow.prepared.map { "\($0.licence.licensee), \(span($0.licence))" } : nil)
                if flow.step < .recording { StepTrack(steps: ["Draft", "Check", "Sign"], current: flow.step.rawValue) }
            }
        }
        .foregroundStyle(.primary)
        .padding(.bottom, 6)
    }
}

struct DraftStep: View {
    @Bindable var flow: IssueFlow
    enum Field { case licensee, contract }
    /// Where typing starts: the name for a new customer, the contract for a renewal.
    @FocusState private var focus: Field?

    var body: some View {
        Form {
            SwiftUI.Section {
                if flow.renewing == nil {
                    TextField(text: $flow.draft.licensee, prompt: Text("Legal name, as in the agreement")) {
                        Label("Customer", systemImage: "building.2")
                    }
                    .focused($focus, equals: .licensee)
                }
                DatePicker(selection: day($flow.draft.notBefore), displayedComponents: .date) { Label("Starts", systemImage: "calendar") }
                DatePicker(selection: day($flow.draft.notAfter), displayedComponents: .date) { Label("Ends", systemImage: "calendar") }
                Picker(selection: $flow.draft.use) {
                    Text("Commercial").tag(Use.commercial)
                    Text("Free").tag(Use.nonCommercial)
                } label: {
                    Label("Type", systemImage: "doc.text")
                }
                .pickerStyle(.segmented)
                TextField(text: $flow.draft.contract, prompt: Text("For example EH-2026-021")) {
                    Label("Contract", systemImage: "tray.and.arrow.down")
                }
                .focused($focus, equals: .contract)
            } header: {
                IssueHeader(flow: flow)
            } footer: {
                Text(hint).foregroundStyle(.secondary)
            }
            if let problem = flow.problem {
                SwiftUI.Section { StatusRow(.failure, problem) }
            }
        }
        .environment(\.timeZone, TimeZone(identifier: "UTC")!)
        .defaultFocus($focus, flow.renewing == nil ? .licensee : .contract)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { flow.close() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Continue") { flow.toCheck() }
                    .disabled(flow.draft.problem != nil)
                    .help(flow.draft.problem ?? "")
            }
        }
    }

    var hint: LocalizedStringResource {
        flow.renewing == nil
            ? "Runs one year from today. The contract reference stays in the register; it is never put in the licence."
            : "Starts the day after the current licence ends and runs one year. The contract reference stays in the register; it is never put in the licence."
    }

    /// A licence day as a date picker's date, in UTC so the day never shifts.
    func day(_ binding: Binding<CivilDate>) -> Binding<Date> {
        Binding(get: { binding.wrappedValue.start }, set: { binding.wrappedValue = CivilDate($0) })
    }
}

struct CheckStep: View {
    @Bindable var flow: IssueFlow
    @State private var showText = false

    var body: some View {
        Form {
            if let p = flow.prepared {
                SwiftUI.Section {
                    LabeledContent("Customer") { Text(p.licence.licensee).bold() }
                    LabeledContent("Valid") { Text(span(p.licence)).bold() }
                    LabeledContent("Type") { Text(p.licence.use.label) }
                    if let contract = p.contract { LabeledContent("Contract", value: contract) }
                    LabeledContent("Signed by") { Text("Your YubiKey, \(flow.model.me?.holder ?? "")") }
                } header: {
                    IssueHeader(flow: flow)
                }
                SwiftUI.Section {
                    StatusRow(.warning, "A signed licence can never be changed. A mistake means a new licence.")
                    DisclosureGroup("Exact text the YubiKey signs", isExpanded: $showText) {
                        Text(p.text)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let problem = flow.problem ?? flow.model.cannotSign {
                    SwiftUI.Section { StatusRow(.failure, problem) }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { flow.back() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sign with YubiKey", systemImage: "key.horizontal") { flow.sign() }
                    .labelStyle(.titleAndIcon)
                    .disabled(flow.model.cannotSign != nil)
            }
        }
    }
}

struct SignStep: View {
    @Bindable var flow: IssueFlow

    var body: some View {
        Form {
            SwiftUI.Section {
                HStack {
                    Spacer()
                    YubiKeyDrawing()
                    Spacer()
                }
                .padding(.vertical, 12)
                StepRow(number: 1, text: "Type your PIN in the window that opened", state: .running)
                StepRow(number: 2, text: "Touch your YubiKey when its light blinks", state: .todo)
            } header: {
                IssueHeader(flow: flow)
            } footer: {
                Text("Nothing leaves your Mac until the licence passes FerroEHR's checks.").foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { flow.close() }
            }
        }
    }
}

struct RecordingProgress: View {
    @Bindable var flow: IssueFlow

    var body: some View {
        switch flow.recording {
        case .recorded(let done):
            Recorded(flow: flow, done: done)
        default:
            Form {
                SwiftUI.Section {
                    if case .failed(let why) = flow.recording {
                        StatusRow(.failure, why)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    } else {
                        let done = flow.recording.stepsDone
                        StepRow(number: 1, text: "Signed on YubiKey \(flow.model.card?.serial ?? "") and checked", state: .done)
                        StepRow(number: 2, text: pullRequestLine, state: done >= 2 ? .done : .running) {
                            if let pr = flow.recording.pullRequest { PullRequestLink(number: pr.number, url: pr.url) }
                        }
                        StepRow(number: 3, text: "Merge into main", state: done >= 3 ? .done : done == 2 ? .running : .todo)
                    }
                } header: {
                    IssueHeader(flow: flow)
                } footer: {
                    if case .failed = flow.recording {
                        EmptyView()
                    } else {
                        Text("You can close this; a notification says when the licence is recorded.").foregroundStyle(.secondary)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { flow.close() }
                }
            }
        }
    }

    var pullRequestLine: LocalizedStringResource {
        flow.recording.pullRequest == nil ? "Opening a pull request on GitHub" : "Pull request opened on GitHub"
    }
}

/// Screen 9: recorded, then send.
struct Recorded: View {
    @Bindable var flow: IssueFlow
    let done: RecordedChange

    var body: some View {
        Form {
            if let p = flow.prepared {
                SwiftUI.Section {
                    LabeledContent {
                        Text("licence.asc · \((flow.signedFile?.utf8.count ?? 0).formatted(.byteCount(style: .file)))")
                    } label: {
                        Label("Licence file", systemImage: "doc.text")
                    }
                    LabeledContent {
                        CopySetupButton(licence: p.licence)
                    } label: {
                        Label("For their IT", systemImage: "wrench.and.screwdriver")
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 10) {
                        IssueHeader(flow: flow)
                        Text(recordedLine(p.licence))
                            .font(.body)
                            .fontWeight(.regular)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Later") { flow.close() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if let p = flow.prepared {
                    DownloadButton(name: "\(slug(p.licence.licensee)).licence.asc", text: flow.signedFile)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    /// The sentence with its pull request as a link, translated whole.
    func recordedLine(_ l: Licence) -> AttributedString {
        l.use == .commercial
            ? AttributedString(
                localized:
                    "Recorded in the register in [#\(done.number)](\(done.url.absoluteString)). \(l.licensee) can use FerroEHR commercially until \(l.notAfter)."
            )
            : AttributedString(
                localized:
                    "Recorded in the register in [#\(done.number)](\(done.url.absoluteString)). \(l.licensee) can use FerroEHR until \(l.notAfter)."
            )
    }
}
