import Foundation

/// The licence file: a cleartext-signed licence followed by the public
/// certificate that signed it, as one armored text.
public struct Token: Sendable {
    /// Why a text is not a licence file.
    public enum Failure: Error, Equatable, Sendable {
        /// No `BEGIN PGP SIGNED MESSAGE` … `END PGP SIGNATURE` block.
        case missingSignedMessage
        /// No `BEGIN PGP PUBLIC KEY BLOCK` … `END PGP PUBLIC KEY BLOCK` block.
        case missingCertificate
        /// The signed block is malformed.
        case message
        /// The certificate block is malformed.
        case certificate
    }

    static let messageBegin = "-----BEGIN PGP SIGNED MESSAGE-----"
    static let signatureBegin = "-----BEGIN PGP SIGNATURE-----"
    static let signatureEnd = "-----END PGP SIGNATURE-----"
    static let certificateBegin = "-----BEGIN PGP PUBLIC KEY BLOCK-----"
    static let certificateEnd = "-----END PGP PUBLIC KEY BLOCK-----"

    /// The signatures in the signed block.
    public let signatures: [SignaturePacket]
    /// The certificate bundled with the token.
    public let certificate: Certificate
    /// The text the signature covers, lines joined with `\r\n` and stripped
    /// of trailing whitespace, as RFC 9580 §7.2 normalises it.
    public let signedText: String

    /// Read a licence file.
    public init(_ text: String) throws(Failure) {
        guard let signed = Self.block(text, Self.messageBegin, Self.signatureEnd) else { throw .missingSignedMessage }
        guard let certText = Self.block(text, Self.certificateBegin, Self.certificateEnd) else { throw .missingCertificate }
        guard let (body, signatureArmor) = Self.split(signed) else { throw .message }
        do {
            let data = try Armor.decode(signatureArmor, kind: "PGP SIGNATURE")
            signatures = try Packet.all(in: data).filter { $0.tag == 2 }.map { try SignaturePacket(body: $0.body) }
        } catch { throw .message }
        do { certificate = try Certificate(armored: certText) } catch { throw .certificate }
        signedText = body
    }

    /// The first `begin` … `end` span of `text`, both markers included.
    static func block(_ text: String, _ begin: String, _ end: String) -> String? {
        guard let start = text.range(of: begin), let stop = text.range(of: end, range: start.upperBound..<text.endIndex)
        else { return nil }
        return String(text[start.lowerBound..<stop.upperBound])
    }

    /// The normalised signed text and the signature's armor, from a
    /// cleartext-signed block: armor headers, a blank line, the dash-escaped
    /// text, then the signature.
    static func split(_ signed: String) -> (String, String)? {
        var lines = signed.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" })
            .map { $0.hasSuffix("\r") ? String($0.dropLast()) : String($0) }
        guard lines.first == messageBegin else { return nil }
        lines.removeFirst()
        // Armor headers ("Hash: SHA512") run to the first empty line.
        guard let blank = lines.firstIndex(of: ""), lines[..<blank].allSatisfy({ $0.contains(": ") }) else { return nil }
        lines.removeSubrange(...blank)
        guard let sig = lines.firstIndex(of: signatureBegin) else { return nil }
        let text = lines[..<sig].map { line -> String in
            let unescaped = line.hasPrefix("- ") ? String(line.dropFirst(2)) : line
            var trimmed = unescaped
            while let last = trimmed.last, last == " " || last == "\t" { trimmed.removeLast() }
            return trimmed
        }
        return (text.joined(separator: "\r\n"), lines[sig...].joined(separator: "\n"))
    }

    /// Put a cleartext signature and a certificate together as one licence
    /// file, one newline between the blocks.
    public static func assemble(signed: String, certificate: String) -> String {
        func trimmed(_ s: String) -> String {
            var s = s
            while let last = s.last, last.isWhitespace { s.removeLast() }
            return s
        }
        return "\(trimmed(signed))\n\(trimmed(certificate))\n"
    }
}
