import CryptoKit
import Foundation

@testable import LicenceCore

/// An in-process issuer for the refusals GnuPG will not produce: a key that
/// may not sign, a key that expired before it signed, signatures without an
/// issuer or a creation time. Real issuance uses GnuPG on a YubiKey.
struct Fixture {
    let key = Curve25519.Signing.PrivateKey()
    let created = Date(timeIntervalSince1970: 1_790_000_000)

    var publicBody: Data {
        var b = Data([4])
        b += be32(UInt32(created.timeIntervalSince1970))
        b += Data([22, UInt8(ed25519OID.count)]) + ed25519OID
        b += mpi(Data([0x40]) + key.publicKey.rawRepresentation)
        return b
    }

    var packet: PublicKeyPacket { try! PublicKeyPacket(body: publicBody) }

    /// A certificate with one user id whose self-signature carries `flags`
    /// and, when given, an expiry `lifetime` seconds after creation.
    func certificate(
        flags: UInt8 = 0x03, lifetime: UInt32? = nil, uid: String = "Fixture <f@example.invalid>",
        selfSigned at: Date? = nil
    ) -> Data {
        var hashed = sub(2, be32(UInt32((at ?? created).timeIntervalSince1970))) + sub(27, Data([flags]))
        if let lifetime { hashed += sub(9, be32(lifetime)) }
        hashed += sub(33, Data([4]) + packet.fingerprint)
        let uidData = Data(uid.utf8)
        var signed = packet.framed
        signed += Data([0xB4]) + be32(UInt32(uidData.count)) + uidData
        let sig = signature(type: 0x13, hashed: hashed, unhashed: sub(16, packet.keyID), over: signed)
        return frame(6, publicBody) + frame(13, uidData) + frame(2, sig)
    }

    /// A text signature over `text` (already `\r\n`-joined).
    func textSignature(_ text: String, at: Date?, issuerFingerprint: Bool = true, issuerKeyID: Bool = true) -> Data {
        var hashed = Data()
        if let at { hashed += sub(2, be32(UInt32(at.timeIntervalSince1970))) }
        if issuerFingerprint { hashed += sub(33, Data([4]) + packet.fingerprint) }
        let unhashed = issuerKeyID ? sub(16, packet.keyID) : Data()
        return frame(2, signature(type: 0x01, hashed: hashed, unhashed: unhashed, over: Data(text.utf8)))
    }

    func signature(type: UInt8, hashed: Data, unhashed: Data, over data: Data) -> Data {
        var head = Data([4, type, 22, 10])
        head += be16(hashed.count) + hashed
        let trailer = head + Data([4, 0xFF]) + be32(UInt32(head.count))
        let digest = Data(SHA512.hash(data: data + trailer))
        let sig = try! key.signature(for: digest)
        return head + be16(unhashed.count) + unhashed + digest.prefix(2) + mpi(sig.prefix(32)) + mpi(sig.suffix(32))
    }

    /// A licence file: `licence` signed with `signatures`, bundling `certificate`.
    static func token(_ licence: Licence, signatures: Data, certificate: Data) -> String {
        let text = licence.canonicalJSON.dropLast()  // the final line break belongs to the frame
        return "-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n\(text)\n"
            + Armor.encode(signatures, kind: "PGP SIGNATURE")
            + Armor.encode(certificate, kind: "PGP PUBLIC KEY BLOCK")
    }

    static let licence = Licence(
        id: UUID(uuidString: "019a1171-8f20-7b3e-a5c4-2e9d7f60b1a8")!, licensee: "Fixture Clinic",
        issued: CivilDate("2026-10-24")!, notBefore: CivilDate("2026-11-01")!,
        notAfter: CivilDate("2027-10-31")!, use: .commercial)

    static var signedText: String { licence.canonicalJSON.dropLast().replacingOccurrences(of: "\n", with: "\r\n") }
}

func be16(_ n: Int) -> Data { Data([UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)]) }
func be32(_ n: UInt32) -> Data { Data([UInt8(n >> 24), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)]) }

func mpi(_ raw: Data) -> Data {
    let trimmed = raw.drop { $0 == 0 }
    guard let first = trimmed.first else { return be16(0) }
    let bits = (trimmed.count - 1) * 8 + (8 - first.leadingZeroBitCount)
    return be16(bits) + Data(trimmed)
}

func sub(_ type: UInt8, _ value: Data) -> Data { Data([UInt8(value.count + 1), type]) + value }

func frame(_ tag: UInt8, _ body: Data) -> Data {
    var out = Data([0xC0 | tag])
    if body.count < 192 {
        out.append(UInt8(body.count))
    } else {
        let n = body.count - 192
        out += Data([UInt8(n >> 8 + 192), UInt8(n & 0xFF)])
    }
    return out + body
}
