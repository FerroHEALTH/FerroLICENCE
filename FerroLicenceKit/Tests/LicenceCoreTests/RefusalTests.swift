import Foundation
import Testing

@testable import LicenceCore

private let day = CivilDate("2026-11-01")!

private func check(_ token: String, anchors: [Data]) throws -> Verified {
    try verify(try Token(token), anchors: anchors.map { try Certificate(packets: $0) }, on: day)
}

@Test func aFixtureLicenceVerifies() throws {
    let f = Fixture()
    let cert = f.certificate()
    let token = Fixture.token(
        Fixture.licence, signatures: f.textSignature(Fixture.signedText, at: f.created.addingTimeInterval(60)), certificate: cert)
    let verified = try check(token, anchors: [cert])
    #expect(verified.licence == Fixture.licence)
    #expect(verified.signer == f.packet.fingerprintHex)
    #expect(verified.signerExpiresAt == nil)
}

@Test func aKeyThatMayNotSignIsRefused() throws {
    let f = Fixture()
    let cert = f.certificate(flags: 0x01)
    let token = Fixture.token(Fixture.licence, signatures: f.textSignature(Fixture.signedText, at: f.created), certificate: cert)
    #expect(throws: VerifyError.notSigningCapable(fingerprint: f.packet.fingerprintHex)) { try check(token, anchors: [cert]) }
}

@Test func signingRightsComeFromTheAnchorNotTheToken() throws {
    let f = Fixture()
    let bundled = f.certificate(flags: 0x03)
    let anchor = f.certificate(flags: 0x01, selfSigned: f.created.addingTimeInterval(10))
    let token = Fixture.token(
        Fixture.licence, signatures: f.textSignature(Fixture.signedText, at: f.created.addingTimeInterval(20)), certificate: bundled)
    #expect(throws: VerifyError.notSigningCapable(fingerprint: f.packet.fingerprintHex)) { try check(token, anchors: [anchor]) }
}

@Test func aSignatureAfterTheKeyExpiredIsRefused() throws {
    let f = Fixture()
    let cert = f.certificate(lifetime: 60)
    let token = Fixture.token(
        Fixture.licence, signatures: f.textSignature(Fixture.signedText, at: f.created.addingTimeInterval(120)), certificate: cert)
    #expect {
        try check(token, anchors: [cert])
    } throws: { error in
        if case .expiredAtSigning = error as? VerifyError { return true }
        return false
    }
    let before = Fixture.token(
        Fixture.licence, signatures: f.textSignature(Fixture.signedText, at: f.created.addingTimeInterval(30)), certificate: cert)
    #expect(try check(before, anchors: [cert]).signerExpiresAt == f.created.addingTimeInterval(60))
}

@Test func aSignatureWithoutIssuerOrTimeIsRefused() throws {
    let f = Fixture()
    let cert = f.certificate()
    let noIssuer = Fixture.token(
        Fixture.licence, signatures: f.textSignature(Fixture.signedText, at: f.created, issuerFingerprint: false, issuerKeyID: false),
        certificate: cert)
    #expect(throws: VerifyError.noIssuer) { try check(noIssuer, anchors: [cert]) }
    let keyIDOnly = Fixture.token(
        Fixture.licence, signatures: f.textSignature(Fixture.signedText, at: f.created, issuerFingerprint: false), certificate: cert)
    #expect(try check(keyIDOnly, anchors: [cert]).licence == Fixture.licence)
    let noTime = Fixture.token(Fixture.licence, signatures: f.textSignature(Fixture.signedText, at: nil), certificate: cert)
    #expect(throws: VerifyError.noSigningTime) { try check(noTime, anchors: [cert]) }
}

@Test func aSignatureByAnotherKeyIsRefused() throws {
    let f = Fixture(), other = Fixture()
    let cert = f.certificate()
    let token = Fixture.token(Fixture.licence, signatures: other.textSignature(Fixture.signedText, at: f.created), certificate: cert)
    #expect(throws: VerifyError.unknownSigner) { try check(token, anchors: [cert]) }
}

@Test func anAnchorWithBrokenBindingsIsRefused() throws {
    let f = Fixture()
    let good = f.certificate()
    var broken = good
    let uid = Data("Fixture".utf8)
    let at = broken.firstRange(of: uid)!
    broken.replaceSubrange(at, with: Data("Fixturf".utf8))
    let token = Fixture.token(Fixture.licence, signatures: f.textSignature(Fixture.signedText, at: f.created), certificate: good)
    #expect(throws: VerifyError.brokenBindings) { try check(token, anchors: [broken]) }
}

@Test func aChangedLicenceIsRefusedAtTheSignature() throws {
    let f = Fixture()
    let cert = f.certificate()
    let token = Fixture.token(Fixture.licence, signatures: f.textSignature(Fixture.signedText, at: f.created), certificate: cert)
        .replacingOccurrences(of: "Fixture Clinic", with: "Fixture Clinik")
    #expect(throws: VerifyError.badSignature) { try check(token, anchors: [cert]) }
}

@Test func everyRefusalMapsToItsCheck() {
    #expect(Check(.noSignature) == .oneSignature)
    #expect(Check(.unknownSigner) == .signedByKey)
    #expect(Check(.expired(notAfter: day)) == .insideWindow)
    #expect(Check.trustedKey < Check.insideWindow)
    #expect(Check.allCases.count == 9)
}
