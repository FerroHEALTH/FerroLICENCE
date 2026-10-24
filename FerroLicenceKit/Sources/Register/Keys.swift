public import Foundation
public import LicenceCore

/// A certificate under `keys/` or `keys/retired/`.
public struct Anchor: Sendable, Equatable {
    public let path: String
    public let fingerprint: String
    public let certificate: Certificate
    public let armored: String
}

/// Whether a key may still be used. A lost key and a handed-over key are
/// both still trusted, so their licences stay valid, and both sign nothing
/// new; a retired key is trusted no more.
public enum KeyStatus: String, Codable, Sendable, CaseIterable {
    case active
    case lost
    case handedOver = "handed-over"
    case retired

    /// The word on screen.
    public var label: LocalizedStringResource {
        switch self {
        case .active: LocalizedStringResource("In Use", bundle: #bundle)
        case .lost: LocalizedStringResource("Lost", bundle: #bundle)
        case .handedOver: LocalizedStringResource("Handed Over", bundle: #bundle)
        case .retired: LocalizedStringResource("Retired", bundle: #bundle)
        }
    }

    /// Still trusted, and signs nothing new.
    public var stoppedSigning: Bool { self == .lost || self == .handedOver }
}

/// One row of `signers.json`.
public struct Signer: Codable, Equatable, Sendable {
    public var fingerprint: String
    public var holder: String
    /// Where its secret lives, such as `YubiKey 40729502`.
    public var medium: String
    public var added: CivilDate
    public var status: KeyStatus
    /// The day the status last changed, when it is not `active`.
    public var since: CivilDate?
    /// The holder's GitHub login, so the app knows who is signed in.
    public var github: String?

    public init(
        fingerprint: String, holder: String, medium: String, added: CivilDate, status: KeyStatus,
        since: CivilDate? = nil, github: String? = nil
    ) {
        self.fingerprint = fingerprint
        self.holder = holder
        self.medium = medium
        self.added = added
        self.status = status
        self.since = since
        self.github = github
    }
}

/// Every key the repository knows: trusted, retired, and who holds them.
public struct Keys: Sendable, Equatable {
    public var trusted: [Anchor]
    public var retired: [Anchor]
    public var signers: [Signer]

    public init(trusted: [Anchor] = [], retired: [Anchor] = [], signers: [Signer] = []) {
        self.trusted = trusted
        self.retired = retired
        self.signers = signers
    }

    /// Read all three from a snapshot.
    public init(_ snapshot: Snapshot) throws {
        func load(_ dir: String) throws -> [Anchor] {
            try snapshot.paths(under: dir).filter { path in
                path.hasSuffix(".asc") && !path.dropFirst(dir.count).contains("/")
            }.map { path in
                let text = snapshot.text(path) ?? ""
                guard text.contains("-----BEGIN PGP PUBLIC KEY BLOCK-----") else { throw RegisterError.notACertificate(path) }
                let cert: Certificate
                do { cert = try Certificate(armored: text) } catch { throw RegisterError.notACertificate(path) }
                guard cert.bindingsVerify() else { throw RegisterError.brokenBindings(path) }
                return Anchor(path: path, fingerprint: cert.primary.fingerprintHex, certificate: cert, armored: text)
            }
        }
        trusted = try load("keys/")
        retired = try load("keys/retired/")
        if let data = snapshot.files["signers.json"] {
            do { signers = try JSONDecoder().decode([Signer].self, from: data) } catch {
                throw RegisterError.signers(String(describing: error))
            }
        } else {
            signers = []
        }
    }

    /// The trusted certificates, as the checker takes them.
    public var certificates: [Certificate] { trusted.map(\.certificate) }

    public func isTrusted(_ fingerprint: String) -> Bool {
        trusted.contains { $0.fingerprint.caseInsensitiveCompare(fingerprint) == .orderedSame }
    }

    public func signer(_ fingerprint: String) -> Signer? {
        signers.first { $0.fingerprint.caseInsensitiveCompare(fingerprint) == .orderedSame }
    }

    public func signer(github login: String) -> Signer? {
        signers.first { $0.github?.caseInsensitiveCompare(login) == .orderedSame && $0.status != .retired }
    }

    /// Who holds `fingerprint`, or the shortened fingerprint.
    public func holder(_ fingerprint: String) -> String { signer(fingerprint)?.holder ?? short(fingerprint) }

    /// Where `keys/`, `keys/retired/` and `signers.json` disagree, in words.
    public var problems: [String] {
        var out: [String] = []
        for a in trusted {
            if let s = signer(a.fingerprint) {
                if s.status == .retired { out.append("\(short(a.fingerprint)) is marked retired but is still trusted under keys/") }
            } else {
                out.append("\(short(a.fingerprint)) is trusted but signers.json does not name its holder")
            }
        }
        for a in retired where signer(a.fingerprint).map({ $0.status != .retired }) ?? false {
            out.append("\(short(a.fingerprint)) is under keys/retired/ but signers.json does not say retired")
        }
        return out
    }

    /// `signers.json` as the app writes it, in the file's own field order.
    public static func encode(_ signers: [Signer]) -> Data {
        let rows: [PrettyJSON] = signers.map { s in
            var pairs: [(String, PrettyJSON)] = [
                ("fingerprint", .string(s.fingerprint)), ("holder", .string(s.holder)),
                ("medium", .string(s.medium)), ("added", .string(s.added.description)),
                ("status", .string(s.status.rawValue)),
            ]
            if let since = s.since { pairs.append(("since", .string(since.description))) }
            if let github = s.github { pairs.append(("github", .string(github))) }
            return .object(pairs)
        }
        return Data(PrettyJSON.array(rows).text.utf8)
    }
}

/// `F2D2…406D`.
public func short(_ fingerprint: String) -> String {
    fingerprint.count > 8 ? "\(fingerprint.prefix(4))…\(fingerprint.suffix(4))" : fingerprint
}

/// `F2D2 14FC 3069 8BA6 5A84  6B2B F2EA 48D4 C316 406D`, as GnuPG prints it.
public func grouped(_ fingerprint: String) -> String {
    var out = ""
    for (i, c) in fingerprint.enumerated() {
        if i > 0, i % 4 == 0 { out += i == 20 ? "  " : " " }
        out.append(c)
    }
    return out
}

/// Why the register or the keys could not be read.
public enum RegisterError: Error, Equatable, Sendable, CustomStringConvertible {
    case notACertificate(String)
    case brokenBindings(String)
    case signers(String)
    case record(String, String)
    case schema(String, Int)

    public var message: LocalizedStringResource {
        switch self {
        case .notACertificate(let p): LocalizedStringResource("\(p) is not a public certificate", bundle: #bundle)
        case .brokenBindings(let p): LocalizedStringResource("\(p) has broken self-bindings", bundle: #bundle)
        case .signers(let why): LocalizedStringResource("signers.json is not a signer list: \(why)", bundle: #bundle)
        case .record(let p, let why): LocalizedStringResource("\(p) is not a register record: \(why)", bundle: #bundle)
        case .schema(let p, let n): LocalizedStringResource("\(p) has schema \(n); this app reads schema 2", bundle: #bundle)
        }
    }

    public var description: String { String(localized: message) }

    /// The same error, naming `path` where it was thrown without one.
    func at(_ path: String) -> RegisterError {
        switch self {
        case .record("", let why): .record(path, why)
        case .schema("", let n): .schema(path, n)
        default: self
        }
    }
}
