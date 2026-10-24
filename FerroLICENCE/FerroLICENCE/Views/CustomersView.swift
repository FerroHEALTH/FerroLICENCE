import AppKit
import GitHubKit
import LicenceCore
import Register
import SwiftUI
import UniformTypeIdentifiers

/// The content column: who needs attention, then every customer.
struct CustomerList: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedCustomer) {
            if !attention.isEmpty {
                SwiftUI.Section("Needs Attention") {
                    ForEach(attention) { CustomerRow(customer: $0).tag($0.slug) }
                }
            }
            SwiftUI.Section("All Customers") {
                ForEach(others) { CustomerRow(customer: $0).tag($0.slug) }
            }
        }
        .overlay {
            if model.register.customers.isEmpty {
                ContentUnavailableView {
                    Label("No Customers Yet", systemImage: "building.2")
                } description: {
                    Text("Every licence issued shows here.")
                } actions: {
                    Button("New Licence") { model.newLicence() }.disabled(model.cannotSign != nil)
                }
            } else if !search.isEmpty, attention.isEmpty, others.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search Customers")
        .navigationTitle("Customers")
        .navigationSubtitle(SyncLine(sync: model.sync).text)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Licence", systemImage: "plus") { model.newLicence() }
                    .buttonStyle(.glassProminent)
                    .labelStyle(.titleAndIcon)
                    .disabled(model.cannotSign != nil)
                    .help(model.cannotSign.map { Text($0) } ?? Text("Draft a licence for a new customer (⌘N)"))
            }
        }
        .onAppear {
            if model.selectedCustomer == nil { model.selectedCustomer = (attention.first ?? others.first)?.slug }
        }
        .accessibilityIdentifier("section.customers")
    }

    var attentionSlugs: [String] {
        model.register.todo(on: model.today).map {
            switch $0 {
            case .endingSoon(let c, _, _), .endedWithoutRenewal(let c, _, _): c
            }
        }
    }

    func matches(_ c: Customer) -> Bool { search.isEmpty || c.name.localizedStandardContains(search) }
    var attention: [Customer] { attentionSlugs.compactMap(model.register.customer).filter(matches) }
    var others: [Customer] { model.register.customers.filter { !attentionSlugs.contains($0.slug) && matches($0) } }
}

struct CustomerRow: View {
    let customer: Customer
    @Environment(AppModel.self) private var model

    var body: some View {
        let look = model.register.current(customer, on: model.today).map {
            StandingLook($0.standing(on: model.today), use: $0.licence.use, brief: true)
        }
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(shortName(customer.name)).lineLimit(1)
                if let look { Text(look.line).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
            }
        } icon: {
            Image(systemName: look?.symbol ?? "circle")
                .foregroundStyle(look?.color ?? .secondary)
                .accessibilityHidden(true)
        }
        .help(customer.name)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("customer.\(customer.slug)")
    }
}

/// The detail column: the customer selected, or a prompt to pick one.
struct CustomerDetailColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let slug = model.selectedCustomer, let customer = model.register.customer(slug) {
            CustomerDetail(customer: customer)
        } else {
            ContentUnavailableView("No Customer Selected", systemImage: "building.2", description: Text("Pick a customer on the left."))
        }
    }
}

/// The customer: what needs doing, the current licence, every earlier one.
/// Its actions are in the toolbar.
struct CustomerDetail: View {
    let customer: Customer
    @Environment(AppModel.self) private var model

    var entries: [Entry] { customer.licences.compactMap(model.register.entry) }
    var current: Entry? { model.register.current(customer, on: model.today) }
    var earlier: [Entry] { entries.filter { $0.id != current?.id } }

    var body: some View {
        Form {
            SwiftUI.Section {
                if let current, let status = status(current) { status }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(shortName(customer.name)).font(.title.bold()).foregroundStyle(.primary).lineLimit(2)
                    since.font(.body).fontWeight(.regular).foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
            }
            if let current {
                SwiftUI.Section("Current Licence") {
                    LicenceFacts(entry: current)
                }
            }
            if !earlier.isEmpty {
                SwiftUI.Section("Earlier") {
                    ForEach(earlier) { e in
                        LabeledContent {
                            HStack(spacing: 6) {
                                Text(StandingLook(e.standing(on: model.today), use: e.licence.use).line)
                                if let pr = model.pullRequest(recording: e.id) { PullRequestLink(number: pr.number, url: pr.url) }
                            }
                        } label: {
                            Text(span(e.licence))
                        }
                        .contextMenu {
                            if e.integrity == .intact { SaveButton(entry: e) }
                            if revocable(e) { RevokeButton(entry: e) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(shortName(customer.name))
        .navigationSubtitle(since)
        .toolbar {
            if let current { actions(current) }
        }
    }

    var since: Text {
        let first = entries.map(\.licence.notBefore).min()
        let count = entries.count
        return first.map { Text("Customer since \($0.monthAndYear) · \(count) licences") } ?? Text("\(count) licences")
    }

    /// Renew…, Download to Downloads, and the rest in More.
    @ToolbarContentBuilder func actions(_ e: Entry) -> some ToolbarContent {
        ToolbarItemGroup {
            if model.canRenew(e), !statusOffersRenew(e) {
                Button("Renew…", systemImage: "arrow.clockwise") { model.renew(e) }
                    .disabled(model.cannotSign != nil)
                    .help(model.cannotSign.map { Text($0) } ?? Text("Draft the next licence for this customer"))
            }
            if e.revocation == nil, e.integrity == .intact {
                DownloadButton(name: "\(e.customer).licence.asc", text: model.snapshot.text(e.licenceFile))
            }
        }
        ToolbarItem {
            Menu("More", systemImage: "ellipsis") {
                if e.integrity == .intact { SaveButton(entry: e) }
                if e.revocation == nil { CopySetupButton(licence: e.licence) }
                if let pr = model.pullRequest(recording: e.id) {
                    Link(destination: pr.url) { Label("Open Pull Request #\(pr.number)", systemImage: "arrow.up.forward.app") }
                }
                if revocable(e) {
                    Divider()
                    RevokeButton(entry: e)
                }
            }
            .menuIndicator(.hidden)
            .help("More actions for this licence")
        }
    }

    /// The one thing that needs doing, as a row: renew, or why there is nothing to do.
    func status(_ e: Entry) -> StatusRow<AnyView>? {
        let renewed = model.register.hasSuccessor(e)
        switch e.standing(on: model.today) {
        case .inForce(let until, let left) where left <= LicenceRegister.endingSoonDays && !renewed:
            return StatusRow(kind: .warning, text: "Ends in \(left) days · \(until)") { AnyView(renewButton(e)) }
        case .ended(let on, _) where !renewed:
            return StatusRow(kind: .warning, text: "Ended on \(on), with no new licence", symbol: "minus.circle.fill") {
                AnyView(renewButton(e))
            }
        case .revoked(let from):
            return StatusRow(kind: .failure, text: "Revoked from \(from): \(e.revocation?.reason ?? "")", symbol: "xmark.octagon.fill") {
                AnyView(EmptyView())
            }
        case .upcoming(let starts):
            return StatusRow(kind: .info, text: "Starts on \(starts)", symbol: "clock.fill") { AnyView(EmptyView()) }
        default:
            return nil
        }
    }

    /// The status row already carries Renew… when the licence ends soon or ended.
    func statusOffersRenew(_ e: Entry) -> Bool {
        guard !model.register.hasSuccessor(e) else { return false }
        switch e.standing(on: model.today) {
        case .inForce(_, let left): return left <= LicenceRegister.endingSoonDays
        case .ended: return true
        default: return false
        }
    }

    func renewButton(_ e: Entry) -> some View {
        Button("Renew…") { model.renew(e) }
            .disabled(model.cannotSign != nil)
    }

    func revocable(_ e: Entry) -> Bool { model.canRevoke(e) }
}

/// The facts of one licence, as grouped rows.
struct LicenceFacts: View {
    let entry: Entry
    @Environment(AppModel.self) private var model

    var body: some View {
        LabeledContent("Valid") { Text(span(entry.licence)) }
        LabeledContent("Type") { Text(entry.licence.use.label) }
        if let contract = entry.record.contract { LabeledContent("Contract", value: contract) }
        LabeledContent("Signed by", value: model.keys.holder(entry.record.signer))
        LabeledContent("Recorded") {
            HStack(spacing: 6) {
                Text(entry.record.recordedAt, format: .dateTime.day().month(.abbreviated).year())
                if let pr = model.pullRequest(recording: entry.id) {
                    Text(verbatim: "·").foregroundStyle(.secondary)
                    PullRequestLink(number: pr.number, url: pr.url)
                }
            }
            .fixedSize()
        }
        if entry.integrity != .intact {
            StatusRow(
                .failure,
                entry.integrity == .missing ? "licence.asc is missing from the register." : "licence.asc no longer matches its record.")
        }
    }
}

struct RevokeButton: View {
    let entry: Entry
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Revoke…", systemImage: "xmark.seal", role: .destructive) { model.startRevoke(entry) }
            .disabled(model.me == nil || !model.canPush)
    }
}

/// The licence file as a document, for Save….
struct LicenceDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]
    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

/// Save…: the register's own `licence.asc`, wherever it is needed.
struct SaveButton: View {
    let entry: Entry
    @Environment(AppModel.self) private var model
    @State private var saving = false

    var body: some View {
        Button("Save Licence File…", systemImage: "square.and.arrow.down") { saving = true }
            .fileExporter(
                isPresented: $saving, document: model.snapshot.text(entry.licenceFile).map(LicenceDocument.init),
                contentType: .plainText, defaultFilename: "\(entry.customer).licence.asc"
            ) { _ in }
            .disabled(model.snapshot.text(entry.licenceFile) == nil)
    }
}

/// Download to Downloads: the licence file goes straight into the Downloads
/// folder, ready to attach to a mail; the symbol turns into a tick for a
/// moment to say it is there.
struct DownloadButton: View {
    let name: String
    let text: String?
    @Environment(AppModel.self) private var model
    @State private var saved: URL?
    @State private var failure: LocalizedStringResource?

    var body: some View {
        Button {
            guard let text else { return }
            do {
                _ = try model.download(text, named: name)
            } catch {
                failure = message(error)
            }
        } label: {
            Label {
                Text("Download to Downloads")
            } icon: {
                Image(systemName: saved == nil ? "arrow.down.circle" : "checkmark.circle.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .disabled(text == nil)
        .help(saved.map { Text("Saved as \($0.lastPathComponent) in Downloads") } ?? Text("Save licence.asc in your Downloads folder"))
        // A download from here or from File › Download to Downloads.
        .onChange(of: model.downloaded) { _, url in saved = url }
        .task(id: saved) {
            guard saved != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            saved = nil
        }
        .alert(
            "The Licence File Was Not Saved", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
            presenting: failure
        ) { _ in
            Button("OK") {}
        } message: {
            Text($0)
        }
    }
}

/// Copy Setup Instructions: the text their IT needs, for the mail that
/// carries the licence file.
struct CopySetupButton: View {
    let licence: Licence

    var body: some View {
        Button("Copy Setup Instructions", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(localized: setupMessage(licence)), forType: .string)
        }
        .help("Copy what their IT needs to install the licence")
    }
}

/// The setup instructions that go with every licence file.
func setupMessage(_ licence: Licence) -> LocalizedStringResource {
    """
    Attached is the FerroEHR licence for \(licence.licensee), valid from \(licence.notBefore) to \(licence.notAfter).

    For your IT: place licence.asc at a path the FerroEHR server can read and set FERROEHR__LICENCE__FILE=/path/to/licence.asc \
    (or [licence] file in ferroehr.toml). Restart the server. GET /ferroehr/rest/status reports the licence state. \
    The server runs the same without it.
    """
}
