import Foundation
import Testing

@testable import LicenceCore

/// Writes the ID 30 vectors under `Vectors/id30`, the cases FerroEHR's
/// checker answers too. Run once with `FERROLICENCE_WRITE_ID30_VECTORS=1
/// swift test --filter writeTheID30Vectors`; the files are committed.
@Test(.enabled(if: ProcessInfo.processInfo.environment["FERROLICENCE_WRITE_ID30_VECTORS"] == "1"))
func writeTheID30Vectors() throws {
    let out = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Vectors/id30")
    try FileManager.default.createDirectory(at: out.appending(path: "anchors"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: out.appending(path: "tokens"), withIntermediateDirectories: true)

    let a = PQFixture(seed: 1), b = PQFixture(seed: 2), u = PQFixture(seed: 3)
    let c = PQFixture(seed: 4), d = PQFixture(seed: 5), n = PQFixture(seed: 6)
    let certs: [String: Data] = [
        "A": a.certificate(uid: "Vector A <a@example.invalid>"),
        "B": b.certificate(uid: "Vector B <b@example.invalid>"),
        "U": u.certificate(uid: "Vector U <u@example.invalid>"),
        "C": c.certificate(flags: 0x01, uid: "Vector C <c@example.invalid>"),
        "D": d.certificate(lifetime: 60, uid: "Vector D <d@example.invalid>"),
        "N": n.certificate(directKey: false, uid: "Vector N <n@example.invalid>"),
    ]
    for (name, cert) in certs where name != "U" {
        try Armor.encode(cert, kind: "PGP PUBLIC KEY BLOCK").write(
            to: out.appending(path: "anchors/\(name).asc"), atomically: true, encoding: .utf8)
    }

    let first = Licence(
        id: UUID(uuidString: "019a1171-8f20-7b3e-a5c4-2e9d7f60b1a8")!, licensee: "Example Hospital NV",
        issued: CivilDate("2026-10-24")!, notBefore: CivilDate("2026-11-01")!, notAfter: CivilDate("2027-10-31")!, use: .commercial)
    let unicode = Licence(
        id: UUID(uuidString: "019a1171-8f20-7b3e-a5c4-2e9d7f60b1a9")!, licensee: "Ünïcode \"Quoted\" / Slash & Co. — ✓",
        issued: CivilDate("2026-10-24")!, notBefore: CivilDate("2026-11-01")!, notAfter: CivilDate("2027-10-31")!, use: .commercial)
    let firstText = String(first.canonicalJSON.dropLast())
    let unknownField = firstText.replacingOccurrences(of: "\"use\": \"commercial\"", with: "\"use\": \"commercial\",\n  \"seats\": 5")

    /// The cleartext frame RFC 9580 §7 describes, with no Hash header.
    func token(_ text: String, _ signatures: Data, _ cert: Data?) -> String {
        "-----BEGIN PGP SIGNED MESSAGE-----\n\n\(text)\n" + Armor.encode(signatures, kind: "PGP SIGNATURE")
            + (cert.map { Armor.encode($0, kind: "PGP PUBLIC KEY BLOCK") } ?? "")
    }
    func signed(_ text: String) -> String { text.replacingOccurrences(of: "\n", with: "\r\n") }
    let at = a.created.addingTimeInterval(60)

    var tokens: [String: String] = [:]
    tokens["ok_a"] = token(firstText, a.documentSignature(signed(firstText), at: at), certs["A"])
    tokens["ok_b_sha512"] = token(
        String(unicode.canonicalJSON.dropLast()), b.documentSignature(signed(String(unicode.canonicalJSON.dropLast())), at: at, hash: 10),
        certs["B"])
    tokens["untrusted"] = token(firstText, u.documentSignature(signed(firstText), at: at), certs["U"])
    tokens["tampered"] = tokens["ok_a"]!.replacingOccurrences(of: "Example Hospital NV", with: "Example Hospital BV")
    tokens["ed25519_half_broken"] = token(firstText, a.documentSignature(signed(firstText), at: at, breakEd25519: true), certs["A"])
    tokens["mldsa_half_broken"] = token(firstText, a.documentSignature(signed(firstText), at: at, breakMLDSA: true), certs["A"])
    tokens["weak_digest"] = token(firstText, a.documentSignature(signed(firstText), at: at, hash: 11), certs["A"])
    tokens["two_signatures"] = token(
        firstText, a.documentSignature(signed(firstText), at: at) + b.documentSignature(signed(firstText), at: at), certs["A"])
    tokens["binary_signature"] = token(firstText, a.documentSignature(signed(firstText), type: 0x00, at: at), certs["A"])
    tokens["key_id_only"] = token(firstText, a.documentSignature(signed(firstText), at: at, issuerFingerprint: false), certs["A"])
    tokens["unknown_signer"] = token(firstText, u.documentSignature(signed(firstText), at: at), certs["A"])
    tokens["not_signing"] = token(firstText, c.documentSignature(signed(firstText), at: at), certs["C"])
    tokens["expired_at_signing"] = token(
        firstText, d.documentSignature(signed(firstText), at: d.created.addingTimeInterval(120)), certs["D"])
    tokens["no_direct_key"] = token(firstText, n.documentSignature(signed(firstText), at: at), certs["N"])
    tokens["unknown_field"] = token(unknownField, a.documentSignature(signed(unknownField), at: at), certs["A"])
    tokens["no_certificate"] = token(firstText, a.documentSignature(signed(firstText), at: at), nil)
    for (name, text) in tokens {
        try text.write(to: out.appending(path: "tokens/\(name).asc"), atomically: true, encoding: .utf8)
    }

    func licence(_ l: Licence) -> [String: String] {
        [
            "licence_id": l.id.uuidString.lowercased(), "licensee": l.licensee, "issued": l.issued.description,
            "not_before": l.notBefore.description, "not_after": l.notAfter.description, "use": "commercial",
        ]
    }
    func entry(
        _ name: String, token: String? = nil, anchors: [String] = ["A", "B"], day: String = "2026-11-01", _ result: String, _ l: Licence?
    )
        -> [String: Any]
    {
        var e: [String: Any] = [
            "name": "id30_\(name)", "token": "\(token ?? name).asc", "anchors": anchors.map { "\($0).asc" }, "day": day, "result": result,
        ]
        if let l { e["licence"] = licence(l) }
        return e
    }
    let cases: [[String: Any]] = [
        entry("ok_a", "ok", first),
        entry("ok_b_sha512", day: "2027-10-31", "ok", unicode),
        entry("untrusted", "UntrustedPrimary", first),
        entry("no_direct_key", anchors: ["N"], "BrokenBindings", first),
        entry("two_signatures", "ExtraSignatures", first),
        entry("binary_signature", "NotTextSignature", first),
        entry("key_id_only", "NoIssuer", first),
        entry("unknown_signer", "UnknownSigner", first),
        entry("not_signing", anchors: ["A", "B", "C"], "NotSigningCapable", first),
        entry("expired_at_signing", anchors: ["A", "B", "D"], "ExpiredAtSigning", first),
        entry("weak_digest", "WeakDigest", first),
        entry("tampered", "BadSignature", first.with(licensee: "Example Hospital BV")),
        entry("ed25519_half_broken", "BadSignature", first),
        entry("mldsa_half_broken", "BadSignature", first),
        entry("unknown_field", "Payload", nil),
        entry("not_yet_valid", token: "ok_a", day: "2026-10-31", "NotYetValid", first),
        entry("expired", token: "ok_a", day: "2027-11-01", "Expired", first),
        entry("no_certificate", "Token:MissingCertificate", nil),
    ]
    let document: [String: Any] = [
        "generated_by": "FerroLicenceKit writeTheID30Vectors (CryptoKit, RFC 9980 algorithm ID 30), 2026-11-25", "cases": cases,
    ]
    let json = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try (String(decoding: json, as: UTF8.self) + "\n").write(to: out.appending(path: "vectors.json"), atomically: true, encoding: .utf8)
}

extension Licence {
    fileprivate func with(licensee: String) -> Licence {
        Licence(id: id, licensee: licensee, issued: issued, notBefore: notBefore, notAfter: notAfter, use: use)
    }
}
