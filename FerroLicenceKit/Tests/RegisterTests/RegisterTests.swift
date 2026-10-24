import Foundation
import LicenceCore
import Testing

@testable import Register

/// The real `keys/`, `signers.json` and `register/` as they were when the
/// register moved to its own repository (`Tests/RegisterSnapshot`).
let repository = Snapshot.readRepository()

extension Snapshot {
    static func readRepository() -> Snapshot {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "RegisterSnapshot")
        return try! Snapshot.read(folder: root)
    }
}

@Suite("The register as committed")
struct CommittedRegister {
    @Test func readsAndEveryFileIsIntact() throws {
        let register = try LicenceRegister(repository)
        #expect(register.entries.count >= 2)
        #expect(register.entries.allSatisfy { $0.integrity == .intact })
    }

    @Test func keysAgreeWithSigners() throws {
        let keys = try Keys(repository)
        #expect(keys.trusted.count == 2)
        #expect(keys.problems.isEmpty)
    }

    @Test func checksAgainstItself() {
        let outcome = RegisterCheck.run(base: repository, head: repository)
        #expect(outcome.passed, "\(outcome.problems)")
        #expect(outcome.findings.isEmpty)
    }

    @Test func recordsRoundTrip() throws {
        for entry in try LicenceRegister(repository).entries {
            let again = try Record(json: entry.record.json, path: "x")
            #expect(again == entry.record)
        }
    }
}

@Suite("Reading records strictly")
struct Records {
    let record = repository.paths(under: "register/").first { $0.hasSuffix("record.json") }!

    func mutated(_ edit: (inout [String: Any]) -> Void) -> Data {
        var o = try! JSONSerialization.jsonObject(with: repository.files[record]!) as! [String: Any]
        edit(&o)
        return try! JSONSerialization.data(withJSONObject: o)
    }

    @Test func refusesAnUnknownField() {
        #expect(throws: RegisterError.record("p", "unknown field colour")) {
            try Record(json: mutated { $0["colour"] = "blue" }, path: "p")
        }
    }

    @Test func refusesAnotherSchema() {
        #expect(throws: RegisterError.schema("p", 1)) { try Record(json: mutated { $0["schema"] = 1 }, path: "p") }
    }

    @Test func refusesAMissingSigner() {
        #expect(throws: RegisterError.record("p", "no signer")) { try Record(json: mutated { $0["signer"] = nil }, path: "p") }
    }

    @Test(arguments: ["2026-09-11T13:29:11.717597Z", "2026-09-11T13:29:11.717597123Z", "2026-09-11T13:29:11.717Z", "2026-09-11T13:29:11Z"])
    func readsTimestamps(_ text: String) throws {
        let date = try #require(Timestamp.parse(text))
        #expect(abs(date.timeIntervalSince1970 - 1_789_133_351.717) < 0.001 || text.hasSuffix(":11Z"))
    }
}

@Suite("Names and days")
struct Names {
    @Test(arguments: [("Acme B.V.", "acme-b-v"), ("  Zorg & Co  ", "zorg-co"), ("Ünïcode", "n-code"), ("!!!", "licensee")])
    func slugs(_ name: String, _ expected: String) { #expect(slug(name) == expected) }

    @Test func versionSevenIDsCarryTheTime() {
        let now = Date(timeIntervalSince1970: 1_790_000_000.123)
        let id = UUID.v7(now: now)
        #expect(id.timestampMs == 1_790_000_000_123)
        #expect(id.uuidString.dropFirst(14).first == "7")
    }

    @Test func groupsFingerprintsAsGnuPGPrintsThem() {
        #expect(grouped("F2D214FC30698BA65A846B2BF2EA48D4C316406D") == "F2D2 14FC 3069 8BA6 5A84  6B2B F2EA 48D4 C316 406D")
        #expect(short("F2D214FC30698BA65A846B2BF2EA48D4C316406D") == "F2D2…406D")
    }
}

@Suite("What needs the licensor")
struct Todos {
    func entry(_ customer: String, _ from: String, _ to: String, renews: UUID? = nil, revoked: String? = nil) -> Entry {
        let id = UUID()
        let licence = Licence(
            id: id, licensee: customer, issued: CivilDate(from)!, notBefore: CivilDate(from)!, notAfter: CivilDate(to)!,
            use: .commercial)
        let record = Record(licence: licence, signer: "F2D2", tokenSHA256: "", contract: nil, renews: renews, recordedAt: Date())
        return Entry(
            record: record,
            revocation: revoked.map { Revocation(licenceID: id, effective: CivilDate($0)!, reason: "r", recordedAt: Date()) },
            customer: slug(customer), folder: "register/\(slug(customer))/\(id)", integrity: .intact)
    }

    @Test func endingSoonComesBeforeEnded() {
        let today = CivilDate("2027-01-01")!
        let soon = entry("Soon", "2026-02-01", "2027-01-31")
        let ended = entry("Ended", "2025-11-01", "2026-12-01")
        let fine = entry("Fine", "2026-06-01", "2027-06-01")
        let todo = LicenceRegister(entries: [ended, fine, soon]).todo(on: today)
        #expect(
            todo == [
                .endingSoon(customer: "soon", licence: soon.id, daysLeft: 30),
                .endedWithoutRenewal(customer: "ended", licence: ended.id, daysAgo: 31),
            ])
    }

    @Test func aRenewalSilencesTheReminder() {
        let old = entry("Acme", "2026-02-01", "2027-01-31")
        let next = entry("Acme", "2027-02-01", "2028-01-31", renews: old.id)
        #expect(LicenceRegister(entries: [old, next]).todo(on: CivilDate("2027-01-01")!).isEmpty)
    }

    @Test func aRevokedRenewalDoesNot() {
        let old = entry("Acme", "2026-02-01", "2027-01-31")
        let next = entry("Acme", "2027-02-01", "2028-01-31", renews: old.id, revoked: "2027-02-01")
        #expect(LicenceRegister(entries: [old, next]).todo(on: CivilDate("2027-01-01")!).count == 1)
    }

    @Test func renewalStartsTheDayAfter() {
        let old = entry("Acme", "2026-02-01", "2027-01-31")
        let draft = Draft.renewal(of: old, today: CivilDate("2027-01-01")!)
        #expect(draft.notBefore == CivilDate("2027-02-01"))
        #expect(draft.notAfter == CivilDate("2028-01-31"))
        #expect(draft.renews == old.id)
    }
}
