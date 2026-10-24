import Foundation
import GitHubKit
import LicenceCore
import Observation
import Register
import Signing

/// How far a change has got on GitHub.
enum Recording: Equatable {
    case notStarted
    case inProgress(RecordingStep)
    case recorded(RecordedChange)
    case failed(LocalizedStringResource)

    var pullRequest: (number: Int, url: URL)? {
        switch self {
        case .inProgress(.opened(let n, let u)), .inProgress(.merged(let n, let u, _)): (n, u)
        case .recorded(let r): (r.number, r.url)
        default: nil
        }
    }

    /// The sheet's list: how many of its lines are done (opened, merged).
    var stepsDone: Int {
        switch self {
        case .notStarted, .inProgress(.opening): 1
        case .inProgress(.opened), .failed: 2
        case .inProgress(.merged), .recorded: 3
        }
    }
}

/// Runs `change` through the recorder, reporting each step to `update`.
@MainActor
func run(_ change: Change, on model: AppModel, update: @escaping @MainActor (Recording) -> Void) async {
    update(.inProgress(.opening))
    do {
        let done = try await model.record(change) { step in Task { @MainActor in update(.inProgress(step)) } }
        update(.recorded(done))
    } catch {
        update(.failed(message(error)))
    }
}

// MARK: - Issue

/// A new licence or a renewal: draft, check, sign on the YubiKey, record.
@Observable
final class IssueFlow: Identifiable {
    enum Step: Int, Comparable {
        case draft, check, sign, recording
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    let id = UUID()
    unowned let model: AppModel
    var draft: Draft
    var step: Step = .draft
    var prepared: Prepared?
    var problem: LocalizedStringResource?
    var recording: Recording = .notStarted
    /// The licence file once signed and checked.
    var signedFile: String?
    var isShown = true
    var task: Task<Void, Never>?

    init(model: AppModel, draft: Draft) {
        self.model = model
        self.draft = draft
    }

    var renewing: Entry? { draft.renews.flatMap(model.register.entry) }

    var title: LocalizedStringResource {
        switch step {
        case .draft: renewing.map { "Renew \($0.licence.licensee)" } ?? "New Licence"
        case .check: "Check Before Signing"
        case .sign: "Sign with Your YubiKey"
        case .recording:
            if case .recorded = recording { "Licence Recorded" } else { "Recording the Licence" }
        }
    }

    /// Draft to check: the licence id is minted here, so the text shown is what the card signs.
    func toCheck() {
        do {
            prepared = try Prepared(draft, today: model.today)
            problem = nil
            step = .check
        } catch {
            problem = error.message
        }
    }

    func back() {
        problem = nil
        step = .draft
    }

    func sign() {
        guard let prepared else { return }
        step = .sign
        problem = nil
        task = Task { await signAndRecord(prepared) }
    }

    func signAndRecord(_ prepared: Prepared) async {
        let model = model
        let file: String
        do {
            let key = try await model.signing.signingKey(keys: model.keys)
            file = try await model.signing.sign(prepared.text, with: key)
        } catch let error as NoSigningKey {
            problem = error.message
            step = .check
            return
        } catch GnuPGError.cancelled {
            step = .check
            return
        } catch let error as GnuPGError where error.isBadPIN {
            await model.refreshCard()
            problem = wrongPIN(triesLeft: model.card?.pinTriesLeft)
            step = .check
            return
        } catch {
            problem = message(error)
            step = .check
            return
        }
        let change: Change
        do {
            (_, change) = try licenceChange(prepared: prepared, signedFile: file, keys: model.keys, register: model.register)
        } catch {
            problem = error.message
            step = .check
            return
        }
        signedFile = file
        step = .recording
        await run(change, on: model) { [weak self] state in self?.recording = state }
        if !isShown {
            model.recordingInBackground -= 1
            switch recording {
            case .recorded: model.notifier.recorded(prepared.licence)
            case .failed(let why): model.notifier.notRecorded(prepared.licence.licensee, why: String(localized: why))
            default: break
            }
        }
    }

    /// Cancel before recording starts; later, the sheet only closes.
    func close() {
        if step == .sign { task?.cancel() }
        if step == .recording, case .inProgress = recording {
            isShown = false
            model.recordingInBackground += 1
        }
        model.issue = nil
    }

    /// The licence as recorded, for Download to Downloads.
    var recordedEntry: Entry? { prepared.flatMap { model.register.entry($0.licence.id) } }
}

// MARK: - Revoke

/// Revoking needs no signature; typing REVOKE is the deliberate step.
@Observable
final class RevokeFlow: Identifiable {
    let id = UUID()
    unowned let model: AppModel
    let entry: Entry
    var reason = ""
    var effective: Date
    var typed = ""
    var problem: LocalizedStringResource?
    var recording: Recording = .notStarted

    init(model: AppModel, entry: Entry) {
        self.model = model
        self.entry = entry
        effective = max(model.today, entry.licence.notBefore).start
    }

    var draft: RevokeDraft { RevokeDraft(reason: reason, effective: CivilDate(effective)) }
    var confirmed: Bool { typed == "REVOKE" }
    var canRevoke: Bool { confirmed && draft.problem(for: entry) == nil && recording == .notStarted }

    func revoke() async {
        do {
            let change = try draft.change(for: entry)
            await run(change, on: model) { [weak self] in self?.recording = $0 }
        } catch {
            problem = error.message
        }
    }
}

// MARK: - Stop using a key

/// A key that signs nothing new: handed over to a successor or lost (both
/// still trusted, so its licences stay valid), or retired because someone
/// else may hold it. Typing the reason's word is the deliberate step.
@Observable
final class StopKeyFlow: Identifiable {
    let id = UUID()
    unowned let model: AppModel
    var fingerprint: String
    var reason: KeyStatus = .handedOver
    var typed = ""
    var problem: LocalizedStringResource?
    var recording: Recording = .notStarted

    init(model: AppModel, fingerprint: String) {
        self.model = model
        self.fingerprint = fingerprint
    }

    var word: String {
        switch reason {
        case .handedOver: "HANDOVER"
        case .retired: "RETIRE"
        default: "LOST"
        }
    }

    var confirmed: Bool { typed == word }

    func record() async {
        do {
            let change = try stopKeyChange(fingerprint: fingerprint, to: reason, keys: model.keys, today: model.today)
            await run(change, on: model) { [weak self] in self?.recording = $0 }
        } catch {
            problem = error.message
        }
    }
}

// MARK: - Trust a new key

/// An owner records the key someone else set up, from the file Set Up a
/// YubiKey saved for them; typing TRUST is the deliberate step.
@Observable
final class TrustKeyFlow: Identifiable {
    let id = UUID()
    unowned let model: AppModel
    var request: KeyRequest?
    var fileName = ""
    var typed = ""
    var problem: LocalizedStringResource?
    var recording: Recording = .notStarted

    init(model: AppModel) {
        self.model = model
    }

    var confirmed: Bool { request != nil && typed == "TRUST" }

    func open(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            request = try KeyRequest(json: try Data(contentsOf: url))
            fileName = url.lastPathComponent
            problem = nil
        } catch let error as PreparationError {
            problem = error.message
        } catch {
            problem = message(error)
        }
    }

    func record() async {
        guard let request else { return }
        do {
            let change = try request.change(keys: model.keys, today: model.today)
            await run(change, on: model) { [weak self] in self?.recording = $0 }
        } catch {
            problem = error.message
        }
    }
}

// MARK: - Set up a YubiKey

/// The seven setup steps, each read back from the card, so a setup that
/// stopped halfway resumes where it stopped.
@Observable
final class SetupFlow {
    unowned let model: AppModel
    var probe: SetupProbe?
    var running: SetupStep?
    var status: LocalizedStringResource?
    var problem: LocalizedStringResource?
    var holder: String
    var recording: Recording = .notStarted
    /// Where the key was saved for an owner, by someone who holds no key yet.
    var savedForOwner: URL?
    /// The new key's fingerprint, to read out to the owner who trusts it.
    var savedFingerprint: String?

    init(model: AppModel) {
        self.model = model
        holder = model.name ?? ""
    }

    /// The PINs were changed on this card, remembered per serial number.
    func pinsChanged(_ serial: String?) -> Bool {
        guard let serial else { return false }
        return UserDefaults.standard.bool(forKey: "pinsChanged.\(serial)")
    }

    func refresh() async {
        probe = await model.signing.probe(keys: model.keys, pinsChanged: pinsChanged(model.card?.serial))
        model.card = probe?.card
    }

    func run(_ step: SetupStep) async {
        running = step
        problem = nil
        status = nil
        defer { running = nil }
        do {
            try await model.signing.run(step, card: probe?.card) { line in
                if let words = describeStatus(line) { Task { @MainActor in self.status = words } }
            }
            if step == .changePINs, let serial = probe?.card?.serial {
                UserDefaults.standard.set(true, forKey: "pinsChanged.\(serial)")
            }
        } catch {
            problem = error.message
        }
        await refresh()
    }

    /// The PINs of this card were changed before, outside the app.
    func pinsAlreadyChanged() async {
        guard let serial = probe?.card?.serial else { return }
        UserDefaults.standard.set(true, forKey: "pinsChanged.\(serial)")
        await refresh()
    }

    /// The last step: the public key and the holder. Someone who holds an
    /// active key records it as a pull request; anyone else saves it for an
    /// owner, because only a key holder's account may change the keys.
    func trust() async {
        guard let card = probe?.card, let fpr = card.signatureKey else { return }
        do {
            let certificate = try await model.signing.exportPublic(fpr)
            if model.isActiveHolder {
                let change = try trustChange(
                    certificate: certificate, holder: holder, medium: "YubiKey \(card.serial)", github: model.login,
                    keys: model.keys, today: model.today)
                await FerroLICENCE.run(change, on: model) { [weak self] in self?.recording = $0 }
            } else if let login = model.login {
                let name = holder.trimmingCharacters(in: .whitespaces)
                let request = KeyRequest(holder: name, github: login, medium: "YubiKey \(card.serial)", certificate: certificate)
                savedForOwner = try model.saveInDownloads(request.json, named: "\(slug(name)).key.json")
                savedFingerprint = request.fingerprint
            }
            await refresh()
        } catch let error as GnuPGError {
            problem = error.message
        } catch let error as PreparationError {
            problem = error.message
        } catch {
            problem = message(error)
        }
    }
}
