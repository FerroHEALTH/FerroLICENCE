import Foundation
import LicenceCore
import Register
import Testing

/// The Register check on changes made to the committed register. New
/// licences need a trusted signature, so they are checked in SigningTests
/// with a throwaway GnuPG key.
@Suite("The Register check")
struct RegisterCheckTests {
    let base = repository
    let keys = try! Keys(repository)
    let register = try! LicenceRegister(repository)
    let today = CivilDate("2026-10-24")!

    func check(_ change: Change) -> RegisterCheck.Outcome { RegisterCheck.run(base: base, head: base.applying(change)) }

    func check(_ edit: (inout Snapshot) -> Void) -> RegisterCheck.Outcome {
        var head = base
        edit(&head)
        return RegisterCheck.run(base: base, head: head)
    }

    var inForce: Entry { register.entries.first { $0.licence.notAfter > today && $0.revocation == nil }! }

    /// A licence signed by a key `main` still trusts.
    var trustedlySigned: Entry { register.entries.first { keys.isTrusted($0.record.signer) }! }

    @Test func passesARevocationTheAppMakes() throws {
        let change = try RevokeDraft(reason: "Clause 9.2", effective: today).change(for: inForce)
        let outcome = check(change)
        #expect(outcome.passed, "\(outcome.problems)")
        #expect(outcome.findings == [.revocation(folder: inForce.folder, effective: today)])
    }

    /// The check as the app runs it before recording, with the GitHub
    /// account that records the change.
    @Test func theAppRecordsARevocationOnlyFromAnActiveHolder() throws {
        let change = try RevokeDraft(reason: "Clause 9.2", effective: today).change(for: inForce)
        try RegisterCheck.check(change, on: base, by: "rubentalstra")
        #expect(throws: RegisterCheck.Refused.self) { try RegisterCheck.check(change, on: base, by: "someone-else") }
    }

    @Test func theAppRecordsNoEditOfALicenceFile() {
        var edited = base.files[inForce.licenceFile]!
        edited.append(contentsOf: Data(" ".utf8))
        let change = Change(kind: .licence, writes: [inForce.licenceFile: edited], branch: "licence/x", title: "x", body: "")
        #expect {
            try RegisterCheck.check(change, on: base, by: "rubentalstra")
        } throws: { error in
            (error as? RegisterCheck.Refused)?.problems.contains("\(inForce.licenceFile) was changed; the register is append-only") == true
        }
    }

    @Test func refusesARevocationOutsideTheLicence() {
        let r = Revocation(licenceID: inForce.id, effective: inForce.licence.notBefore.adding(days: -1), reason: "x", recordedAt: Date())
        #expect(!check { $0.files["\(inForce.folder)/revocation.json"] = r.json }.passed)
    }

    @Test func refusesARevocationOfAnotherLicence() {
        let r = Revocation(licenceID: UUID(), effective: today, reason: "x", recordedAt: Date())
        #expect(!check { $0.files["\(inForce.folder)/revocation.json"] = r.json }.passed)
    }

    @Test func refusesAChangedLicenceFile() {
        let outcome = check { $0.files[inForce.licenceFile]!.append(contentsOf: Data(" ".utf8)) }
        #expect(outcome.problems.contains("\(inForce.licenceFile) was changed; the register is append-only"))
    }

    @Test func refusesARemovedLicence() {
        #expect(!check { $0.files["\(inForce.folder)/record.json"] = nil }.passed)
    }

    @Test func refusesALicenceWithoutRecord() {
        #expect(!check { $0.files["register/acme/\(UUID().uuidString.lowercased())/licence.asc"] = $0.files[inForce.licenceFile] }.passed)
    }

    @Test func refusesAFileAtTheWrongDepth() {
        #expect(!check { $0.files["register/acme/notes.json"] = Data("{}".utf8) }.passed)
    }

    @Test func refusesACopiedLicenceUnderANewID() {
        let id = UUID().uuidString.lowercased()
        let outcome = check {
            $0.files["register/acme/\(id)/licence.asc"] = $0.files[trustedlySigned.licenceFile]
            $0.files["register/acme/\(id)/record.json"] = $0.files["\(trustedlySigned.folder)/record.json"]
        }
        #expect(outcome.problems.contains { $0.contains("should be register/") })
        #expect(outcome.problems.contains { $0.contains("already in the register") })
    }

    @Test func passesMarkingAKeyLost() throws {
        let fpr = keys.trusted[0].fingerprint
        let outcome = check(try stopKeyChange(fingerprint: fpr, to: .lost, keys: keys, today: today))
        #expect(outcome.passed, "\(outcome.problems)")
        #expect(outcome.findings == [.statusChanged(fingerprint: fpr, to: .lost)])
    }

    @Test func passesHandingAKeyOver() throws {
        let fpr = keys.trusted[0].fingerprint
        let change = try stopKeyChange(fingerprint: fpr, to: .handedOver, keys: keys, today: today)
        #expect(change.title.hasSuffix("as handed over"))
        let outcome = check(change)
        #expect(outcome.passed, "\(outcome.problems)")
        #expect(outcome.findings == [.statusChanged(fingerprint: fpr, to: .handedOver)])
        let after = try Keys(base.applying(change))
        #expect(after.signer(fpr)?.status == .handedOver)
        #expect(after.isTrusted(fpr))
    }

    @Test func aHandedOverKeyCanBeRetiredAndNothingElse() throws {
        let fpr = keys.trusted[0].fingerprint
        let handedOver = base.applying(try stopKeyChange(fingerprint: fpr, to: .handedOver, keys: keys, today: today))
        let keysAfter = try Keys(handedOver)
        let retired = RegisterCheck.run(
            base: handedOver, head: handedOver.applying(try stopKeyChange(fingerprint: fpr, to: .retired, keys: keysAfter, today: today)))
        #expect(retired.passed, "\(retired.problems)")
        #expect(throws: PreparationError.self) { try stopKeyChange(fingerprint: fpr, to: .lost, keys: keysAfter, today: today) }
        var signers = keysAfter.signers
        let i = try #require(signers.firstIndex { $0.fingerprint == fpr })
        signers[i].status = .active
        var head = handedOver
        head.files["signers.json"] = Keys.encode(signers)
        #expect(!RegisterCheck.run(base: handedOver, head: head).passed)
    }

    @Test func theLastKeyInUseIsNotHandedOver() throws {
        let fpr = keys.trusted[0].fingerprint
        let one = base.applying(try stopKeyChange(fingerprint: keys.trusted[1].fingerprint, to: .lost, keys: keys, today: today))
        #expect(throws: PreparationError.self) { try stopKeyChange(fingerprint: fpr, to: .handedOver, keys: Keys(one), today: today) }
        #expect(throws: PreparationError.self) { try stopKeyChange(fingerprint: fpr, to: .active, keys: keys, today: today) }
    }

    @Test func passesRetiringAKey() throws {
        let outcome = check(try stopKeyChange(fingerprint: keys.trusted[1].fingerprint, to: .retired, keys: keys, today: today))
        #expect(outcome.passed, "\(outcome.problems)")
    }

    @Test func refusesRetiringWithoutMovingTheCertificate() throws {
        var change = try stopKeyChange(fingerprint: keys.trusted[1].fingerprint, to: .retired, keys: keys, today: today)
        change.deletes = []
        #expect(!check(change).passed)
    }

    @Test func refusesBringingARetiredKeyBack() {
        var signers = keys.signers
        let i = signers.firstIndex { $0.status == .retired }!
        signers[i].status = .active
        #expect(!check { $0.files["signers.json"] = Keys.encode(signers) }.passed)
    }

    @Test func refusesRenamingAHolder() {
        var signers = keys.signers
        signers[0].holder = "Someone Else"
        #expect(check { $0.files["signers.json"] = Keys.encode(signers) }.problems.contains { $0.contains("more than the status") })
    }

    @Test func refusesDroppingASignerRow() {
        let signers = Array(keys.signers.dropLast())
        #expect(!check { $0.files["signers.json"] = Keys.encode(signers) }.passed)
    }

    @Test func refusesACertificateWithoutARow() {
        #expect(!check { $0.files["keys/0000000000000000000000000000000000000000.asc"] = Data(keys.trusted[0].armored.utf8) }.passed)
    }

    @Test func refusesAKeyFileThatIsNotACertificate() {
        #expect(!check { $0.files["keys/x.asc"] = Data("not a certificate\n".utf8) }.passed)
    }

    @Test func summarisesForTheJobPage() throws {
        let change = try RevokeDraft(reason: "Clause 9.2", effective: today).change(for: inForce)
        #expect(check(change).summary(keys: keys).contains("Revocation from 2026-10-24"))
        #expect(check { $0.files["register/acme/notes.json"] = Data() }.summary(keys: keys).contains("**Refused:**"))
    }

    /// The committed register as it was before anyone had a GitHub login.
    var withoutLogins: Snapshot {
        let signers = keys.signers.map { s -> Signer in
            var s = s
            s.github = nil
            return s
        }
        return Snapshot(files: base.files.merging(["signers.json": Keys.encode(signers)]) { $1 })
    }

    @Test func passesGivingAHolderTheirGitHubLogin() throws {
        let before = withoutLogins
        var signers = try Keys(before).signers
        let i = try #require(signers.firstIndex { $0.status == .active })
        signers[i].github = "rubentalstra"
        var head = before
        head.files["signers.json"] = Keys.encode(signers)
        let outcome = RegisterCheck.run(base: before, head: head)
        #expect(outcome.passed, "\(outcome.problems)")
        #expect(outcome.findings == [.githubLogin(fingerprint: signers[i].fingerprint, login: "rubentalstra")])
    }

    @Test func refusesChangingAGitHubLoginOnceGiven() throws {
        var signers = keys.signers
        let i = try #require(signers.firstIndex { $0.github != nil })
        signers[i].github = "someone-else"
        #expect(!check { $0.files["signers.json"] = Keys.encode(signers) }.passed)
    }

    @Test func refusesALoginThatIsNotALogin() throws {
        let before = withoutLogins
        var signers = try Keys(before).signers
        let i = try #require(signers.firstIndex { $0.status == .active })
        signers[i].github = "ruben talstra; rm"
        var head = before
        head.files["signers.json"] = Keys.encode(signers)
        #expect(!RegisterCheck.run(base: before, head: head).passed)
    }

    // MARK: Who may open the pull request

    @Test func aRevocationComesFromAnActiveKeyHolder() throws {
        let outcome = check(try RevokeDraft(reason: "Clause 9.2", effective: today).change(for: inForce))
        for holder in ["rubentalstra", "AlessandroTorrisi", "alessandrotorrisi"] {
            #expect(RegisterCheck.authorProblems(holder, base: base, outcome: outcome).isEmpty, "\(holder)")
        }
        #expect(
            RegisterCheck.authorProblems("stranger", base: base, outcome: outcome) == [
                "\(inForce.folder) may be revoked only by an active key holder's GitHub account, not `stranger`"
            ])
    }

    @Test func aKeyChangeComesFromAnActiveKeyHolder() throws {
        let fpr = try #require(keys.signers.first { $0.status == .active }).fingerprint
        let outcome = check(try stopKeyChange(fingerprint: fpr, to: .lost, keys: keys, today: today))
        #expect(outcome.passed, "\(outcome.problems)")
        #expect(RegisterCheck.authorProblems("rubentalstra", base: base, outcome: outcome).isEmpty)
        #expect(
            RegisterCheck.authorProblems("stranger", base: base, outcome: outcome) == [
                "the keys may be changed only by an active key holder's GitHub account, not `stranger`"
            ])
    }

    @Test func aGitHubLoginIsGivenOnlyByThatLogin() throws {
        let before = withoutLogins
        var signers = try Keys(before).signers
        let i = try #require(signers.firstIndex { $0.status == .active })
        signers[i].github = "rubentalstra"
        var head = before
        head.files["signers.json"] = Keys.encode(signers)
        let outcome = RegisterCheck.run(base: before, head: head)
        #expect(RegisterCheck.authorProblems("rubentalstra", base: before, outcome: outcome).isEmpty)
        #expect(
            RegisterCheck.authorProblems("AlessandroTorrisi", base: before, outcome: outcome) == [
                "only `rubentalstra` may give \(short(signers[i].fingerprint)) the GitHub login `rubentalstra`, not `AlessandroTorrisi`"
            ])
    }

    @Test func aPullRequestThatChangesNothingNeedsNoHolder() {
        let outcome = RegisterCheck.run(base: base, head: base)
        #expect(RegisterCheck.authorProblems("anyone", base: base, outcome: outcome).isEmpty)
    }
}
