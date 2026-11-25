import CommonCrypto
import CryptoKit
import Foundation

@testable import LicenceCore

/// An in-process issuer of version 6 ML-DSA-65+Ed25519 keys and signatures
/// (RFC 9980 algorithm ID 30), for the ID 30 vectors and the refusals a
/// real signer will not produce. Real issuance signs on the master key.
struct PQFixture {
    let ed: Curve25519.Signing.PrivateKey
    let ml: MLDSA65.PrivateKey
    let created: Date

    /// A key from fixed seeds, so the vector anchors can be written again
    /// with the same key material.
    init(seed: UInt8, created: Date = Date(timeIntervalSince1970: 1_790_000_000)) {
        ed = try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: seed, count: 32))
        ml = try! MLDSA65.PrivateKey(seedRepresentation: Data(repeating: seed &+ 0x80, count: 32), publicKey: nil)
        self.created = created
    }

    var publicBody: Data {
        let material = ed.publicKey.rawRepresentation + ml.publicKey.rawRepresentation
        return Data([6]) + be32(UInt32(created.timeIntervalSince1970)) + Data([30]) + be32(UInt32(material.count)) + material
    }

    var packet: PublicKeyPacket { try! PublicKeyPacket(body: publicBody) }

    /// The issuer fingerprint subpacket of a version 6 key.
    var issuer: Data { sub(33, Data([6]) + packet.fingerprint) }

    /// A version 6 signature body over `data`. `breakEd25519` and `breakMLDSA`
    /// flip one byte of that half after signing.
    func signature(
        type: UInt8, hash: UInt8 = 12, hashed: Data, unhashed: Data = Data(), over data: Data,
        breakEd25519: Bool = false, breakMLDSA: Bool = false
    ) -> Data {
        let head = Data([6, type, 30, hash]) + be32(UInt32(hashed.count)) + hashed
        let salt = Data((0..<HashAlgorithm.saltSize(hash)!).map { _ in UInt8.random(in: 0...255) })
        let trailer = head + Data([6, 0xFF]) + be32(UInt32(head.count))
        let digest = Self.digest(hash, salt + data + trailer)
        var edSignature = try! ed.signature(for: digest)
        var mlSignature = try! ml.signature(for: digest)
        if breakEd25519 { edSignature[edSignature.startIndex] ^= 0x01 }
        if breakMLDSA { mlSignature[mlSignature.startIndex] ^= 0x01 }
        return head + be32(UInt32(unhashed.count)) + unhashed + digest.prefix(2) + Data([UInt8(salt.count)]) + salt + edSignature
            + mlSignature
    }

    /// The digests the fixture signs over, SHA2-224 included for the refusal case.
    static func digest(_ hash: UInt8, _ data: Data) -> Data {
        guard hash == 11 else { return HashAlgorithm.digest(hash, data)! }
        var out = [UInt8](repeating: 0, count: Int(CC_SHA224_DIGEST_LENGTH))
        let bytes = [UInt8](data)
        _ = CC_SHA224(bytes, CC_LONG(bytes.count), &out)
        return Data(out)
    }

    /// A certificate: the key, a direct key signature carrying `flags` and,
    /// when given, an expiry `lifetime` seconds after creation, and one user
    /// id with its certification.
    func certificate(flags: UInt8 = 0x03, lifetime: UInt32? = nil, directKey: Bool = true, uid: String) -> Data {
        var hashed = sub(2, be32(UInt32(created.timeIntervalSince1970))) + sub(27, Data([flags]))
        if let lifetime { hashed += sub(9, be32(lifetime)) }
        hashed += issuer
        let direct = signature(type: 0x1F, hashed: hashed, over: packet.framed)
        let uidData = Data(uid.utf8)
        let certified = packet.framed + Data([0xB4]) + be32(UInt32(uidData.count)) + uidData
        let certification = signature(
            type: 0x13, hashed: sub(2, be32(UInt32(created.timeIntervalSince1970))) + issuer, over: certified)
        return frame(6, publicBody) + (directKey ? frame(2, direct) : Data()) + frame(13, uidData) + frame(2, certification)
    }

    /// A signature packet of `type` (0x01 text) over `text`, already `\r\n`-joined.
    func documentSignature(
        _ text: String, type: UInt8 = 0x01, at: Date, hash: UInt8 = 12, issuerFingerprint: Bool = true,
        breakEd25519: Bool = false, breakMLDSA: Bool = false
    ) -> Data {
        var hashed = sub(2, be32(UInt32(at.timeIntervalSince1970)))
        if issuerFingerprint { hashed += issuer }
        let unhashed = issuerFingerprint ? Data() : sub(16, packet.keyID)
        return frame(
            2,
            signature(
                type: type, hash: hash, hashed: hashed, unhashed: unhashed, over: Data(text.utf8), breakEd25519: breakEd25519,
                breakMLDSA: breakMLDSA))
    }
}
