import Foundation
import Testing

@testable import LicenceCore

@Test func armorRoundTripsAndChecksTheCRC() throws {
    let data = Data((0..<200).map { UInt8($0) })
    let text = Armor.encode(data, kind: "PGP SIGNATURE")
    #expect(try Armor.decode(text, kind: "PGP SIGNATURE") == data)
    let broken = text.replacingOccurrences(of: "\n=", with: "\n=A")
    #expect(throws: Armor.Failure.self) { try Armor.decode(String(broken.dropLast(0)), kind: "PGP SIGNATURE") }
    #expect(Armor.crc24(Data("123456789".utf8)) == 0x21CF02)
}

@Test func datesAreStrictAndOneYearEndsTheDayBeforeTheAnniversary() {
    #expect(CivilDate("2027-13-01") == nil)
    #expect(CivilDate("2027-02-29") == nil)
    #expect(CivilDate("2027-1-01") == nil)
    let cases = [
        ("2026-10-01", "2027-09-30"), ("2026-12-31", "2027-12-30"), ("2026-01-01", "2026-12-31"),
        ("2028-02-29", "2029-02-28"), ("2027-03-01", "2028-02-29"), ("2028-03-01", "2029-02-28"),
    ]
    for (first, last) in cases {
        #expect(CivilDate(first)!.oneYearLater.description == last, "from \(first)")
    }
    #expect(CivilDate("2026-10-23")!.days(until: CivilDate("2026-11-30")!) == 38)
}

@Test func licencesAreReadStrictly() throws {
    let good = """
        {"licence_id": "019a1171-8f20-7b3e-a5c4-2e9d7f60b1a8", "licensee": "X", "issued": "2026-10-24",
         "not_before": "2026-11-01", "not_after": "2027-10-31", "use": "commercial"}
        """
    #expect(try Licence.parse(good).use == .commercial)
    #expect(throws: Licence.Failure.field("seats")) {
        try Licence.parse(good.replacingOccurrences(of: "\"use\"", with: "\"seats\": 5, \"use\""))
    }
    #expect(throws: Licence.Failure.field("use")) {
        try Licence.parse(good.replacingOccurrences(of: "commercial", with: "enterprise"))
    }
    #expect(throws: Licence.Failure.notAnObject) { try Licence.parse("[1]") }
}

@Test func jsonEscapesLikeSerde() {
    #expect(Licence.quote("a\"b\\c\n\t\u{01}/é") == "\"a\\\"b\\\\c\\n\\t\\u0001/é\"")
}

@Test func uuidsComeOutOfAnyText() {
    let a = UUID(uuidString: "019a1171-8f20-7b3e-a5c4-2e9d7f60b1a8")!
    let text = "uid: \(a.uuidString.lowercased())::sys::1\n{\"ehr_id\": \"00000000-0000-0000-0000-000000000000\"} junk-junk-1234\n"
    #expect(Attest.uuids(in: text) == [a, UUID(uuidString: "00000000-0000-0000-0000-000000000000")!])
}

@Test func stampedIdentifiersPointAtTheirKey() {
    let licence = StampKey.licence(UUID())
    let ids = (0..<30).map { i -> UUID in
        var b = [UInt8](UUID().data)
        let ms = UInt64(1_793_491_200_000 + i)
        for j in 0..<6 { b[j] = UInt8(ms >> (8 * (5 - UInt64(j))) & 0xFF) }
        b[6] = 0x70 | (b[6] & 0x0F)
        return licence.stamp(UUID(data: Data(b))!)!
    }
    let report = Attest.run(
        ids,
        candidates: [
            .init(label: "unlicensed", key: .unlicensed, notAfter: nil, revokedFrom: nil),
            .init(label: "licence", key: licence, notAfter: nil, revokedFrom: nil),
        ])
    #expect(report.best(threshold: 1e-9)?.label == "licence")
    #expect(report.findings.first?.matched == 30)
    #expect(report.sampled == 30)
}
