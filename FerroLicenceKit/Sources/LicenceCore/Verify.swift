public import Foundation

/// Why a licence file was refused, named after the check that refused it, in
/// the order FerroEHR runs them (`docs/design.md` §5).
public enum VerifyError: Error, Equatable, Sendable {
    /// The bundled key is not one of the trusted keys, compared on the full key packet.
    case untrustedPrimary(fingerprint: String)
    /// The trusted key's own signatures do not verify under it.
    case brokenBindings
    /// The signed block carries no signature.
    case noSignature
    /// More than one signature; exactly one is allowed.
    case extraSignatures(Int)
    /// Not a text signature, the only kind a cleartext licence is made with.
    case notTextSignature
    /// The signature names no issuer.
    case noIssuer
    /// Made by another key than the primary, a subkey included.
    case unknownSigner
    /// The key's newest self-signature does not allow signing.
    case notSigningCapable(fingerprint: String)
    /// The signature carries no creation time.
    case noSigningTime
    /// Signed after the key had expired.
    case expiredAtSigning(expiredAt: Date, signedAt: Date)
    /// The signature does not match the text.
    case badSignature
    /// The text is not a licence document.
    case payload(Licence.Failure)
    /// The window has not opened yet.
    case notYetValid(notBefore: CivilDate)
    /// The window has closed.
    case expired(notAfter: CivilDate)
}

/// A licence that passed every check.
public struct Verified: Equatable, Sendable {
    public let licence: Licence
    /// The trusted key that signed, upper-case hex.
    public let signer: String
    public let signedAt: Date
    /// When the signer expires, if its self-signature sets an expiry.
    public let signerExpiresAt: Date?
}

/// Check `token` against the trusted `anchors` as of `day`.
///
/// Trust is decided on the full primary key packet: the bundled key must
/// equal an anchor's byte for byte. From then on only the anchor counts:
/// whether the key may sign and when it expires are read from the anchor's
/// own self-signature, never from the copy the token carries.
public func verify(_ token: Token, anchors: [Certificate], on day: CivilDate) throws(VerifyError) -> Verified {
    let bundled = token.certificate.primary
    guard let anchor = anchors.first(where: { $0.primary.body == bundled.body }) else {
        throw .untrustedPrimary(fingerprint: bundled.fingerprintHex)
    }
    let primary = anchor.primary
    guard anchor.bindingsVerify() else { throw .brokenBindings }

    guard let signature = token.signatures.first else { throw .noSignature }
    guard token.signatures.count == 1 else { throw .extraSignatures(token.signatures.count) }
    guard signature.type == 0x01 else { throw .notTextSignature }
    if let issuer = signature.issuerFingerprint {
        guard issuer == primary.fingerprint else { throw .unknownSigner }
    } else {
        guard let keyID = signature.issuerKeyID else { throw .noIssuer }
        guard keyID == primary.keyID else { throw .unknownSigner }
    }

    guard let selfSignature = anchor.newestSelfSignature,
        let flags = selfSignature.hashed.keyFlags?.first, flags & 0x02 != 0
    else { throw .notSigningCapable(fingerprint: primary.fingerprintHex) }

    guard let signedAt = signature.created else { throw .noSigningTime }
    var expiresAt: Date?
    if let lifetime = selfSignature.hashed.keyExpiration, lifetime > 0 {
        let expiry = primary.created.addingTimeInterval(TimeInterval(lifetime))
        expiresAt = expiry
        if signedAt >= expiry { throw .expiredAtSigning(expiredAt: expiry, signedAt: signedAt) }
    }

    guard signature.verifies(Data(token.signedText.utf8), by: primary) else { throw .badSignature }

    let licence: Licence
    do { licence = try Licence.parse(token.signedText) } catch { throw .payload(error) }
    switch licence.window(on: day) {
    case .notYetValid: throw .notYetValid(notBefore: licence.notBefore)
    case .expired: throw .expired(notAfter: licence.notAfter)
    case .active: return Verified(licence: licence, signer: primary.fingerprintHex, signedAt: signedAt, signerExpiresAt: expiresAt)
    }
}

/// The nine checks, in order, as people read them.
public enum Check: Int, CaseIterable, Comparable, Sendable {
    case trustedKey, keyIntact, oneSignature, signedByKey, maySign, beforeExpiry, signatureMatches, validDocument, insideWindow

    public var title: LocalizedStringResource {
        switch self {
        case .trustedKey: LocalizedStringResource("Signed by a key we trust", bundle: #bundle)
        case .keyIntact: LocalizedStringResource("Key is intact", bundle: #bundle)
        case .oneSignature: LocalizedStringResource("Exactly one signature, of the right kind", bundle: #bundle)
        case .signedByKey: LocalizedStringResource("Signed by the key itself", bundle: #bundle)
        case .maySign: LocalizedStringResource("Key is allowed to sign", bundle: #bundle)
        case .beforeExpiry: LocalizedStringResource("Signed before the key expired", bundle: #bundle)
        case .signatureMatches: LocalizedStringResource("Signature matches the text", bundle: #bundle)
        case .validDocument: LocalizedStringResource("Text is a valid licence", bundle: #bundle)
        case .insideWindow: LocalizedStringResource("The day falls inside the valid dates", bundle: #bundle)
        }
    }

    /// The check a refusal comes from.
    public init(_ error: VerifyError) {
        switch error {
        case .untrustedPrimary: self = .trustedKey
        case .brokenBindings: self = .keyIntact
        case .noSignature, .extraSignatures, .notTextSignature: self = .oneSignature
        case .noIssuer, .unknownSigner: self = .signedByKey
        case .notSigningCapable: self = .maySign
        case .noSigningTime, .expiredAtSigning: self = .beforeExpiry
        case .badSignature: self = .signatureMatches
        case .payload: self = .validDocument
        case .notYetValid, .expired: self = .insideWindow
        }
    }

    public static func < (a: Check, b: Check) -> Bool { a.rawValue < b.rawValue }
}
