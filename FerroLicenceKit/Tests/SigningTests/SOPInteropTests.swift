import Foundation
import LicenceCore
import Register
import Testing

@testable import Signing

/// The proof that a licence `ferrohealth-sop` signs with an RFC 9980 ID 30
/// key passes FerroEHR's checks and the Register check through every flow
/// the app records, and that the kit and `ferrohealth-sop` agree on each
/// other's signatures. Software keys in a throwaway folder only. CI sets
/// `FERROLICENCE_REQUIRE_SOP=1`, so a missing program fails there.
@Suite("ferrohealth-sop interop", .serialized, .enabled(if: SOPHome.available))
struct SOPInteropTests {
    let today = CivilDate("2026-11-25")!

    func base(_ keys: [(SoftwareID30Key, String)]) throws -> Snapshot {
        var files: [String: Data] = [:]
        var signers: [Signer] = []
        for (key, holder) in keys {
            let fpr = try #require(key.fingerprint)
            files["keys/\(fpr).asc"] = Data(key.certificate.utf8)
            signers.append(
                Signer(
                    fingerprint: fpr, holder: holder, medium: "software key", added: today, status: .active,
                    github: holder.lowercased().replacingOccurrences(of: " ", with: "-")))
        }
        files["signers.json"] = Keys.encode(signers)
        return Snapshot(files: files)
    }

    func issue(_ draft: Draft, by key: SoftwareID30Key, on snapshot: Snapshot) async throws -> (Prepared, Change) {
        let prepared = try Prepared(draft, today: today)
        let file = try await key.token(for: prepared.text)
        let (_, change) = try licenceChange(
            prepared: prepared, signedFile: file, keys: Keys(snapshot), register: LicenceRegister(snapshot))
        return (prepared, change)
    }

    @Test func anID30LicenceIsRecordedAndPassesTheRegisterCheck() async throws {
        let home = try SOPHome()
        defer { home.remove() }
        let key = try await home.key("Holder")
        let fpr = try #require(key.fingerprint)
        #expect(fpr.count == 64)
        let base = try base([(key, "Test Holder")])

        let draft = Draft(licensee: "Zorg & Co “Noord”", use: .commercial, notBefore: today, notAfter: today.oneYearLater, contract: "C-17")
        let (prepared, change) = try await issue(draft, by: key, on: base)
        let file = try #require(change.writes.first { $0.key.hasSuffix("licence.asc") }.map { String(decoding: $0.value, as: UTF8.self) })
        #expect(!file.contains("Hash:"))
        let verified = try verify(try Token(file), anchors: Keys(base).certificates, on: today)
        #expect(verified.licence == prepared.licence)
        #expect(verified.signer == fpr)

        let outcome = RegisterCheck.run(base: base, head: base.applying(change))
        #expect(outcome.passed, "\(outcome.problems)")
        #expect(RegisterCheck.authorProblems("test-holder", base: base, outcome: outcome).isEmpty)
        #expect(!RegisterCheck.authorProblems("someone-else", base: base, outcome: outcome).isEmpty)
    }

    /// Renew, revoke, trust a new key, then mark a key lost, handed over or
    /// retired: each change passes the Register check, and a key that stopped
    /// signs nothing new.
    @Test func everyRegisterFlowWorksWithID30Keys() async throws {
        let home = try SOPHome()
        defer { home.remove() }
        let a = try await home.key("A")
        let b = try await home.key("B")
        let c = try await home.key("C")
        var main = try base([(a, "Holder A"), (b, "Holder B")])

        let (first, issued) = try await issue(
            Draft(licensee: "Acme", use: .commercial, notBefore: today, notAfter: today.oneYearLater), by: a, on: main)
        #expect(RegisterCheck.run(base: main, head: main.applying(issued)).passed)
        main = main.applying(issued)
        let entry = try #require(LicenceRegister(main).entry(first.licence.id))

        let (_, renewal) = try await issue(.renewal(of: entry, today: today), by: b, on: main)
        let renewed = RegisterCheck.run(base: main, head: main.applying(renewal))
        #expect(renewed.passed, "\(renewed.problems)")

        let revocation = try RevokeDraft(reason: "Clause 9.2", effective: today).change(for: entry)
        let revoked = RegisterCheck.run(base: main, head: main.applying(revocation))
        #expect(revoked.passed, "\(revoked.problems)")

        let request = KeyRequest(holder: "Holder C", github: "holder-c", medium: "software key", certificate: c.certificate)
        let trusted = RegisterCheck.run(base: main, head: main.applying(try request.change(keys: Keys(main), today: today)))
        #expect(trusted.passed, "\(trusted.problems)")
        #expect(trusted.findings == [.trusted(fingerprint: try #require(c.fingerprint))])

        let aFingerprint = try #require(a.fingerprint)
        for status in [KeyStatus.lost, .handedOver, .retired] {
            let stop = try stopKeyChange(fingerprint: aFingerprint, to: status, keys: Keys(main), today: today)
            let stopped = main.applying(stop)
            #expect(RegisterCheck.run(base: main, head: stopped).passed, "\(status)")
            // A retired key is no longer trusted, so recording refuses its licence first.
            do {
                let (_, late) = try await issue(
                    Draft(licensee: "Late", use: .commercial, notBefore: today, notAfter: today), by: a, on: stopped)
                #expect(status != .retired)
                #expect(!RegisterCheck.run(base: stopped, head: stopped.applying(late)).passed, "\(status)")
            } catch RecordingError.refused(.untrustedPrimary) {
                #expect(status == .retired)
            }
        }
    }

    @Test func theKitAndFerrohealthSopAgreeOnEachOthersSignatures() async throws {
        let home = try SOPHome()
        defer { home.remove() }
        let vectors = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../LicenceCoreTests/Vectors/id30").standardized
        for (name, valid) in [
            ("ok_a", true), ("ok_b_sha512", true), ("tampered", false), ("weak_digest", false), ("mldsa_half_broken", false),
        ] {
            let text = try String(contentsOf: vectors.appending(path: "tokens/\(name).asc"), encoding: .utf8)
            let begin = try #require(text.range(of: "-----BEGIN PGP SIGNATURE-----"))
            let end = try #require(text.range(of: "-----END PGP SIGNATURE-----"))
            let signature = home.url.appending(path: "\(name).sig")
            try String(text[begin.lowerBound..<end.upperBound]).write(to: signature, atomically: true, encoding: .utf8)
            let anchor = vectors.appending(path: name == "ok_b_sha512" ? "anchors/B.asc" : "anchors/A.asc")
            let signedText = try Token(text).signedText
            if valid {
                #expect(try await home.sop.verify(signedText, signatures: signature, certificates: [anchor]).count == 1, "\(name)")
            } else {
                await #expect(throws: SOPError.self, "\(name)") {
                    try await home.sop.verify(signedText, signatures: signature, certificates: [anchor])
                }
            }
        }
    }

    @Test func aMissingProgramIsNotInstalled() async {
        let missing = SOP(executable: URL(filePath: "/nonexistent/ferrohealth-sop"))
        await #expect(throws: SOPError.notInstalled) { try await missing.sign("x", keys: URL(filePath: "/nonexistent")) }
    }
}

@Test func soPExitCodesAreTypedFailures() {
    #expect(SOPFailure(exitCode: 3) == .noSignature)
    #expect(SOPFailure(exitCode: 13) == .unsupportedAlgorithm)
    #expect(SOPFailure(exitCode: 41) == .badData)
    #expect(SOPFailure(exitCode: 67) == .keyIsProtected)
    #expect(SOPFailure(exitCode: 79) == .keyCannotSign)
    #expect(SOPFailure(exitCode: 97) == .noHardwareKey)
    #expect(SOPFailure(exitCode: 101) == .hardwareKeyFailure)
    #expect(SOPFailure(exitCode: 2) == .other(2))
}

/// A throwaway folder under `/tmp` for software ID 30 keys.
struct SOPHome {
    static let installed = SOP.find()
    static var available: Bool {
        installed != nil || ProcessInfo.processInfo.environment["FERROLICENCE_REQUIRE_SOP"] == "1"
    }

    let url: URL
    let sop: SOP

    init() throws {
        sop = try #require(Self.installed, "ferrohealth-sop is not installed; FERROLICENCE_REQUIRE_SOP=1 needs it")
        url = URL(filePath: "/tmp").appending(path: "fl-sop-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    /// A software ID 30 key that certifies and signs, and its certificate.
    func key(_ name: String) async throws -> SoftwareID30Key {
        let file = url.appending(path: "\(name).key")
        try await sop.generateKey(userID: "Throwaway \(name) <\(name.lowercased())@example.invalid>", into: file)
        return SoftwareID30Key(sop: sop, keys: file, certificate: try await sop.extractCert(keys: file))
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}
