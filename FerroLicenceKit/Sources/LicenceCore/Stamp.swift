import CryptoKit
public import Foundation

/// The identifier stamp: sixteen keyed bits in the last two bytes of every
/// server-minted UUIDv7, `HMAC-SHA256(key, timestamp_ms)[0..2]`
/// (`docs/design.md` §7).
public struct StampKey: Sendable {
    /// The public constant every build without a licence stamps with.
    public static let unlicensedMaterial = Data("ferroehr/unlicensed/v1".utf8)
    /// Prefixed to a licence id's sixteen raw bytes.
    public static let licencePrefix = Data("ferroehr/licence/v1/".utf8)

    let key: SymmetricKey

    public init(material: Data) {
        key = SymmetricKey(data: material)
    }

    /// The key of the build without a licence.
    public static var unlicensed: StampKey { StampKey(material: unlicensedMaterial) }

    /// The key of a licence.
    public static func licence(_ id: UUID) -> StampKey {
        StampKey(material: licencePrefix + id.data)
    }

    /// The two stamp bytes for an identifier minted at `timestampMs`.
    public func stamp16(_ timestampMs: UInt64) -> Data {
        var be = timestampMs.bigEndian
        let message = withUnsafeBytes(of: &be) { Data($0) }
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: key).prefix(2))
    }

    /// `id` with its last two bytes replaced by this key's stamp; `nil` when
    /// it is not a version 7 UUID.
    public func stamp(_ id: UUID) -> UUID? {
        guard let ts = id.timestampMs else { return nil }
        var bytes = id.data
        let tag = stamp16(ts)
        bytes[14] = tag[tag.startIndex]
        bytes[15] = tag[tag.startIndex + 1]
        return UUID(data: bytes)
    }

    /// Whether `id` carries this key's stamp.
    public func carries(_ id: UUID) -> Bool {
        guard let ts = id.timestampMs else { return false }
        return stamp16(ts) == id.data.suffix(2)
    }
}

extension UUID {
    /// The sixteen raw bytes.
    public var data: Data { withUnsafeBytes(of: uuid) { Data($0) } }

    /// A UUID from sixteen raw bytes.
    public init?(data: Data) {
        guard data.count == 16 else { return nil }
        let b = [UInt8](data)
        self.init(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// The 48-bit millisecond timestamp of a version 7 UUID.
    public var timestampMs: UInt64? {
        let b = [UInt8](data)
        guard b[6] >> 4 == 7 else { return nil }
        return b[0..<6].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }
}
