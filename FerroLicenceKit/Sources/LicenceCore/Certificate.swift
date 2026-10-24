public import Foundation

/// A transferable public key (RFC 9580 §10.1): the primary key, its direct
/// signatures, its user ids with their signatures, and its subkeys with
/// their bindings.
public struct Certificate: Equatable, Sendable {
    /// The primary key.
    public let primary: PublicKeyPacket
    let direct: [SignaturePacket]
    let users: [(id: Data, signatures: [SignaturePacket])]
    let subkeys: [(key: PublicKeyPacket, signatures: [SignaturePacket])]

    public static func == (a: Certificate, b: Certificate) -> Bool {
        a.primary == b.primary && a.direct == b.direct
            && a.users.map(\.id) == b.users.map(\.id) && a.subkeys.map(\.key) == b.subkeys.map(\.key)
    }

    /// Read an armored `PGP PUBLIC KEY BLOCK`.
    public init(armored: String) throws {
        try self.init(packets: try Armor.decode(armored, kind: "PGP PUBLIC KEY BLOCK"))
    }

    /// Read the binary packets of a transferable public key.
    public init(packets data: Data) throws {
        let packets = try Packet.all(in: data)
        guard let first = packets.first, first.tag == 6 else { throw PacketFailure.malformed("no primary key") }
        primary = try PublicKeyPacket(body: first.body)
        var direct: [SignaturePacket] = []
        var users: [(Data, [SignaturePacket])] = []
        var subkeys: [(PublicKeyPacket, [SignaturePacket])] = []
        enum Owner { case primary, user, attribute, subkey }
        var owner = Owner.primary
        for packet in packets.dropFirst() {
            switch packet.tag {
            case 2:
                let signature = try SignaturePacket(body: packet.body)
                switch owner {
                case .primary: direct.append(signature)
                case .user: users[users.count - 1].1.append(signature)
                case .subkey: subkeys[subkeys.count - 1].1.append(signature)
                case .attribute: break
                }
            case 13:
                users.append((packet.body, []))
                owner = .user
            case 17: owner = .attribute
            case 14:
                subkeys.append((try PublicKeyPacket(body: packet.body), []))
                owner = .subkey
            case 12: break  // trust packets carry no meaning outside a keyring
            default: throw PacketFailure.malformed("packet tag \(packet.tag) in a certificate")
            }
        }
        self.direct = direct
        self.users = users.map { (id: $0.0, signatures: $0.1) }
        self.subkeys = subkeys.map { (key: $0.0, signatures: $0.1) }
    }

    /// Whether every self-signature and binding verifies under the primary:
    /// direct signatures, user id certifications, subkey bindings, and the
    /// back-signature of a subkey that may sign.
    public func bindingsVerify() -> Bool {
        let p = primary.framed
        for s in direct where !s.verifies(p, by: primary) { return false }
        for user in users {
            var data = p
            let n = UInt32(user.id.count)
            data.append(contentsOf: [0xB4, UInt8(n >> 24), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)])
            data.append(user.id)
            for s in user.signatures where !s.verifies(data, by: primary) { return false }
        }
        for sub in subkeys {
            let data = p + sub.key.framed
            for s in sub.signatures {
                guard s.verifies(data, by: primary) else { return false }
                if let embedded = s.hashed.embedded ?? s.unhashed.embedded, sub.key.ed25519 != nil {
                    guard let back = try? SignaturePacket(body: embedded), back.type == 0x19,
                        back.verifies(data, by: sub.key)
                    else { return false }
                }
            }
        }
        return true
    }

    /// The primary's newest self-signature that can carry its key flags and
    /// expiry: a direct-key signature or a user id certification.
    var newestSelfSignature: SignaturePacket? {
        (direct + users.flatMap(\.signatures))
            .filter { [0x1F, 0x10, 0x11, 0x12, 0x13].contains($0.type) }
            // The last of equally new signatures wins, as in the Rust checker.
            .reduce(nil) { best, s in
                guard let best else { return s }
                return (s.created ?? .distantPast) >= (best.created ?? .distantPast) ? s : best
            }
    }
}
