import GitHubKit
import Register
import Signing
import SwiftUI

/// The main window. Customers is a three-column split view (sidebar,
/// customers, the customer); every other section is two columns. Each
/// section owns its toolbar; sync and the YubiKey are one group on the
/// trailing side everywhere.
struct MainView: View {
    @Environment(AppModel.self) private var model
    /// Whether the sidebar is hidden, for the window: both split views read
    /// and write it, so hiding it in one section keeps it hidden in the next.
    @SceneStorage("sidebarHidden") private var sidebarHidden = false

    var body: some View {
        @Bindable var model = model
        Group {
            if model.section == .customers {
                NavigationSplitView(columnVisibility: threeColumns) {
                    Sidebar()
                } content: {
                    CustomerList()
                        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
                } detail: {
                    CustomerDetailColumn()
                        .toolbar { StatusItems() }
                }
            } else {
                NavigationSplitView(columnVisibility: twoColumns) {
                    Sidebar()
                } detail: {
                    SectionDetail()
                        .toolbar { StatusItems() }
                }
            }
        }
        .sheet(item: issueBinding) { IssueSheet(flow: $0) }
        .sheet(item: $model.revoke) { RevokeSheet(flow: $0) }
        .sheet(item: $model.stopKey) { StopKeySheet(flow: $0) }
        .sheet(item: $model.trustKey) { TrustKeySheet(flow: $0) }
        .alert(
            "The Licence File Was Not Saved",
            isPresented: Binding(get: { model.downloadProblem != nil }, set: { if !$0 { model.downloadProblem = nil } }),
            presenting: model.downloadProblem
        ) { _ in
            Button("OK") {}
        } message: {
            Text($0)
        }
    }

    /// Customers: the sidebar hidden leaves the list and the customer.
    var threeColumns: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { sidebarHidden ? .doubleColumn : .all },
            set: { sidebarHidden = $0 == .doubleColumn || $0 == .detailOnly })
    }

    /// Every other section: the sidebar hidden leaves the section alone.
    var twoColumns: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { sidebarHidden ? .detailOnly : .all },
            set: { sidebarHidden = $0 == .detailOnly })
    }

    /// Closing the sheet while a licence is still recording keeps it recording.
    var issueBinding: Binding<IssueFlow?> {
        Binding(
            get: { model.issue?.isShown == true ? model.issue : nil },
            set: { if $0 == nil { model.issue?.close() } })
    }
}

/// The sidebar: Licences, Tools and Signing.
struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.section) {
            SwiftUI.Section("Licences") {
                row(.customers, badge: model.register.customers.count)
                row(.activity)
            }
            SwiftUI.Section("Tools") {
                row(.checkFile)
                row(.attest)
            }
            SwiftUI.Section("Signing") {
                row(.keys)
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
    }

    /// A sidebar row. The tag comes last: a modifier after it, such as a
    /// badge, hides it from the list's selection.
    func row(_ section: Section, badge: Int = 0) -> some View {
        Label(section.title, systemImage: section.symbol)
            .badge(badge)
            .accessibilityIdentifier("sidebar.\(section.rawValue)")
            .tag(section)
    }
}

/// Every section but Customers, titled with the sync state.
struct SectionDetail: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let error = model.readError {
                ContentUnavailableView {
                    Label("The Register Does Not Read", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Sync Now") { Task { await model.syncNow() } }
                }
            } else {
                switch model.section {
                case .customers: EmptyView()
                case .activity: ActivityView().accessibilityElement(children: .contain).accessibilityIdentifier("section.activity")
                case .checkFile: CheckFileView().accessibilityElement(children: .contain).accessibilityIdentifier("section.checkFile")
                case .attest: AttestView().accessibilityElement(children: .contain).accessibilityIdentifier("section.attest")
                case .keys: KeysView().accessibilityElement(children: .contain).accessibilityIdentifier("section.keys")
                }
            }
        }
        .navigationTitle(model.section.title)
        .navigationSubtitle(SyncLine(sync: model.sync).text)
    }
}

/// "Synced 2 minutes ago", and the other states of the last sync.
struct SyncLine {
    let sync: SyncState

    var text: Text {
        if sync.syncing { return Text("Syncing…") }
        if let saved = sync.offlineSince { return Text("Offline copy from \(saved, format: .relative(presentation: .named))") }
        if sync.error != nil { return Text("Not synced: no connection") }
        guard let last = sync.lastSynced else { return Text(verbatim: "") }
        return Text("Synced \(last, format: .relative(presentation: .named))")
    }
}

/// Sync and the YubiKey, one glass group on the trailing side.
struct StatusItems: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            SyncButton()
            CardIndicator()
        }
        .visibilityPriority(.high)
        ToolbarSpacer(.fixed)
    }
}

/// The sync symbol and its popover.
struct SyncButton: View {
    @Environment(AppModel.self) private var model
    @Environment(Updater.self) private var updater

    var body: some View {
        @Bindable var model = model
        Button {
            model.showSync.toggle()
        } label: {
            Label(
                "Sync",
                systemImage: model.sync.error == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.arrow.triangle.2.circlepath"
            )
            .symbolEffect(.rotate, isActive: model.sync.syncing)
        }
        .help("Sync with GitHub (⌘R)")
        .popover(isPresented: $model.showSync, arrowEdge: .bottom) { SyncPopover().environment(model).environment(updater) }
    }
}

/// What was read, what is still recording, the offline copy, the next sync,
/// and an available update.
struct SyncPopover: View {
    @Environment(AppModel.self) private var model
    @Environment(Updater.self) private var updater

    var body: some View {
        Form {
            SwiftUI.Section {
                LabeledContent("Register") {
                    Text(verbatim: "main · \(model.sync.commit.map { String($0.prefix(7)) } ?? "–")").monospacedDigit()
                }
                LabeledContent("Recording") {
                    model.recordingInBackground == 0 ? Text("Nothing pending") : Text("\(model.recordingInBackground) still recording")
                }
                LabeledContent("Offline copy") { Text("Saved, \(model.register.entries.count) licences") }
                LabeledContent("Next sync") {
                    if let last = model.sync.lastSynced {
                        Text(last.addingTimeInterval(300), format: .dateTime.hour().minute())
                    } else {
                        Text("Now")
                    }
                }
            } header: {
                Label {
                    SyncLine(sync: model.sync).text
                } icon: {
                    Image(systemName: model.sync.error == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.sync.error == nil ? .green : .orange)
                }
                .font(.headline)
            } footer: {
                if let error = model.sync.error { Text(error) }
            }
            if let update = updater.available {
                SwiftUI.Section {
                    LabeledContent {
                        Button("Update…") { Task { await updater.check(userInitiated: true) } }
                    } label: {
                        Label {
                            Text("FerroLICENCE \(update.version) is available")
                            Text("You have \(Updater.version)")
                        } icon: {
                            Image(systemName: "arrow.down.circle").foregroundStyle(.tint)
                        }
                    }
                }
            }
            SwiftUI.Section {
                Button("Sync Now") { Task { await model.syncNow() } }
                    .keyboardShortcut("r")
                    .disabled(model.sync.syncing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The YubiKey in the toolbar: green when it holds your trusted key. A
/// toolbar button like its neighbours, so the glass group spaces it the
/// same; it opens Keys, where the YubiKey is explained.
struct CardIndicator: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.section = .keys
        } label: {
            Label("YubiKey", systemImage: "key.horizontal.fill")
                .foregroundStyle(model.cardReady ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
        }
        .help(help)
        .accessibilityLabel(help)
    }

    var help: Text {
        guard let card = model.card else { return Text("No YubiKey plugged in") }
        return model.cardReady
            ? Text("YubiKey \(card.serial) ready to sign") : Text("YubiKey \(card.serial) does not hold your trusted key")
    }
}
