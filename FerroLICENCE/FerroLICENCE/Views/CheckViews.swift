import AppKit
import LicenceCore
import Register
import SwiftUI
import UniformTypeIdentifiers

/// Takes a file dropped anywhere on the view, pasted, or opened from the
/// toolbar, and gives it to `take` as text.
struct FileInput: ViewModifier {
    let types: [UTType]
    @Binding var importing: Bool
    @Binding var problem: LocalizedStringResource?
    let take: (CheckedFile) -> Void
    @Environment(AppModel.self) private var model
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            // File › Open… on the section that is showing.
            .onChange(of: model.openFileRequested, initial: true) { _, asked in
                guard asked else { return }
                model.openFileRequested = false
                importing = true
            }
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(.tint, lineWidth: 3).padding(6).allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                if let url = urls.first { load(url) }
            }
            .onDropSessionUpdated { session in
                targeted = session.phase == .entering || session.phase == .active
            }
            .onPasteCommand(of: [.plainText, .utf8PlainText]) { _ in
                if let text = NSPasteboard.general.string(forType: .string) {
                    take(CheckedFile(name: String(localized: "Pasted text"), text: text))
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: types) { result in
                if case .success(let url) = result { load(url) }
            }
    }

    func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 64 << 20 else {
            problem = "That file is larger than 64 MB."
            return
        }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            problem = "That file is not text."
            return
        }
        problem = nil
        take(CheckedFile(name: url.lastPathComponent, text: text))
    }
}

extension View {
    func fileInput(
        _ types: [UTType], importing: Binding<Bool>, problem: Binding<LocalizedStringResource?>, take: @escaping (CheckedFile) -> Void
    )
        -> some View
    {
        modifier(FileInput(types: types, importing: importing, problem: problem, take: take))
    }
}

/// Screen 12: the answer first, then the facts; the nine checks open from
/// the last row. Works offline against the saved register.
struct CheckFileView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var problem: LocalizedStringResource?

    var body: some View {
        Group {
            if let file = model.checkedFile {
                Form {
                    SwiftUI.Section {
                        LabeledContent {
                            Button("Choose Another…") { importing = true }
                        } label: {
                            Label(file.name, systemImage: "doc.text")
                        }
                        if let problem { StatusRow(.failure, problem) }
                    }
                    CheckResult(file: file)
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView {
                    Label("Check a Licence File", systemImage: "checkmark.seal")
                } description: {
                    Text("Drop a licence file here, paste its text, or open it. The check works offline, as FerroEHR does at boot.")
                    if let problem { Text(problem) }
                } actions: {
                    Button("Open File…") { importing = true }
                }
            }
        }
        .fileInput(
            [.plainText, .data, UTType(filenameExtension: "asc") ?? .data], importing: $importing, problem: $problem
        ) { model.checkedFile = $0 }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Open File…", systemImage: "doc") { importing = true }
                    .buttonStyle(.glassProminent)
                    .labelStyle(.titleAndIcon)
            }
        }
    }
}

struct CheckResult: View {
    let file: CheckedFile
    @Environment(AppModel.self) private var model
    @State private var showChecks = false

    var body: some View {
        switch Result(catching: { () throws(Token.Failure) in
            try FileCheck(text: file.text, keys: model.keys, register: model.register, day: model.today)
        }) {
        case .failure:
            SwiftUI.Section {
                StatusRow(.failure, "This is not a licence file. A licence file starts with -----BEGIN PGP SIGNED MESSAGE-----.")
            }
        case .success(let check):
            SwiftUI.Section {
                StatusRow(check.failedAt == nil ? .success : .failure, check.headline(keys: model.keys))
            }
            SwiftUI.Section("This Licence") {
                if let l = check.claimed {
                    LabeledContent("Customer") { Text("\(l.licensee) · \(l.use.label)") }
                    LabeledContent("Valid") { Text(span(l)) }
                }
                LabeledContent("Genuine") {
                    Label {
                        Text(genuineLine(check))
                    } icon: {
                        Image(systemName: check.genuine ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(check.genuine ? .green : .red)
                    }
                }
                LabeledContent("In FerroEHR") { Text(check.inFerroEHR) }
                DisclosureGroup(isExpanded: $showChecks) {
                    ForEach(Check.allCases, id: \.self) { c in
                        Label {
                            Text(c.title)
                        } icon: {
                            Image(systemName: icon(c, check)).foregroundStyle(color(c, check))
                        }
                    }
                } label: {
                    LabeledContent("Checks") { Text("\(check.passed) of \(Check.allCases.count) passed") }
                }
            }
        }
    }

    func genuineLine(_ check: FileCheck) -> LocalizedStringResource {
        guard check.genuine else { return "Not signed by one of our keys" }
        let who = model.keys.holder(check.signer)
        return switch check.known {
        case .ours(_, let revocation?): "Signed by \(who), revoked from \(revocation.effective)"
        case .ours: "Signed by \(who), in the register"
        default: "Signed by \(who), but not in the register"
        }
    }

    func icon(_ c: Check, _ check: FileCheck) -> String {
        guard let failed = check.failedAt else { return "checkmark.circle.fill" }
        return c < failed ? "checkmark.circle.fill" : c == failed ? "xmark.circle.fill" : "circle.dashed"
    }

    func color(_ c: Check, _ check: FileCheck) -> Color {
        guard let failed = check.failedAt else { return .green }
        return c < failed ? .green : c == failed ? .red : .secondary
    }
}

/// Screen 13: the verdict first, then the evidence in plain numbers, then
/// anything that needs attention.
struct AttestView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var problem: LocalizedStringResource?
    @State private var copied = false

    var body: some View {
        Group {
            if let file = model.attestedFile {
                Form {
                    SwiftUI.Section {
                        LabeledContent {
                            Button("Choose Another…") { importing = true }
                        } label: {
                            Label {
                                Text(file.name)
                                Text("\(Attest.uuids(in: file.text).count) identifiers")
                            } icon: {
                                Image(systemName: "chart.bar.doc.horizontal")
                            }
                        }
                        if let problem { StatusRow(.failure, problem) }
                    }
                    AttestResult(report: attest(file.text, register: model.register))
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView {
                    Label("Attest Data", systemImage: "chart.bar.doc.horizontal")
                } description: {
                    Text("Drop a database export, a log or an API response here, or open it. Every identifier in it is read.")
                    if let problem { Text(problem) }
                } actions: {
                    Button("Open File…") { importing = true }
                }
            }
        }
        .fileInput([.plainText, .json, .commaSeparatedText, .data], importing: $importing, problem: $problem) { model.attestedFile = $0 }
        .toolbar {
            if let file = model.attestedFile {
                ToolbarItem {
                    Button(copied ? "Copied" : "Copy Report", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report(file), forType: .string)
                        copied = true
                    }
                    .help("Copy the full numbers for a letter or a case file")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Open File…", systemImage: "doc") { importing = true }
                    .buttonStyle(.glassProminent)
                    .labelStyle(.titleAndIcon)
            }
        }
        .onChange(of: model.attestedFile) { copied = false }
    }

    func report(_ file: CheckedFile) -> String {
        let r = attest(file.text, register: model.register)
        var lines = [
            String(localized: "FerroLICENCE attestation of \(file.name), \(Date().formatted(date: .long, time: .shortened))"),
            String(localized: "Identifiers read: \(r.total); version 7: \(r.sampled)"), "",
        ]
        for f in r.findings {
            lines.append(String(localized: "\(f.label): \(f.matched) of \(f.sampled) carry its mark; p = \(f.pValue)"))
        }
        return lines.joined(separator: "\n")
    }
}

struct AttestResult: View {
    let report: Attest.Report
    @Environment(AppModel.self) private var model

    var body: some View {
        if report.sampled == 0 {
            SwiftUI.Section { StatusRow(.info, "No FerroEHR identifiers in this file: it holds no version 7 UUIDs.") }
        } else if let best = report.best(threshold: identificationThreshold) {
            SwiftUI.Section { StatusRow(.success, verdict(best), symbol: "checkmark.seal") }
            SwiftUI.Section("Result") {
                LabeledContent("Evidence") { Text("\(best.matched) of \(best.sampled) carry its mark") }
                LabeledContent("By chance") { Text(chance(best.pValue)) }
                if let first = best.firstMatch, let last = best.lastMatch {
                    LabeledContent("Made") {
                        Text(
                            "\(first, format: .dateTime.day().month(.abbreviated).year()) – \(last, format: .dateTime.day().month(.abbreviated).year())"
                        )
                    }
                }
                if best.matchedAfterNotAfter > 0 {
                    StatusRow(.warning, "\(best.matchedAfterNotAfter) made after the licence ended")
                }
                if best.matchedFromRevocation > 0 {
                    StatusRow(.warning, "\(best.matchedFromRevocation) made after it was revoked")
                }
            }
        } else {
            SwiftUI.Section {
                StatusRow(
                    .warning, "Not made under any licence in the register, nor by an unlicensed server. \(report.sampled) identifiers read."
                )
            }
        }
    }

    func verdict(_ f: Attest.Finding) -> LocalizedStringResource {
        if f.label == "unlicensed" { return "Made by a FerroEHR server running without a licence" }
        guard let id = UUID(uuidString: f.label), let e = model.register.entry(id) else { return "Made under licence \(f.label)" }
        return "Made under the licence of \(e.licence.licensee) (\(span(e.licence)))"
    }

    /// `fewer than 1 in 10³⁰⁰`.
    func chance(_ p: Double) -> LocalizedStringResource {
        guard p > 0 else { return "fewer than 1 in 10³⁰⁰" }
        let exponent = Int(-log10(p).rounded(.down))
        return exponent >= 3
            ? "fewer than 1 in 10\(superscript(exponent))" : "about \(p.formatted(.percent.precision(.significantDigits(2))))"
    }

    func superscript(_ n: Int) -> String {
        let digits = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
        return String(n).compactMap { $0.wholeNumberValue.map { digits[$0] } }.joined()
    }
}
