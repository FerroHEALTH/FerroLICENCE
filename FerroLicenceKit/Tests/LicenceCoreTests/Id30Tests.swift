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

/// `Vectors/rfc9980/vectors.json`: what RFC 9980 Appendix A.3 says about its
/// sample certificate and its detached signature.
struct RFC9980Sample: Decodable {
    let certificate: String
    let primary_fingerprint: String
    let subkey_fingerprint: String
    let signature: String
    let signature_version: UInt8
    let signature_type: UInt8
    let hash_algorithm: UInt8
    let message: String
    let hashed_text: String
}

/// RFC 9980 Appendix A.3: the sample ML-DSA-65+Ed25519 certificate and its
/// detached text signature (type 0x01) over "Testing\n", an oracle written
/// by others. A text signature hashes the line ending as CR LF (RFC 9580 §5.2.4).
@Test func theRFC9980SampleKeyAndSignatureVerify() throws {
    let sample = try JSONDecoder().decode(RFC9980Sample.self, from: Data(contentsOf: Vectors.dir.appending(path: "rfc9980/vectors.json")))
    let cert = try Certificate(armored: try rfc9980(sample.certificate))
    #expect(cert.primary.version == 6)
    #expect(cert.primary.algorithm == 30)
    #expect(cert.primary.fingerprint.hexLower == sample.primary_fingerprint)
    #expect(cert.subkeys.first?.key.fingerprint.hexLower == sample.subkey_fingerprint)
    #expect(cert.bindingsVerify())

    let packets = try Packet.all(in: try Armor.decode(try rfc9980(sample.signature), kind: "PGP SIGNATURE"))
    let signature = try #require(packets.first.map { try SignaturePacket(body: $0.body) })
    #expect(signature.version == sample.signature_version)
    #expect(signature.type == sample.signature_type)
    #expect(signature.hashAlgorithm == sample.hash_algorithm)
    #expect(signature.issuerFingerprint == cert.primary.fingerprint)
    #expect(sample.message.replacingOccurrences(of: "\n", with: "\r\n") == sample.hashed_text)
    #expect(signature.verifies(Data(sample.hashed_text.utf8), by: cert.primary))
    #expect(!signature.verifies(Data(sample.message.utf8), by: cert.primary))
}

@Test func anID30LicenceVerifies() throws {
    let f = try PQFixture(seed: 1)
    let cert = try f.certificate(uid: "Fixture <f@example.invalid>")
    for hash: UInt8 in [8, 9, 10, 12, 14] {
        let token = Fixture.token(
            Fixture.licence, signatures: try f.documentSignature(Fixture.signedText, at: f.created.addingTimeInterval(60), hash: hash),
            certificate: cert, hashHeader: false)
        let verified = try check(token, anchors: [cert])
        #expect(verified.licence == Fixture.licence)
        #expect(try verified.signer == f.packet.fingerprintHex)
        #expect(verified.signer.count == 64)
    }
}

@Test func aDigestUnder256BitsIsRefused() throws {
    let f = try PQFixture(seed: 1)
    let cert = try f.certificate(uid: "Fixture <f@example.invalid>")
    let token = Fixture.token(
        Fixture.licence, signatures: try f.documentSignature(Fixture.signedText, at: f.created, hash: 11), certificate: cert,
        hashHeader: false)
    #expect(throws: VerifyError.weakDigest(hashAlgorithm: 11)) { try check(token, anchors: [cert]) }
    #expect(Check(.weakDigest(hashAlgorithm: 11)) == .signatureMatches)
}

@Test(arguments: [(true, false), (false, true)])
func bothHalvesMustVerify(_ breakEd25519: Bool, _ breakMLDSA: Bool) throws {
    let f = try PQFixture(seed: 1)
    let cert = try f.certificate(uid: "Fixture <f@example.invalid>")
    let token = Fixture.token(
        Fixture.licence,
        signatures: try f.documentSignature(Fixture.signedText, at: f.created, breakEd25519: breakEd25519, breakMLDSA: breakMLDSA),
        certificate: cert, hashHeader: false)
    #expect(throws: VerifyError.badSignature) { try check(token, anchors: [cert]) }
}

@Test func aVersion6KeyWithoutADirectKeySignatureIsRefused() throws {
    let f = try PQFixture(seed: 1)
    let cert = try f.certificate(directKey: false, uid: "Fixture <f@example.invalid>")
    let token = Fixture.token(
        Fixture.licence, signatures: try f.documentSignature(Fixture.signedText, at: f.created), certificate: cert, hashHeader: false)
    #expect(throws: VerifyError.brokenBindings) { try check(token, anchors: [cert]) }
}

@Test func aVersion6SignatureNamedOnlyByKeyIDIsRefused() throws {
    let f = try PQFixture(seed: 1)
    let cert = try f.certificate(uid: "Fixture <f@example.invalid>")
    let token = Fixture.token(
        Fixture.licence, signatures: try f.documentSignature(Fixture.signedText, at: f.created, issuerFingerprint: false),
        certificate: cert, hashHeader: false)
    #expect(throws: VerifyError.noIssuer) { try check(token, anchors: [cert]) }
}

@Test func signingRightsAndExpiryComeFromTheDirectKeySignature() throws {
    let f = try PQFixture(seed: 1)
    let certifyOnly = try f.certificate(flags: 0x01, uid: "Fixture <f@example.invalid>")
    let signed = Fixture.token(
        Fixture.licence, signatures: try f.documentSignature(Fixture.signedText, at: f.created), certificate: certifyOnly,
        hashHeader: false)
    let fingerprint = try f.packet.fingerprintHex
    #expect(throws: VerifyError.notSigningCapable(fingerprint: fingerprint)) { try check(signed, anchors: [certifyOnly]) }

    let expiring = try f.certificate(lifetime: 60, uid: "Fixture <f@example.invalid>")
    let late = Fixture.token(
        Fixture.licence, signatures: try f.documentSignature(Fixture.signedText, at: f.created.addingTimeInterval(120)),
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
    let pq = try PQFixture(seed: 1)
    let cert = try classic.certificate()
    let token = Fixture.token(
        Fixture.licence, signatures: try pq.documentSignature(Fixture.signedText, at: pq.created), certificate: cert, hashHeader: false)
    #expect(throws: VerifyError.unknownSigner) { try check(token, anchors: [cert]) }
}

@Test func anIssuerFingerprintOfTheWrongVersionIsMalformed() throws {
    let f = try PQFixture(seed: 1)
    let v6 = try f.packet.fingerprint
    let hashed = sub(2, be32(UInt32(f.created.timeIntervalSince1970))) + sub(33, Data([4]) + Data(v6.prefix(20)))
    let body = try f.signature(type: 0x01, hashed: hashed, over: Data(Fixture.signedText.utf8))
    #expect(throws: PacketFailure.malformed("issuer fingerprint version")) { try SignaturePacket(body: body) }
}

/// The ID 30 vectors under `Vectors/id30`, which FerroEHR's checker must
/// answer the same way (`docs/ferroehr-integration.md` §1).
struct ID30Vectors: Decodable {
    let cases: [Vectors.Case]

    static let dir = Vectors.dir.appending(path: "id30")
    static func load() throws -> ID30Vectors {
        try JSONDecoder().decode(ID30Vectors.self, from: Data(contentsOf: dir.appending(path: "vectors.json")))
    }
}

@Test(arguments: (try? ID30Vectors.load().cases) ?? [])
func theSwiftCheckerAnswersTheID30Vectors(_ c: Vectors.Case) throws {
    let anchors = try c.anchors.map {
        try Certificate(armored: String(contentsOf: ID30Vectors.dir.appending(path: "anchors/\($0)"), encoding: .utf8))
    }
    try answer(c, token: try String(contentsOf: ID30Vectors.dir.appending(path: "tokens/\(c.token)"), encoding: .utf8), anchors: anchors)
}

@Test func theID30VectorsCoverEveryCheck() throws {
    let refusals = Set(try ID30Vectors.load().cases.map(\.result))
    for expected in [
        "ok", "UntrustedPrimary", "BrokenBindings", "ExtraSignatures", "NotTextSignature", "NoIssuer", "UnknownSigner",
        "NotSigningCapable", "ExpiredAtSigning", "WeakDigest", "BadSignature", "Payload", "NotYetValid", "Expired",
    ] {
        #expect(refusals.contains(expected), "\(expected)")
    }
}

/// What the ID 30 signer does: a detached text signature over the licence
/// text, framed by the kit as a cleartext-signed licence file.
@Test func aDetachedTextSignatureFramedAsCleartextVerifies() throws {
    let f = try PQFixture(seed: 1)
    let cert = try f.certificate(uid: "Fixture <f@example.invalid>")
    let signature = Armor.encode(try f.documentSignature(Fixture.signedText, at: f.created), kind: "PGP SIGNATURE")
    let file = Token.cleartext(
        String(Fixture.licence.canonicalJSON.dropLast()), signature: signature,
        certificate: Armor.encode(cert, kind: "PGP PUBLIC KEY BLOCK"))
    #expect(file.hasPrefix("-----BEGIN PGP SIGNED MESSAGE-----\n\n{\n"))
    #expect(!file.contains("Hash:"))
    #expect(try check(file, anchors: [cert]).licence == Fixture.licence)
}

@Test func theCleartextFrameDashEscapes() throws {
    let file = Token.cleartext("- a\n-b\nc", signature: "-----BEGIN PGP SIGNATURE-----\n", certificate: "")
    #expect(file.contains("\n\n- - a\n- -b\nc\n-----BEGIN PGP SIGNATURE-----"))
    let (text, _) = try #require(Token.split(file))
    #expect(text == "- a\r\n-b\r\nc")
}
