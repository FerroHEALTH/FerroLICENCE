import CryptoKit
public import Foundation

/// Why OpenPGP packets could not be read.
public enum PacketFailure: Error, Equatable, Sendable {
    /// The data ends inside a packet or a field.
    case truncated
    /// A packet header or field this reader does not accept.
    case malformed(String)
}

/// A cursor over bytes that throws instead of reading past the end.
struct Reader {
    let data: Data
    var at: Int

    init(_ data: Data) {
        self.data = data
        at = data.startIndex
    }

    var atEnd: Bool { at >= data.endIndex }

    mutating func byte() throws(PacketFailure) -> UInt8 {
        guard at < data.endIndex else { throw .truncated }
        defer { at += 1 }
        return data[at]
    }

    mutating func bytes(_ count: Int) throws(PacketFailure) -> Data {
        guard count >= 0, data.endIndex - at >= count else { throw .truncated }
        defer { at += count }
        return data.subdata(in: at..<(at + count))
    }

    mutating func uint16() throws(PacketFailure) -> Int {
        let b = try bytes(2)
        return Int(b[b.startIndex]) << 8 | Int(b[b.startIndex + 1])
    }

    mutating func uint32() throws(PacketFailure) -> UInt32 {
        let b = try bytes(4)
        return b.reduce(0) { $0 << 8 | UInt32($1) }
    }

    /// A multiprecision integer (RFC 9580 §3.2): a bit count, then the bytes.
    mutating func mpi() throws(PacketFailure) -> Data {
        let bits = try uint16()
        return try bytes((bits + 7) / 8)
    }
}

/// One packet: its tag and its body.
struct Packet: Equatable {
    let tag: UInt8
    let body: Data

    /// Every packet in `data`, in order.
    static func all(in data: Data) throws(PacketFailure) -> [Packet] {
        var reader = Reader(data)
        var out: [Packet] = []
        while !reader.atEnd {
            let header = try reader.byte()
            guard header & 0x80 != 0 else { throw .malformed("packet header") }
            let tag: UInt8
            let length: Int
            if header & 0x40 != 0 {
                tag = header & 0x3F
                let first = Int(try reader.byte())
                switch first {
                case 0..<192: length = first
                case 192..<224: length = (first - 192) << 8 + Int(try reader.byte()) + 192
                case 255: length = Int(try reader.uint32())
                default: throw .malformed("partial body length")
                }
            } else {
                tag = header >> 2 & 0x0F
                switch header & 0x03 {
                case 0: length = Int(try reader.byte())
                case 1: length = try reader.uint16()
                case 2: length = Int(try reader.uint32())
                default: throw .malformed("indeterminate length")
                }
            }
            out.append(Packet(tag: tag, body: try reader.bytes(length)))
        }
        return out
    }
}

/// The OID of Ed25519 in legacy EdDSA keys (RFC 9580 §9.2).
let ed25519OID = Data([0x2B, 0x06, 0x01, 0x04, 0x01, 0xDA, 0x47, 0x0F, 0x01])

/// The public-key algorithms the checks verify.
enum KeyAlgorithm {
    /// EdDSALegacy on Ed25519 in a version 4 key (RFC 9580 §5.5.5.5).
    static let ed25519Legacy: UInt8 = 22
    /// ML-DSA-65+Ed25519 in a version 6 key (RFC 9980 §2.1).
    static let mldsa65Ed25519: UInt8 = 30
}

/// RFC 9980 Tables 6 and 7: the fixed sizes of the ML-DSA-65+Ed25519 artifacts.
enum MLDSA65Ed25519 {
    static let ed25519PublicKey = 32
    static let mldsaPublicKey = 1952
    static let ed25519Signature = 64
    static let mldsaSignature = 3309
}

/// The key material the checks can verify with.
enum KeyMaterial: Equatable, Sendable {
    /// An Ed25519 point in a version 4 EdDSALegacy key.
    case ed25519Legacy(Data)
    /// The two halves of an ML-DSA-65+Ed25519 key, Ed25519 first (RFC 9980 §5.3.2.1).
    case mldsa65Ed25519(ed25519: Data, mldsa: Data)
    /// Any other algorithm; it cannot sign anything the checks accept.
    case other
}

/// A version 4 or version 6 public key or subkey packet.
public struct PublicKeyPacket: Equatable, Sendable {
    /// The packet body, the bytes trust is decided on.
    public let body: Data
    /// 4 or 6 (RFC 9580 §5.5.2).
    public let version: UInt8
    /// When the key was made.
    public let created: Date
    /// The public-key algorithm (22 is EdDSALegacy, 30 ML-DSA-65+Ed25519, 18 ECDH, 1 RSA).
    public let algorithm: UInt8
    let material: KeyMaterial

    init(body: Data) throws(PacketFailure) {
        var r = Reader(body)
        version = try r.byte()
        self.body = body
        created = Date(timeIntervalSince1970: TimeInterval(try r.uint32()))
        algorithm = try r.byte()
        switch version {
        case 4:
            if algorithm == KeyAlgorithm.ed25519Legacy {
                let oid = try r.bytes(Int(try r.byte()))
                let point = try r.mpi()
                material = oid == ed25519OID && point.count == 33 && point.first == 0x40 ? .ed25519Legacy(point.dropFirst()) : .other
            } else {
                material = .other
            }
        case 6:
            let count = Int(try r.uint32())
            let key = try r.bytes(count)
            guard r.atEnd else { throw .malformed("key material length") }
            if algorithm == KeyAlgorithm.mldsa65Ed25519 {
                guard count == MLDSA65Ed25519.ed25519PublicKey + MLDSA65Ed25519.mldsaPublicKey else {
                    throw .malformed("ML-DSA-65+Ed25519 key length")
                }
                material = .mldsa65Ed25519(
                    ed25519: key.prefix(MLDSA65Ed25519.ed25519PublicKey), mldsa: key.suffix(MLDSA65Ed25519.mldsaPublicKey))
            } else {
                material = .other
            }
        default:
            throw .malformed("only version 4 and 6 keys")
        }
    }

    /// The fingerprint: SHA-1 over the framed body for version 4 (RFC 9580
    /// §5.5.4.2), SHA-256 for version 6 (§5.5.4.3).
    public var fingerprint: Data {
        version == 6 ? Data(SHA256.hash(data: framed)) : Data(Insecure.SHA1.hash(data: framed))
    }

    /// The fingerprint as GnuPG prints it, upper-case hex.
    public var fingerprintHex: String { fingerprint.hexUpper }

    /// The 64-bit key id: the last eight bytes of a version 4 fingerprint,
    /// the first eight of a version 6 one.
    public var keyID: Data { version == 6 ? fingerprint.prefix(8) : fingerprint.suffix(8) }

    /// Whether the key's algorithm can make a signature the checks verify.
    var canSign: Bool { material != .other }

    /// How a key enters a hash: `0x99` and a two-octet length for version 4,
    /// `0x9B` and a four-octet length for version 6 (RFC 9580 §5.2.4).
    var framed: Data {
        var out = version == 6 ? Data([0x9B]) + be32(body.count) : Data([0x99, UInt8(body.count >> 8 & 0xFF), UInt8(body.count & 0xFF)])
        out.append(body)
        return out
    }
}

/// Four big-endian octets.
func be32(_ n: Int) -> Data {
    let v = UInt32(truncatingIfNeeded: n)
    return Data([UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)])
}

/// A signature subpacket area, read into the fields the checks use.
struct Subpackets: Equatable {
    var created: Date?
    var keyExpiration: UInt32?
    var keyFlags: Data?
    var issuerKeyID: Data?
    /// The key version octet and the fingerprint (RFC 9580 §5.2.3.35).
    var issuerFingerprint: (version: UInt8, fingerprint: Data)?
    var embedded: Data?

    static func == (a: Subpackets, b: Subpackets) -> Bool {
        a.created == b.created && a.keyExpiration == b.keyExpiration && a.keyFlags == b.keyFlags
            && a.issuerKeyID == b.issuerKeyID && a.issuerFingerprint?.version == b.issuerFingerprint?.version
            && a.issuerFingerprint?.fingerprint == b.issuerFingerprint?.fingerprint && a.embedded == b.embedded
    }

    init(_ data: Data) throws(PacketFailure) {
        var r = Reader(data)
        while !r.atEnd {
            let first = Int(try r.byte())
            let length: Int
            switch first {
            case 0..<192: length = first
            case 192..<255: length = (first - 192) << 8 + Int(try r.byte()) + 192
            default: length = Int(try r.uint32())
            }
            guard length >= 1 else { throw .malformed("empty subpacket") }
            let body = try r.bytes(length)
            let type = body[body.startIndex] & 0x7F
            let value = body.dropFirst()
            switch type {
            case 2 where value.count == 4:
                created = Date(timeIntervalSince1970: TimeInterval(value.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }))
            case 9 where value.count == 4:
                keyExpiration = value.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            case 27: keyFlags = Data(value)
            case 16 where value.count == 8: issuerKeyID = Data(value)
            case 33 where value.count == 21 && value.first == 4, 33 where value.count == 33 && value.first == 6:
                issuerFingerprint = (value[value.startIndex], Data(value.dropFirst()))
            case 32: embedded = Data(value)
            default: break
            }
        }
    }
}

/// The hash algorithms the checks compute (RFC 9580 Table 23).
enum HashAlgorithm {
    /// The digest size in bits, for the algorithms CryptoKit computes and SHA2-224.
    static func bits(_ id: UInt8) -> Int? {
        switch id {
        case 8, 12: 256
        case 9: 384
        case 10, 14: 512
        case 11: 224
        default: nil
        }
    }

    /// The version 6 salt size (RFC 9580 Table 23).
    static func saltSize(_ id: UInt8) -> Int? {
        switch id {
        case 8, 11, 12: 16
        case 9: 24
        case 10, 14: 32
        default: nil
        }
    }

    /// The digest of a signature's data. SHA-1 is absent: RFC 9580 §9.5
    /// forbids validating a recent signature that depends on it.
    static func digest(_ id: UInt8, _ data: Data) -> Data? {
        switch id {
        case 8: Data(SHA256.hash(data: data))
        case 9: Data(SHA384.hash(data: data))
        case 10: Data(SHA512.hash(data: data))
        case 12: Data(SHA3_256.hash(data: data))
        case 14: Data(SHA3_512.hash(data: data))
        default: nil
        }
    }
}

/// The algorithm-specific fields of a signature.
enum SignatureMaterial: Equatable, Sendable {
    /// The MPIs of a version 4 signature.
    case mpis([Data])
    /// The two fixed-length halves of an ML-DSA-65+Ed25519 signature,
    /// Ed25519 first (RFC 9980 §5.3.1).
    case mldsa65Ed25519(ed25519: Data, mldsa: Data)
    /// A version 6 signature of another algorithm, kept whole.
    case other(Data)
}

/// A version 4 or version 6 signature packet.
public struct SignaturePacket: Equatable, Sendable {
    /// 4 or 6 (RFC 9580 §5.2.3).
    public let version: UInt8
    /// The signature type: 0x00 binary, 0x01 text, 0x10 to 0x13 certifications,
    /// 0x18 subkey binding, 0x19 primary key binding, 0x1F direct key.
    public let type: UInt8
    /// The public-key algorithm.
    public let algorithm: UInt8
    /// The hash algorithm (8 SHA2-256, 9 SHA2-384, 10 SHA2-512, 12 SHA3-256, 14 SHA3-512).
    public let hashAlgorithm: UInt8
    /// Version through the hashed subpackets: what the hash covers after the data.
    let hashedPart: Data
    let hashed: Subpackets
    let unhashed: Subpackets
    let left16: Data
    /// The version 6 salt, hashed before the data; empty for version 4.
    let salt: Data
    let material: SignatureMaterial

    init(body: Data) throws(PacketFailure) {
        var r = Reader(body)
        version = try r.byte()
        guard version == 4 || version == 6 else { throw .malformed("only version 4 and 6 signatures") }
        type = try r.byte()
        algorithm = try r.byte()
        hashAlgorithm = try r.byte()
        let wide = version == 6
        let hashedLength = wide ? Int(try r.uint32()) : try r.uint16()
        let hashedData = try r.bytes(hashedLength)
        hashedPart = body.subdata(in: body.startIndex..<(body.startIndex + (wide ? 8 : 6) + hashedLength))
        hashed = try Subpackets(hashedData)
        unhashed = try Subpackets(try r.bytes(wide ? Int(try r.uint32()) : try r.uint16()))
        left16 = try r.bytes(2)
        for issuer in [hashed.issuerFingerprint, unhashed.issuerFingerprint].compactMap(\.self) where issuer.version != version {
            // RFC 9580 §5.2.3.35: a version octet that differs from the signature's is malformed.
            throw .malformed("issuer fingerprint version")
        }
        if wide {
            guard let size = HashAlgorithm.saltSize(hashAlgorithm), Int(try r.byte()) == size else {
                throw .malformed("salt size")
            }
            salt = try r.bytes(size)
            if algorithm == KeyAlgorithm.mldsa65Ed25519 {
                let ed = try r.bytes(MLDSA65Ed25519.ed25519Signature)
                let ml = try r.bytes(MLDSA65Ed25519.mldsaSignature)
                guard r.atEnd else { throw .malformed("ML-DSA-65+Ed25519 signature length") }
                material = .mldsa65Ed25519(ed25519: ed, mldsa: ml)
            } else {
                material = .other(try r.bytes(body.endIndex - r.at))
            }
        } else {
            salt = Data()
            var values: [Data] = []
            while !r.atEnd { values.append(try r.mpi()) }
            material = .mpis(values)
        }
    }

    /// When it was made, from the hashed area.
    public var created: Date? { hashed.created }

    /// The issuer fingerprint, hashed area first.
    var issuerFingerprint: Data? { (hashed.issuerFingerprint ?? unhashed.issuerFingerprint)?.fingerprint }

    /// The 64-bit issuer key id, hashed area first.
    var issuerKeyID: Data? { hashed.issuerKeyID ?? unhashed.issuerKeyID }

    /// Whether the digest is too short for the key: RFC 9980 §5.3.1 refuses
    /// an ML-DSA-65+Ed25519 signature over a digest under 256 bits.
    func digestTooShort(for key: PublicKeyPacket) -> Bool {
        guard key.algorithm == KeyAlgorithm.mldsa65Ed25519 else { return false }
        return (HashAlgorithm.bits(hashAlgorithm) ?? 0) < 256
    }

    /// Whether this signature over `data` verifies under `key`.
    func verifies(_ data: Data, by key: PublicKeyPacket) -> Bool {
        guard version == key.version, algorithm == key.algorithm, !digestTooShort(for: key) else { return false }
        let trailer = hashedPart + Data([version, 0xFF]) + be32(hashedPart.count)
        guard let digest = HashAlgorithm.digest(hashAlgorithm, salt + data + trailer), digest.prefix(2) == left16 else {
            return false
        }
        switch (key.material, material) {
        case (.ed25519Legacy(let raw), .mpis(let values)) where version == 4 && values.count == 2:
            func pad(_ d: Data) -> Data? { d.count <= 32 ? Data(repeating: 0, count: 32 - d.count) + d : nil }
            guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
                let rPart = pad(values[0]), let sPart = pad(values[1])
            else { return false }
            return publicKey.isValidSignature(rPart + sPart, for: digest)
        case (.mldsa65Ed25519(let edKey, let mlKey), .mldsa65Ed25519(let edSignature, let mlSignature)) where version == 6:
            // RFC 9980 §5.2.3: both halves over the same digest, each with an empty context.
            guard let ed = try? Curve25519.Signing.PublicKey(rawRepresentation: edKey),
                let ml = try? MLDSA65.PublicKey(rawRepresentation: mlKey)
            else { return false }
            return ed.isValidSignature(edSignature, for: digest) && ml.isValidSignature(mlSignature, for: digest)
        default:
            return false
        }
    }
}

extension Data {
    /// Upper-case hex, as GnuPG prints fingerprints.
    public var hexUpper: String { map { String(format: "%02X", $0) }.joined() }
    /// Lower-case hex.
    public var hexLower: String { map { String(format: "%02x", $0) }.joined() }
}
