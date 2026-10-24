import Foundation
import GitHubKit
import LicenceCore
import Observation
import Register
import Signing

/// Where the app is between launch and work.
enum Phase: Equatable {
    case starting
    case signedOut
    /// Signed in; the Ready to Issue list is showing.
    case checking
    case ready
}

/// The sidebar's sections.
enum Section: String, CaseIterable, Identifiable, Hashable {
    case customers, activity, checkFile, attest, keys

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .customers: "Customers"
        case .activity: "Activity"
        case .checkFile: "Check a File"
        case .attest: "Attest Data"
        case .keys: "Keys"
        }
    }

    var symbol: String {
        switch self {
        case .customers: "building.2"
        case .activity: "clock.arrow.circlepath"
        case .checkFile: "checkmark.seal"
        case .attest: "chart.bar.doc.horizontal"
        case .keys: "key.horizontal"
        }
    }
}

/// A file dropped or opened for checking or attesting.
struct CheckedFile: Equatable {
    let name: String
    let text: String
}

/// How the last sync went.
struct SyncState: Equatable {
    var lastSynced: Date?
    var commit: String?
    var etag: String?
    var syncing = false
    var error: LocalizedStringResource?
    /// The register on screen came from the offline copy, saved at this time.
    var offlineSince: Date?
}

/// Everything the windows show, and every change to it.
@Observable
final class AppModel {
    let repository: any RepositoryService
    let signing: any SigningService
    let store: OfflineStore
    let notifier: Notifier
    /// Fixed in fixture mode, so screenshots do not change from day to day.
    let fixedToday: CivilDate?

    var phase: Phase = .starting
    var section: Section = .customers
    var selectedCustomer: String?

    // Signing in
    var deviceCode: DeviceCode?
    var signInError: LocalizedStringResource?
    var login: String?
    var name: String?
    var canPush = false

    // The register
    var snapshot = Snapshot()
    var keys = Keys()
    var register = LicenceRegister()
    var readError: LocalizedStringResource?
    var activity: [Merged] = []
    var sync = SyncState()

    // Signing
    var tools: Tools?
    var card: CardStatus?

    // Check a File and Attest Data
    var checkedFile: CheckedFile?
    var attestedFile: CheckedFile?

    var showSync = false

    // The changes in progress
    var issue: IssueFlow?
    var revoke: RevokeFlow?
    var stopKey: StopKeyFlow?
    var trustKey: TrustKeyFlow?
    var setup: SetupFlow?
    /// Changes still recording whose sheet was closed.
    var recordingInBackground = 0

    init(
        repository: any RepositoryService, signing: any SigningService, store: OfflineStore, notifier: Notifier,
        fixedToday: CivilDate? = nil
    ) {
        self.repository = repository
        self.signing = signing
        self.store = store
        self.notifier = notifier
        self.fixedToday = fixedToday
    }

    var today: CivilDate { fixedToday ?? .today }

    /// The signed-in person's row in `signers.json`; `nil` means read-only.
    var me: Signer? { login.flatMap { keys.signer(github: $0) } }

    /// Whether the YubiKey plugged in holds a trusted key of the signed-in person.
    var cardReady: Bool {
        guard let fpr = card?.signatureKey, let me else { return false }
        return keys.isTrusted(fpr) && me.fingerprint.caseInsensitiveCompare(fpr) == .orderedSame
    }

    /// Why a licence cannot be signed now, in words; `nil` when it can.
    var cannotSign: LocalizedStringResource? {
        if login == nil { return "Sign in with GitHub first." }
        if me == nil { return "Your GitHub account is not a key holder in signers.json, so this Mac can only check and attest." }
        if me?.status == .lost { return "Your key is marked lost, so it signs nothing new. Set up a new YubiKey." }
        if me?.status == .handedOver { return "Your key is marked handed over, so it signs nothing new." }
        if !canPush { return "Your GitHub account cannot open pull requests on the repository." }
        if tools?.gnupgVersion == nil { return "GnuPG is not installed. Run: brew install gnupg pinentry-mac" }
        if card == nil { return "Plug in your YubiKey." }
        if !cardReady { return "The YubiKey plugged in does not hold your trusted key." }
        return nil
    }

    // MARK: Launch and sign-in

    func start() async {
        if let saved = await store.saved() {
            show(saved.snapshot)
            sync.offlineSince = saved.savedAt
            sync.etag = saved.etag
            sync.commit = saved.snapshot.commit
        }
        guard await repository.isSignedIn else {
            phase = .signedOut
            return
        }
        await afterSignIn(showChecklist: false)
    }

    func signIn() async {
        signInError = nil
        do {
            let code = try await repository.startSignIn()
            deviceCode = code
            try await repository.finishSignIn(code)
            deviceCode = nil
            await afterSignIn(showChecklist: true)
        } catch is CancellationError {
            deviceCode = nil
        } catch {
            deviceCode = nil
            signInError = message(error)
        }
    }

    func afterSignIn(showChecklist: Bool) async {
        async let who: Void = refreshWho()
        async let synced: Void = syncNow()
        async let tooling: Void = refreshSigning()
        _ = await (who, synced, tooling)
        phase = showChecklist || readinessProblems ? .checking : .ready
    }

    /// Whether the Ready to Issue list has something to say.
    var readinessProblems: Bool { me != nil && cannotSign != nil }

    func refreshWho() async {
        do {
            let who = try await repository.whoAmI()
            login = who.login
            name = who.name
            canPush = who.canPush
        } catch {
            sync.error = message(error)
        }
    }

    func signOut() async {
        await repository.signOut()
        await store.clear()
        login = nil
        name = nil
        canPush = false
        show(Snapshot())
        activity = []
        sync = SyncState()
        phase = .signedOut
    }

    // MARK: Sync

    /// Read `main` again. An unchanged register costs one answer.
    func syncNow() async {
        guard !sync.syncing else { return }
        sync.syncing = true
        defer { sync.syncing = false }
        do {
            let result = try await repository.sync(etag: snapshot.files.isEmpty ? nil : sync.etag)
            if let fresh = result.snapshot {
                show(fresh)
                sync.etag = result.etag
                await store.save(fresh, etag: result.etag, at: Date())
            }
            sync.commit = result.commit
            sync.lastSynced = Date()
            sync.offlineSince = nil
            sync.error = nil
            activity = (try? await repository.activity()) ?? activity
            notifier.remindRenewals(register.todo(on: today), register: register)
        } catch {
            sync.error = message(error)
        }
    }

    func show(_ fresh: Snapshot) {
        snapshot = fresh
        do {
            keys = try Keys(fresh)
            register = try LicenceRegister(fresh)
            readError = nil
        } catch {
            readError = message(error)
        }
    }

    func refreshSigning() async {
        async let t = signing.tools()
        async let c = signing.card()
        tools = await t
        card = await c
    }

    func refreshCard() async { card = await signing.card() }

    // MARK: Looking things up

    /// The merged pull request that recorded `id`, or its revocation.
    func pullRequest(recording id: UUID, label: String = "licence") -> Merged? {
        activity.first { $0.labels.contains(label) && $0.records(id) }
    }

    /// The merged pull request that trusted `fingerprint`.
    func pullRequest(trusting fingerprint: String) -> Merged? {
        activity.first { $0.labels.contains("key") && $0.branch == "key/\(fingerprint.prefix(8).lowercased())" }
    }

    /// Who a GitHub login belongs to, by `signers.json`.
    func person(_ login: String) -> String { keys.signer(github: login)?.holder ?? login }

    // MARK: Changes

    func newLicence() {
        issue = IssueFlow(model: self, draft: .newCustomer(today: today))
    }

    func renew(_ entry: Entry) {
        issue = IssueFlow(model: self, draft: .renewal(of: entry, today: today))
    }

    func startRevoke(_ entry: Entry) {
        revoke = RevokeFlow(model: self, entry: entry)
    }

    /// The person signed in holds a key that is not lost or retired, so the
    /// Register check lets them change the keys.
    var isActiveHolder: Bool { me?.status == .active }

    /// Trust a New Key…: an owner records the key someone else set up.
    func startTrustKey() {
        trustKey = TrustKeyFlow(model: self)
    }

    /// Stop Using a Key…, starting on the first trusted key.
    func startStopKey() {
        if let first = keys.trusted.first { stopKey = StopKeyFlow(model: self, fingerprint: first.fingerprint) }
    }

    /// A commercial licence with no licence after it can be renewed.
    func canRenew(_ entry: Entry) -> Bool {
        entry.licence.use == .commercial && !register.hasSuccessor(entry)
    }

    /// Still to be revoked: commercial, not revoked, and not yet ended.
    func canRevoke(_ entry: Entry) -> Bool {
        guard entry.revocation == nil, entry.licence.use == .commercial else { return false }
        if case .ended = entry.standing(on: today) { return false }
        return true
    }

    /// A sheet is open, so the menu bar starts no second change.
    var sheetIsOpen: Bool { issue?.isShown == true || revoke != nil || stopKey != nil || trustKey != nil }

    /// Record a prepared change and sync once it is merged. The Register
    /// check runs here first, against `main` as it is now: the register's
    /// repository runs no CI, so nothing is opened that breaks a rule.
    func record(_ change: Change, progress: @escaping @Sendable (RecordingStep) -> Void) async throws -> RecordedChange {
        await syncNow()
        try RegisterCheck.check(change, on: snapshot, by: login ?? "")
        let done = try await repository.record(change, progress: progress)
        await syncNow()
        return done
    }

    // MARK: Files

    /// File › Open… asked the section on screen to show its file chooser.
    var openFileRequested = false

    /// The licence file Download to Downloads saved last, for its tick.
    var downloaded: URL?

    /// Why a download from the menu bar failed, for the main window's alert.
    var downloadProblem: LocalizedStringResource?

    /// Saves a licence file in the Downloads folder and returns where.
    func download(_ text: String, named name: String) throws -> URL {
        let url = try saveInDownloads(Data(text.utf8), named: name)
        downloaded = url
        return url
    }

    /// Saves a file in the Downloads folder and returns where.
    ///
    /// An earlier copy is never overwritten: the next one is
    /// `example-hospital 2.licence.asc`.
    func saveInDownloads(_ data: Data, named name: String) throws -> URL {
        let folder = URL.downloadsDirectory
        let dot = name.firstIndex(of: ".") ?? name.endIndex
        let (stem, ext) = (name[..<dot], name[dot...])
        var url = folder.appending(path: name)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path()) {
            url = folder.appending(path: "\(stem) \(n)\(ext)")
            n += 1
        }
        try data.write(to: url, options: .withoutOverwriting)
        return url
    }
}
