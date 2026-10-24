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

/// A version 4 public key or subkey packet.
public struct PublicKeyPacket: Equatable, Sendable {
    /// The packet body, the bytes trust is decided on.
    public let body: Data
    /// When the key was made.
    public let created: Date
    /// The public-key algorithm (22 is legacy EdDSA, 18 ECDH, 1 RSA).
    public let algorithm: UInt8
    /// The Ed25519 public key, when the algorithm is EdDSA on Ed25519.
    let ed25519: Data?

    init(body: Data) throws(PacketFailure) {
        var r = Reader(body)
        guard try r.byte() == 4 else { throw .malformed("only version 4 keys") }
        self.body = body
        created = Date(timeIntervalSince1970: TimeInterval(try r.uint32()))
        algorithm = try r.byte()
        if algorithm == 22 {
            let oid = try r.bytes(Int(try r.byte()))
            let point = try r.mpi()
            if oid == ed25519OID, point.count == 33, point.first == 0x40 {
                ed25519 = point.dropFirst()
            } else {
                ed25519 = nil
            }
        } else {
            ed25519 = nil
        }
    }

    /// The version 4 fingerprint: SHA-1 over the framed packet body.
    public var fingerprint: Data {
        Data(Insecure.SHA1.hash(data: framed))
    }

    /// The fingerprint as GnuPG prints it, upper-case hex.
    public var fingerprintHex: String { fingerprint.hexUpper }

    /// The 64-bit key id: the last eight bytes of the fingerprint.
    public var keyID: Data { fingerprint.suffix(8) }

    /// `0x99`, the body length, the body: how a key enters a signature hash.
    var framed: Data {
        var out = Data([0x99, UInt8(body.count >> 8 & 0xFF), UInt8(body.count & 0xFF)])
        out.append(body)
        return out
    }
}

/// A signature subpacket area, read into the fields the checks use.
struct Subpackets: Equatable {
    var created: Date?
    var keyExpiration: UInt32?
    var keyFlags: Data?
    var issuerKeyID: Data?
    var issuerFingerprint: Data?
    var embedded: Data?

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
            case 33 where value.count == 21 && value.first == 4: issuerFingerprint = Data(value.dropFirst())
            case 32: embedded = Data(value)
            default: break
            }
        }
    }
}

/// A version 4 signature packet.
public struct SignaturePacket: Equatable, Sendable {
    /// The signature type: 0x00 binary, 0x01 text, 0x10 to 0x13 certifications,
    /// 0x18 subkey binding, 0x19 primary key binding, 0x1F direct key.
    public let type: UInt8
    /// The public-key algorithm.
    public let algorithm: UInt8
    /// The hash algorithm (8 SHA-256, 9 SHA-384, 10 SHA-512).
    public let hashAlgorithm: UInt8
    /// Version through the hashed subpackets: what the hash covers after the data.
    let hashedPart: Data
    let hashed: Subpackets
    let unhashed: Subpackets
    let left16: Data
    let mpis: [Data]

    init(body: Data) throws(PacketFailure) {
        var r = Reader(body)
        guard try r.byte() == 4 else { throw .malformed("only version 4 signatures") }
        type = try r.byte()
        algorithm = try r.byte()
        hashAlgorithm = try r.byte()
        let hashedLength = try r.uint16()
        let hashedData = try r.bytes(hashedLength)
        hashedPart = body.subdata(in: body.startIndex..<(body.startIndex + 6 + hashedLength))
        hashed = try Subpackets(hashedData)
        unhashed = try Subpackets(try r.bytes(try r.uint16()))
        left16 = try r.bytes(2)
        var values: [Data] = []
        while !r.atEnd { values.append(try r.mpi()) }
        mpis = values
    }

    /// When it was made, from the hashed area.
    public var created: Date? { hashed.created }

    /// The issuer fingerprint, hashed area first.
    var issuerFingerprint: Data? { hashed.issuerFingerprint ?? unhashed.issuerFingerprint }

    /// The 64-bit issuer key id, hashed area first.
    var issuerKeyID: Data? { hashed.issuerKeyID ?? unhashed.issuerKeyID }

    /// Whether this signature over `data` verifies under `key`.
    func verifies(_ data: Data, by key: PublicKeyPacket) -> Bool {
        guard algorithm == 22, let raw = key.ed25519, mpis.count == 2,
            let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
        else { return false }
        var trailer = hashedPart
        trailer.append(contentsOf: [0x04, 0xFF])
        let n = UInt32(hashedPart.count)
        trailer.append(contentsOf: [UInt8(n >> 24), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)])
        guard let digest = Self.digest(hashAlgorithm, data + trailer), digest.prefix(2) == left16 else {
            return false
        }
        func pad(_ d: Data) -> Data? { d.count <= 32 ? Data(repeating: 0, count: 32 - d.count) + d : nil }
        guard let rPart = pad(mpis[0]), let sPart = pad(mpis[1]) else { return false }
        return publicKey.isValidSignature(rPart + sPart, for: digest)
    }

    static func digest(_ algorithm: UInt8, _ data: Data) -> Data? {
        switch algorithm {
        case 2: Data(Insecure.SHA1.hash(data: data))
        case 8: Data(SHA256.hash(data: data))
        case 9: Data(SHA384.hash(data: data))
        case 10: Data(SHA512.hash(data: data))
        default: nil
        }
    }
}

extension Data {
    /// Upper-case hex, as GnuPG prints fingerprints.
    public var hexUpper: String { map { String(format: "%02X", $0) }.joined() }
    /// Lower-case hex.
    public var hexLower: String { map { String(format: "%02x", $0) }.joined() }
}
