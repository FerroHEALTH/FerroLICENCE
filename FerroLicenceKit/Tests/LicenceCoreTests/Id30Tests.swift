import Foundation
import Testing

@testable import LicenceCore

private let day = CivilDate("2026-11-01")!

private func check(_ token: String, anchors: [Data]) throws -> Verified {
    try verify(try Token(token), anchors: anchors.map { try Certificate(packets: $0) }, on: day)
}

private func rfc9980(_ name: String) throws -> String {
    try String(contentsOf: Vectors.dir.appending(path: "rfc9980/\(name)"), encoding: .utf8)
}

/// RFC 9980 Appendix A.3: the sample ML-DSA-65+Ed25519 certificate and its
/// detached signature over "Testing\n", an oracle written by others.
@Test func theRFC9980SampleKeyAndSignatureVerify() throws {
    let cert = try Certificate(armored: try rfc9980("a3-public.asc"))
    #expect(cert.primary.version == 6)
    #expect(cert.primary.algorithm == 30)
    #expect(cert.primary.fingerprint.hexLower == "a3e2e14b6a493ff930fb27321f125e9a6880338be9fb7da3ae065ea65793242f")
    #expect(cert.subkeys.first?.key.fingerprint.hexLower == "7dae8fbce23022607167af72a002e774e0ca379a2d7ae072384e1e8fde3265e4")
    #expect(cert.bindingsVerify())

    let packets = try Packet.all(in: try Armor.decode(try rfc9980("a3-detached.asc"), kind: "PGP SIGNATURE"))
    let signature = try #require(packets.first.map { try SignaturePacket(body: $0.body) })
    #expect(signature.version == 6)
    #expect(signature.issuerFingerprint == cert.primary.fingerprint)
    // A text signature: the line ending is hashed as CR LF (RFC 9580 §5.2.4).
    #expect(signature.type == 0x01)
    #expect(signature.verifies(Data("Testing\r\n".utf8), by: cert.primary))
    #expect(!signature.verifies(Data("Testing\n".utf8), by: cert.primary))
}

@Test func anID30LicenceVerifies() throws {
    let f = PQFixture(seed: 1)
    let cert = f.certificate(uid: "Fixture <f@example.invalid>")
    for hash: UInt8 in [8, 9, 10, 12, 14] {
        let token = Fixture.token(
            Fixture.licence, signatures: f.documentSignature(Fixture.signedText, at: f.created.addingTimeInterval(60), hash: hash),
            certificate: cert, hashHeader: false)
        let verified = try check(token, anchors: [cert])
        #expect(verified.licence == Fixture.licence)
        #expect(verified.signer == f.packet.fingerprintHex)
        #expect(verified.signer.count == 64)
    }
}

@Test func aDigestUnder256BitsIsRefused() throws {
    let f = PQFixture(seed: 1)
    let cert = f.certificate(uid: "Fixture <f@example.invalid>")
    let token = Fixture.token(
        Fixture.licence, signatures: f.documentSignature(Fixture.signedText, at: f.created, hash: 11), certificate: cert,
        hashHeader: false)
    #expect(throws: VerifyError.weakDigest(hashAlgorithm: 11)) { try check(token, anchors: [cert]) }
    #expect(Check(.weakDigest(hashAlgorithm: 11)) == .signatureMatches)
}

@Test(arguments: [(true, false), (false, true)])
func bothHalvesMustVerify(_ breakEd25519: Bool, _ breakMLDSA: Bool) throws {
    let f = PQFixture(seed: 1)
    let cert = f.certificate(uid: "Fixture <f@example.invalid>")
    let token = Fixture.token(
        Fixture.licence,
        signatures: f.documentSignature(Fixture.signedText, at: f.created, breakEd25519: breakEd25519, breakMLDSA: breakMLDSA),
        certificate: cert, hashHeader: false)
    #expect(throws: VerifyError.badSignature) { try check(token, anchors: [cert]) }
}

@Test func aVersion6KeyWithoutADirectKeySignatureIsRefused() throws {
    let f = PQFixture(seed: 1)
    let cert = f.certificate(directKey: false, uid: "Fixture <f@example.invalid>")
    let token = Fixture.token(
        Fixture.licence, signatures: f.documentSignature(Fixture.signedText, at: f.created), certificate: cert, hashHeader: false)
    #expect(throws: VerifyError.brokenBindings) { try check(token, anchors: [cert]) }
}

@Test func aVersion6SignatureNamedOnlyByKeyIDIsRefused() throws {
    let f = PQFixture(seed: 1)
    let cert = f.certificate(uid: "Fixture <f@example.invalid>")
    let token = Fixture.token(
        Fixture.licence, signatures: f.documentSignature(Fixture.signedText, at: f.created, issuerFingerprint: false),
        certificate: cert, hashHeader: false)
    #expect(throws: VerifyError.noIssuer) { try check(token, anchors: [cert]) }
}

@Test func signingRightsAndExpiryComeFromTheDirectKeySignature() throws {
    let f = PQFixture(seed: 1)
    let certifyOnly = f.certificate(flags: 0x01, uid: "Fixture <f@example.invalid>")
    let signed = Fixture.token(
        Fixture.licence, signatures: f.documentSignature(Fixture.signedText, at: f.created), certificate: certifyOnly,
        hashHeader: false)
    #expect(throws: VerifyError.notSigningCapable(fingerprint: f.packet.fingerprintHex)) { try check(signed, anchors: [certifyOnly]) }

    let expiring = f.certificate(lifetime: 60, uid: "Fixture <f@example.invalid>")
    let late = Fixture.token(
        Fixture.licence, signatures: f.documentSignature(Fixture.signedText, at: f.created.addingTimeInterval(120)),
        certificate: expiring, hashHeader: false)
    #expect {
        try check(late, anchors: [expiring])
    } throws: { error in
        if case .expiredAtSigning = error as? VerifyError { return true }
        return false
    }
}

@Test func aVersion4AnchorDoesNotAcceptAVersion6Signature() throws {
    let classic = Fixture()
    let pq = PQFixture(seed: 1)
    let cert = classic.certificate()
    let token = Fixture.token(
        Fixture.licence, signatures: pq.documentSignature(Fixture.signedText, at: pq.created), certificate: cert, hashHeader: false)
    #expect(throws: VerifyError.unknownSigner) { try check(token, anchors: [cert]) }
}

@Test func anIssuerFingerprintOfTheWrongVersionIsMalformed() throws {
    let f = PQFixture(seed: 1)
    let hashed = sub(2, be32(UInt32(f.created.timeIntervalSince1970))) + sub(33, Data([4]) + Data(f.packet.fingerprint.prefix(20)))
    let body = f.signature(type: 0x01, hashed: hashed, over: Data(Fixture.signedText.utf8))
    #expect(throws: PacketFailure.malformed("issuer fingerprint version")) { try SignaturePacket(body: body) }
}

/// The ID 30 vectors under `Vectors/id30`, which FerroEHR's checker must
/// answer the same way (`docs/ferroehr-integration.md` §1).
struct ID30Vectors: Decodable {
    let cases: [Vectors.Case]

    static let dir = Vectors.dir.appending(path: "id30")
    static let all: ID30Vectors = try! JSONDecoder().decode(ID30Vectors.self, from: Data(contentsOf: dir.appending(path: "vectors.json")))
}

@Test(arguments: ID30Vectors.all.cases.map(\.name))
func theSwiftCheckerAnswersTheID30Vectors(_ caseName: String) throws {
    let c = ID30Vectors.all.cases.first { $0.name == caseName }!
    let anchors = try c.anchors.map {
        try Certificate(armored: String(contentsOf: ID30Vectors.dir.appending(path: "anchors/\($0)"), encoding: .utf8))
    }
    let text = try String(contentsOf: ID30Vectors.dir.appending(path: "tokens/\(c.token)"), encoding: .utf8)
    let result: String
    var licence: Licence?
    do {
        let token = try Token(text)
        do {
            licence = try verify(token, anchors: anchors, on: CivilDate(c.day)!).licence
            result = "ok"
        } catch {
            result = name(of: error)
            licence = try? Licence.parse(token.signedText)
        }
    } catch {
        result = tokenName(error)
    }
    #expect(result == c.result, "\(c.name)")
    if let expected = c.licence {
        #expect(licence?.id.uuidString.lowercased() == expected["licence_id"])
        #expect(licence?.licensee == expected["licensee"])
        #expect(licence?.notAfter.description == expected["not_after"])
    } else {
        #expect(licence == nil, "\(c.name)")
    }
}

@Test func theID30VectorsCoverEveryCheck() {
    let refusals = Set(ID30Vectors.all.cases.map(\.result))
    for expected in [
        "ok", "UntrustedPrimary", "BrokenBindings", "ExtraSignatures", "NotTextSignature", "NoIssuer", "UnknownSigner",
        "NotSigningCapable", "ExpiredAtSigning", "WeakDigest", "BadSignature", "Payload", "NotYetValid", "Expired",
    ] {
        #expect(refusals.contains(expected), "\(expected)")
    }
}
