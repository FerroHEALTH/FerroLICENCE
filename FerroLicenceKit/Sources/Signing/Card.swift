public import Foundation
import LicenceCore
public import Register

/// The card plugged in now, as `gpg --card-status --with-colons` reports it.
public struct CardStatus: Sendable, Equatable {
    /// The serial number printed on the YubiKey.
    public var serial: String
    public var vendor: String
    /// The key in the signature slot, upper-case hex.
    public var signatureKey: String?
    /// The PIN is asked on every signature (`forcesig`).
    public var pinEverySignature: Bool
    public var signaturesMade: Int
    /// All three key slots are Curve 25519.
    public var curve25519: Bool
    /// PIN tries left, when the card reports them.
    public var pinTriesLeft: Int?
    /// Touch is required to sign (`uif` for the signature key).
    public var touchToSign: Bool?

    /// Read the colon listing; `nil` when it names no card.
    public init?(colons: String) {
        serial = ""
        vendor = ""
        pinEverySignature = false
        signaturesMade = 0
        curve25519 = false
        var curves = 0
        for line in colons.split(separator: "\n") {
            let f = line.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            func field(_ i: Int) -> String { i < f.count ? f[i] : "" }
            switch field(0) {
            case "serial": serial = field(1)
            case "vendor": vendor = field(2)
            case "forcepin": pinEverySignature = field(1) == "1"
            case "sigcount": signaturesMade = Int(field(1)) ?? 0
            case "pinretry": pinTriesLeft = Int(field(1))
            case "uif": touchToSign = field(1) != "0" && !field(1).isEmpty
            case "keyattr":
                if ["ed25519", "cv25519", "curve25519"].contains(field(3).lowercased()) { curves += 1 }
            case "fpr":
                let fpr = field(1).uppercased()
                if !fpr.isEmpty, fpr.contains(where: { $0 != "0" }) { signatureKey = fpr }
            default: break
            }
        }
        curve25519 = curves == 3
        if serial.isEmpty { return nil }
    }
}

/// A primary key whose secret is on a card this keyring knows.
public struct CardKey: Sendable, Equatable {
    public let fingerprint: String
    /// The card's application id as GnuPG lists it.
    public let card: String

    /// The card's serial number, from its application id.
    public var serial: String {
        let a = Array(card)
        guard a.count == 32, card.hasPrefix("D276000124") else { return card }
        let digits = String(a[20..<28])
        let trimmed = digits.drop { $0 == "0" }
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    /// Every `sec` record whose secret is on a card, never on disk, never a stub.
    static func parse(_ listing: String) -> [CardKey] {
        var out: [CardKey] = []
        var pending: String?
        for line in listing.split(separator: "\n") {
            let f = line.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            switch f.first {
            case "sec":
                let card = f.count > 14 ? f[14] : ""
                pending = ["", "#", "+"].contains(card) ? nil : card
            case "fpr":
                if let card = pending, f.count > 9 { out.append(CardKey(fingerprint: f[9], card: card)) }
                pending = nil
            default: pending = nil
            }
        }
        return out
    }
}

/// A primary key as the public keyring lists it.
public struct PublicPrimary: Sendable, Equatable {
    public let fingerprint: String
    public let algorithm: Int
    public let curve: String
    public let canSign: Bool
    public let validity: String

    /// Ed25519, may sign, neither expired nor revoked.
    public var canIssue: Bool {
        algorithm == 22 && curve == "ed25519" && canSign && !["e", "r", "d", "i"].contains(validity)
    }

    static func parse(_ listing: String) -> PublicPrimary? {
        var pending: (Int, String, Bool, String)?
        for line in listing.split(separator: "\n") {
            let f = line.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            func field(_ i: Int) -> String { i < f.count ? f[i] : "" }
            if field(0) == "pub", pending == nil {
                pending = (Int(field(3)) ?? 0, field(16), field(11).contains("s"), field(1))
            } else if field(0) == "fpr", let p = pending {
                return PublicPrimary(fingerprint: field(9), algorithm: p.0, curve: p.1, canSign: p.2, validity: p.3)
            }
        }
        return nil
    }
}

/// A master key that may sign here: trusted, and on the YubiKey plugged in
/// now. Only `signingKey` makes one, so nothing signs with a key on disk.
public struct SigningKey: Sendable, Equatable {
    public let fingerprint: String
    public let serial: String

    #if DEBUG
        /// Tests only, for CI's throwaway keyring, which has no YubiKey. Debug
        /// builds alone compile it, so no release can sign with a key on disk.
        static func softwareForTests(_ fingerprint: String) -> SigningKey { SigningKey(fingerprint: fingerprint, serial: "test") }
    #endif
}

/// Why nothing can sign right now.
public enum NoSigningKey: Error, Equatable, Sendable, CustomStringConvertible {
    case noCard
    case emptyCard(serial: String)
    case untrusted(serial: String, fingerprint: String)
    case gnupg(GnuPGError)

    public var message: LocalizedStringResource {
        switch self {
        case .noCard: LocalizedStringResource("Plug in your YubiKey.", bundle: #bundle)
        case .emptyCard(let s): LocalizedStringResource("YubiKey \(s) holds no key yet. Set it up under Keys.", bundle: #bundle)
        case .untrusted(let s, let f):
            LocalizedStringResource("The key on YubiKey \(s) (\(short(f))) is not a trusted key.", bundle: #bundle)
        case .gnupg(let e): e.message
        }
    }

    public var description: String { String(localized: message) }
}

extension GnuPG {
    /// The key on the YubiKey plugged in now, if it may sign. When the
    /// keyring does not know the card's key yet, its public certificate is
    /// imported from the register's `keys/`, so no manual step is needed.
    public func signingKey(keys: Keys) async throws(NoSigningKey) -> SigningKey {
        let card: CardStatus
        do {
            guard let c = try await cardStatus() else { throw NoSigningKey.noCard }
            card = c
        } catch let e as NoSigningKey { throw e } catch let e as GnuPGError { throw .gnupg(e) } catch { throw .noCard }
        guard let fpr = card.signatureKey else { throw .emptyCard(serial: card.serial) }
        guard let anchor = keys.trusted.first(where: { $0.fingerprint == fpr }) else {
            throw .untrusted(serial: card.serial, fingerprint: fpr)
        }
        do {
            if try await !cardKeys().contains(where: { $0.fingerprint == fpr }) {
                try await importPublic(anchor.armored)
                _ = try await cardStatus()  // creates the card stubs for the imported key
            }
        } catch { throw .gnupg(error) }
        return SigningKey(fingerprint: fpr, serial: card.serial)
    }

    /// Sign `text` on the card with `key`. The PIN window and the touch are
    /// GnuPG's and the card's; this only waits.
    public func sign(_ text: String, with key: SigningKey) async throws(GnuPGError) -> String {
        let signed = try await clearsign(text, with: key.fingerprint)
        let certificate = try await exportPublic(key.fingerprint)
        return Token.assemble(signed: signed, certificate: certificate)
    }
}
