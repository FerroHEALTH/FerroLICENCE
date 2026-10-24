import Foundation
import LicenceCore
import Register
import Testing

@testable import Signing

/// The proof that a licence GnuPG signs passes FerroEHR's checks, is
/// recorded, and passes the Register check. It runs in a throwaway GnuPG
/// home with a software key and never touches the developer's keyring. CI
/// sets `FERROLICENCE_REQUIRE_GPG=1`, so a missing `gpg` fails there instead
/// of skipping.
@Suite("GnuPG interop", .serialized, .enabled(if: Throwaway.available))
struct InteropTests {
    @Test func aLicenceSignedByGnuPGIsRecordedAndPassesTheRegisterCheck() async throws {
        let home = try await Throwaway()
        defer { home.remove() }
        let fpr = try await home.generate()
        let certificate = try await home.gpg.exportPublic(fpr)
        #expect(certificate.hasPrefix("-----BEGIN PGP PUBLIC KEY BLOCK-----"))

        let base = Snapshot(files: [
            "keys/\(fpr).asc": Data(certificate.utf8),
            "signers.json": Keys.encode([
                Signer(
                    fingerprint: fpr, holder: "Test Holder", medium: "software key",
                    added: CivilDate("2026-10-24")!, status: .active, github: "test-holder")
            ]),
        ])
        let keys = try Keys(base)
        let today = CivilDate("2026-10-24")!
        let prepared = try Prepared(
            Draft(
                licensee: "Zorg & Co “Noord”", use: .commercial, notBefore: today,
                notAfter: today.oneYearLater, contract: "C-17"), today: today)
        let file = try await home.gpg.sign(prepared.text, with: .softwareForTests(fpr))

        let verified = try verify(try Token(file), anchors: keys.certificates, on: today)
        #expect(verified.licence == prepared.licence)
        #expect(verified.signer == fpr)

        let (record, change) = try licenceChange(prepared: prepared, signedFile: file, keys: keys, register: LicenceRegister())
        #expect(record.contract == "C-17")
        #expect(
            change.writes.keys.sorted() == [
                "register/zorg-co-noord/\(prepared.licence.id.uuidString.lowercased())/licence.asc",
                "register/zorg-co-noord/\(prepared.licence.id.uuidString.lowercased())/record.json",
            ])
        let outcome = RegisterCheck.run(base: base, head: base.applying(change))
        #expect(outcome.passed, "\(outcome.problems)")
        #expect(
            outcome.findings == [
                .licence(
                    folder: "register/zorg-co-noord/\(prepared.licence.id.uuidString.lowercased())",
                    licensee: "Zorg & Co “Noord”", notAfter: today.oneYearLater, signer: fpr)
            ])

        // Only the signer's own GitHub account may record it.
        #expect(RegisterCheck.authorProblems("test-holder", base: base, outcome: outcome).isEmpty)
        #expect(RegisterCheck.authorProblems("Test-Holder", base: base, outcome: outcome).isEmpty)
        #expect(
            RegisterCheck.authorProblems("someone-else", base: base, outcome: outcome) == [
                "register/zorg-co-noord/\(prepared.licence.id.uuidString.lowercased()) is signed with Test Holder's key, so only Test Holder's GitHub account may record it, not `someone-else`"
            ])
    }

    @Test func aNewHoldersKeyIsTrustedFromAnOwnersAccount() async throws {
        // Two people, two Macs: each has a GnuPG home of their own.
        let ownersMac = try await Throwaway()
        defer { ownersMac.remove() }
        let newcomersMac = try await Throwaway()
        defer { newcomersMac.remove() }
        let owner = try await ownersMac.generate()
        let newcomer = try await newcomersMac.generate()
        let base = Snapshot(files: [
            "keys/\(owner).asc": Data(try await ownersMac.gpg.exportPublic(owner).utf8),
            "signers.json": Keys.encode([
                Signer(
                    fingerprint: owner, holder: "Owner", medium: "YubiKey 1", added: CivilDate("2026-10-07")!, status: .active,
                    github: "owner")
            ]),
        ])

        // Written by Set Up a YubiKey on the newcomer's Mac, read on the owner's.
        let written = KeyRequest(
            holder: "New Holder", github: "newcomer", medium: "YubiKey 2", certificate: try await newcomersMac.gpg.exportPublic(newcomer))
        let request = try KeyRequest(json: written.json)
        #expect(request == written)
        #expect(request.fingerprint == newcomer)

        let today = CivilDate("2026-10-24")!
        let outcome = RegisterCheck.run(base: base, head: base.applying(try request.change(keys: Keys(base), today: today)))
        #expect(outcome.passed, "\(outcome.problems)")
        #expect(outcome.findings == [.trusted(fingerprint: newcomer)])
        #expect(RegisterCheck.authorProblems("owner", base: base, outcome: outcome).isEmpty)
        #expect(!RegisterCheck.authorProblems("newcomer", base: base, outcome: outcome).isEmpty)
        #expect(
            try Keys(base.applying(try request.change(keys: Keys(base), today: today))).signer(github: "newcomer")?.fingerprint == newcomer)
    }

    @Test func aKeyThatStoppedSigningSignsNothingNew() async throws {
        let home = try await Throwaway()
        defer { home.remove() }
        let fpr = try await home.generate()
        let certificate = try await home.gpg.exportPublic(fpr)
        let today = CivilDate("2026-10-24")!
        let prepared = try Prepared(Draft(licensee: "Acme", use: .commercial, notBefore: today, notAfter: today), today: today)
        let file = try await home.gpg.sign(prepared.text, with: .softwareForTests(fpr))
        for status in [KeyStatus.lost, .handedOver] {
            let base = Snapshot(files: [
                "keys/\(fpr).asc": Data(certificate.utf8),
                "signers.json": Keys.encode([
                    Signer(fingerprint: fpr, holder: "Old Holder", medium: "YubiKey 1", added: today, status: status, since: today)
                ]),
            ])
            let (_, change) = try licenceChange(prepared: prepared, signedFile: file, keys: Keys(base), register: LicenceRegister())
            let outcome = RegisterCheck.run(base: base, head: base.applying(change))
            #expect(outcome.problems.contains { $0.hasSuffix("which is marked \(status.rawValue)") }, "\(status)")
        }
    }

    @Test func aKeyRequestIsReadStrictly() {
        #expect(throws: PreparationError.self) { try KeyRequest(json: Data("{}".utf8)) }
        var wrong = KeyRequest(holder: "A", github: "a b", medium: "YubiKey 1", certificate: "")
        #expect(throws: PreparationError.self) { try KeyRequest(json: wrong.json) }
        wrong.github = "a"
        wrong.format = "something-else"
        #expect(throws: PreparationError.self) { try KeyRequest(json: wrong.json) }
    }

    @Test func aLicenceSignedByAnUntrustedKeyIsRefused() async throws {
        let home = try await Throwaway()
        defer { home.remove() }
        let fpr = try await home.generate()
        let today = CivilDate("2026-10-24")!
        let prepared = try Prepared(Draft(licensee: "Acme", use: .commercial, notBefore: today, notAfter: today), today: today)
        let file = try await home.gpg.sign(prepared.text, with: .softwareForTests(fpr))

        #expect(throws: RecordingError.refused(.untrustedPrimary(fingerprint: fpr))) {
            try licenceChange(prepared: prepared, signedFile: file, keys: Keys(), register: LicenceRegister())
        }
        let folder = "register/acme/\(prepared.licence.id.uuidString.lowercased())"
        let head = Snapshot(files: [
            "\(folder)/licence.asc": Data(file.utf8),
            "\(folder)/record.json": Record(
                licence: prepared.licence, signer: fpr, tokenSHA256: sha256Hex(Data(file.utf8)),
                contract: nil, renews: nil, recordedAt: Date()
            ).json,
        ])
        #expect(!RegisterCheck.run(base: Snapshot(), head: head).passed)
    }

    @Test func aSoftwareKeyNeverBecomesASigningKey() async throws {
        let home = try await Throwaway()
        defer { home.remove() }
        let fpr = try await home.generate()
        let certificate = try await home.gpg.exportPublic(fpr)
        let keys = try Keys(Snapshot(files: ["keys/\(fpr).asc": Data(certificate.utf8)]))
        // Whatever card is plugged in, it does not hold this key.
        await #expect(throws: NoSigningKey.self) { try await home.gpg.signingKey(keys: keys) }
    }

    @Test func aDraftWithADifferentTextIsRefused() async throws {
        let home = try await Throwaway()
        defer { home.remove() }
        let fpr = try await home.generate()
        let certificate = try await home.gpg.exportPublic(fpr)
        let keys = try Keys(Snapshot(files: ["keys/\(fpr).asc": Data(certificate.utf8)]))
        let today = CivilDate("2026-10-24")!
        let signedFor = try Prepared(Draft(licensee: "Acme", use: .commercial, notBefore: today, notAfter: today), today: today)
        let other = try Prepared(Draft(licensee: "Acme", use: .commercial, notBefore: today, notAfter: today), today: today)
        let file = try await home.gpg.sign(signedFor.text, with: .softwareForTests(fpr))
        #expect(throws: RecordingError.different) {
            try licenceChange(prepared: other, signedFile: file, keys: keys, register: LicenceRegister())
        }
    }

    @Test func cancellingStopsTheProcess() async throws {
        let started = ContinuousClock.now
        let task = Task { try await Command.run(URL(filePath: "/bin/sleep"), ["30"]) }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        await #expect(throws: GnuPGError.cancelled) { try await task.value }
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test func tooMuchOutputIsAFailureNotAMissingGnuPG() async {
        let error = await #expect(throws: GnuPGError.self) { try await Command.run(URL(filePath: "/usr/bin/yes"), []) }
        #expect(error != .notInstalled)
    }

    @Test func aMissingProgramIsNotInstalled() async {
        await #expect(throws: GnuPGError.notInstalled) { try await Command.run(URL(filePath: "/nonexistent/gpg"), []) }
    }
}

/// A GnuPG home in `/tmp`, short enough for the agent's socket path.
struct Throwaway {
    static let installed = GnuPG.find()
    static var available: Bool {
        installed != nil || ProcessInfo.processInfo.environment["FERROLICENCE_REQUIRE_GPG"] == "1"
    }

    let url: URL
    let gpg: GnuPG

    init() async throws {
        let found = try #require(Self.installed, "gpg is not installed; FERROLICENCE_REQUIRE_GPG=1 needs it")
        url = URL(filePath: "/tmp").appending(path: "fl-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        gpg = GnuPG(executable: found.executable, home: url, loopbackPassphrase: "")
    }

    /// An Ed25519 primary that certifies and signs, as the YubiKey makes.
    func generate() async throws -> String {
        _ = try await gpg.run(["--quick-generate-key", "Throwaway <throwaway@example.invalid>", "ed25519", "cert,sign", "never"])
        let listing = try await gpg.run(["--with-colons", "--with-fingerprint", "--list-keys"])
        return try #require(PublicPrimary.parse(listing)).fingerprint
    }

    func remove() {
        let kill = Process()
        kill.executableURL = gpg.gpgconf
        kill.arguments = ["--homedir", url.path, "--kill", "all"]
        try? kill.run()
        kill.waitUntilExit()
        try? FileManager.default.removeItem(at: url)
    }
}
