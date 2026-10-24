import CryptoKit
public import Foundation
public import LicenceCore

/// What was issued, written once beside the licence file (schema 2).
public struct Record: Sendable, Equatable {
    public static let schema = 2
    public var licence: Licence
    /// The master key that signed, upper-case hex.
    public var signer: String
    /// SHA-256 of `licence.asc`, lower-case hex.
    public var tokenSHA256: String
    /// The licensor's own reference to the agreement; never in the token.
    public var contract: String?
    /// The licence this one renews.
    public var renews: UUID?
    public var recordedAt: Date

    public init(licence: Licence, signer: String, tokenSHA256: String, contract: String?, renews: UUID?, recordedAt: Date) {
        self.licence = licence
        self.signer = signer
        self.tokenSHA256 = tokenSHA256
        self.contract = contract
        self.renews = renews
        self.recordedAt = recordedAt
    }

    /// `record.json` as serde_json writes it.
    public var json: Data {
        var pairs: [(String, PrettyJSON)] = [
            ("schema", .int(Self.schema)), ("licence", licence.prettyJSON),
            ("signer", .string(signer)), ("token_sha256", .string(tokenSHA256)),
        ]
        if let contract { pairs.append(("contract", .string(contract))) }
        if let renews { pairs.append(("renews", .string(renews.uuidString.lowercased()))) }
        pairs.append(("recorded_at", .string(Timestamp.format(recordedAt))))
        return Data(PrettyJSON.object(pairs).text.utf8)
    }

    /// Read `record.json`, strictly: schema 2 and no unknown field.
    public init(json data: Data, path: String) throws(RegisterError) {
        do {
            self = try JSONDecoder().decode(Record.self, from: data)
        } catch let error as RegisterError {
            throw error.at(path)
        } catch {
            throw .record(path, Self.reason(error))
        }
    }

    static func reason(_ error: any Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, _): "no \(key.stringValue)"
        case DecodingError.typeMismatch(_, let c), DecodingError.valueNotFound(_, let c), DecodingError.dataCorrupted(let c):
            c.codingPath.isEmpty ? "not a JSON object" : c.codingPath.map(\.stringValue).joined(separator: ".")
        case let f as Licence.Failure: "licence: \(f)"
        default: "not a JSON object"
        }
    }
}

extension Record: Decodable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: JSONKey.self)
        let known: Set = ["schema", "licence", "signer", "token_sha256", "contract", "renews", "recorded_at"]
        if let extra = c.allKeys.map(\.stringValue).first(where: { !known.contains($0) }) {
            throw RegisterError.record("", "unknown field \(extra)")
        }
        let schema = try c.decode(Int.self, forKey: JSONKey("schema"))
        guard schema == Self.schema else { throw RegisterError.schema("", schema) }
        let renews = try c.decodeIfPresent(String.self, forKey: JSONKey("renews")).map { s in
            guard let u = UUID(uuidString: s) else { throw RegisterError.record("", "renews") }
            return u
        }
        guard let at = Timestamp.parse(try c.decode(String.self, forKey: JSONKey("recorded_at"))) else {
            throw RegisterError.record("", "recorded_at")
        }
        self.init(
            licence: try c.decode(Licence.self, forKey: JSONKey("licence")),
            signer: try c.decode(String.self, forKey: JSONKey("signer")),
            tokenSHA256: try c.decode(String.self, forKey: JSONKey("token_sha256")),
            contract: try c.decodeIfPresent(String.self, forKey: JSONKey("contract")), renews: renews, recordedAt: at)
    }
}

/// That a licence no longer counts from `effective`, written once beside it.
public struct Revocation: Sendable, Equatable {
    public var licenceID: UUID
    public var effective: CivilDate
    public var reason: String
    public var recordedAt: Date

    public init(licenceID: UUID, effective: CivilDate, reason: String, recordedAt: Date) {
        self.licenceID = licenceID
        self.effective = effective
        self.reason = reason
        self.recordedAt = recordedAt
    }

    public var json: Data {
        Data(
            PrettyJSON.object([
                ("schema", .int(Record.schema)), ("licence_id", .string(licenceID.uuidString.lowercased())),
                ("effective", .string(effective.description)), ("reason", .string(reason)),
                ("recorded_at", .string(Timestamp.format(recordedAt))),
            ]).text.utf8)
    }

    public init(json data: Data, path: String) throws(RegisterError) {
        do { self = try JSONDecoder().decode(Revocation.self, from: data) } catch { throw .record(path, "not a revocation") }
    }
}

extension Revocation: Decodable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: JSONKey.self)
        let known: Set = ["schema", "licence_id", "effective", "reason", "recorded_at"]
        guard c.allKeys.allSatisfy({ known.contains($0.stringValue) }), try c.decode(Int.self, forKey: JSONKey("schema")) == Record.schema,
            let id = UUID(uuidString: try c.decode(String.self, forKey: JSONKey("licence_id"))),
            let effective = CivilDate(try c.decode(String.self, forKey: JSONKey("effective"))),
            let at = Timestamp.parse(try c.decode(String.self, forKey: JSONKey("recorded_at")))
        else { throw RegisterError.record("", "not a revocation") }
        self.init(licenceID: id, effective: effective, reason: try c.decode(String.self, forKey: JSONKey("reason")), recordedAt: at)
    }
}

/// RFC 3339 timestamps in UTC, as the register stores them.
public enum Timestamp {
    static let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    public static func format(_ date: Date) -> String { date.formatted(style) }

    /// Read a timestamp with any number of fractional digits: serde writes
    /// up to nine, the format style reads three.
    public static func parse(_ text: String) -> Date? {
        guard let dot = text.firstIndex(of: "."), let z = text.lastIndex(of: "Z"), dot < z else {
            return try? Date(text, strategy: Date.ISO8601FormatStyle())
        }
        let fraction = text[text.index(after: dot)..<z].prefix(3)
        return try? Date(text[..<dot] + "." + fraction + "Z", strategy: style)
    }
}

/// Whether a licence file still is what its record says.
public enum Integrity: Sendable, Equatable { case intact, missing, changed }

/// Where a licence stands on a given day.
public enum Standing: Sendable, Equatable {
    case upcoming(starts: CivilDate)
    case inForce(until: CivilDate, daysLeft: Int)
    case ended(on: CivilDate, daysAgo: Int)
    case revoked(from: CivilDate)
}

/// One licence folder: `register/<customer>/<licence-id>/`.
public struct Entry: Sendable, Equatable, Identifiable {
    public let record: Record
    public let revocation: Revocation?
    /// The customer folder name.
    public let customer: String
    /// The licence folder, `register/<customer>/<licence-id>`.
    public let folder: String
    public let integrity: Integrity

    public var id: UUID { record.licence.id }
    public var licence: Licence { record.licence }
    public var licenceFile: String { "\(folder)/licence.asc" }

    public func standing(on today: CivilDate) -> Standing {
        if let r = revocation, r.effective <= today { return .revoked(from: r.effective) }
        if today < licence.notBefore { return .upcoming(starts: licence.notBefore) }
        if today > licence.notAfter { return .ended(on: licence.notAfter, daysAgo: licence.notAfter.days(until: today)) }
        return .inForce(until: licence.notAfter, daysLeft: today.days(until: licence.notAfter))
    }
}

/// A customer: one folder under `register/` with every licence issued to it.
public struct Customer: Sendable, Equatable, Identifiable, Hashable {
    public let slug: String
    /// The licensee as the newest licence spells it.
    public let name: String
    /// Licence ids, newest first.
    public let licences: [UUID]
    public var id: String { slug }
}

/// Something that needs the licensor.
public enum Todo: Sendable, Equatable, Identifiable {
    case endingSoon(customer: String, licence: UUID, daysLeft: Int)
    case endedWithoutRenewal(customer: String, licence: UUID, daysAgo: Int)

    public var id: UUID {
        switch self {
        case .endingSoon(_, let l, _), .endedWithoutRenewal(_, let l, _): l
        }
    }
}

/// Every licence ever issued.
public struct LicenceRegister: Sendable, Equatable {
    /// Days before its last day that a licence counts as ending soon.
    public static let endingSoonDays = 60
    /// Days after its last day that a licence without a successor is still worth mentioning.
    public static let recentlyEndedDays = 90

    /// Every entry, by customer folder, then by first day.
    public let entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries.sorted {
            ($0.customer, $0.licence.notBefore, $0.id.uuidString) < ($1.customer, $1.licence.notBefore, $1.id.uuidString)
        }
    }

    /// Read every licence folder in the snapshot. A malformed record refuses
    /// the whole read, because a register that skips a licence would let
    /// attestation miss it.
    public init(_ snapshot: Snapshot) throws(RegisterError) {
        var entries: [Entry] = []
        for path in snapshot.paths(under: "register/") where path.hasSuffix("/record.json") {
            let parts = path.split(separator: "/")
            guard parts.count == 4 else { continue }
            let folder = parts.dropLast().joined(separator: "/")
            let record = try Record(json: snapshot.files[path]!, path: path)
            let revocation = try snapshot.files["\(folder)/revocation.json"].map { (d: Data) throws(RegisterError) in
                try Revocation(json: d, path: "\(folder)/revocation.json")
            }
            let integrity: Integrity =
                switch snapshot.files["\(folder)/licence.asc"] {
                case nil: .missing
                case let d? where sha256Hex(d) == record.tokenSHA256: .intact
                default: .changed
                }
            entries.append(Entry(record: record, revocation: revocation, customer: String(parts[1]), folder: folder, integrity: integrity))
        }
        self.init(entries: entries)
    }

    public func entry(_ id: UUID) -> Entry? { entries.first { $0.id == id } }

    /// Every customer, by name.
    public var customers: [Customer] {
        Dictionary(grouping: entries, by: \.customer).map { slug, es in
            let newest = es.sorted { ($0.licence.notBefore, $0.id.uuidString) > ($1.licence.notBefore, $1.id.uuidString) }
            return Customer(slug: slug, name: newest[0].licence.licensee, licences: newest.map(\.id))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func customer(_ slug: String) -> Customer? { customers.first { $0.slug == slug } }

    /// The licence that speaks for `customer` today: the one in force that
    /// lasts longest, else the next to start, else the newest.
    public func current(_ customer: Customer, on today: CivilDate) -> Entry? {
        let es = customer.licences.compactMap(entry)
        let inForce = es.filter { if case .inForce = $0.standing(on: today) { true } else { false } }
            .max { $0.licence.notAfter < $1.licence.notAfter }
        let upcoming = es.filter { if case .upcoming = $0.standing(on: today) { true } else { false } }
            .min { $0.licence.notBefore < $1.licence.notBefore }
        return inForce ?? upcoming ?? es.first
    }

    /// Whether a licence for the same customer starts after `entry` and is
    /// not revoked, or names it as the licence it renews.
    public func hasSuccessor(_ entry: Entry) -> Bool {
        entries.contains { other in
            other.id != entry.id && other.revocation == nil
                && (other.record.renews == entry.id
                    || (other.customer == entry.customer && other.licence.notBefore > entry.licence.notBefore))
        }
    }

    /// What needs the licensor today: licences still in force first, soonest
    /// end first, then the ones that ended, most recent first.
    public func todo(on today: CivilDate) -> [Todo] {
        var out: [(Int, Int, Todo)] = []
        for c in customers {
            guard let e = current(c, on: today), !hasSuccessor(e) else { continue }
            switch e.standing(on: today) {
            case .inForce(_, let left) where left <= Self.endingSoonDays:
                out.append((0, left, .endingSoon(customer: c.slug, licence: e.id, daysLeft: left)))
            case .ended(_, let ago) where ago <= Self.recentlyEndedDays:
                out.append((1, ago, .endedWithoutRenewal(customer: c.slug, licence: e.id, daysAgo: ago)))
            default: break
            }
        }
        return out.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
    }
}

/// A licensee name as a folder name: lower-case ASCII letters and digits,
/// runs of anything else collapsed to one hyphen; `licensee` when nothing survives.
public func slug(_ licensee: String) -> String {
    var out = ""
    var hyphen = false
    for c in licensee.unicodeScalars {
        if c.isASCII, CharacterSet.alphanumerics.contains(c) {
            if hyphen, !out.isEmpty { out.append("-") }
            hyphen = false
            out.unicodeScalars.append(c)
        } else {
            hyphen = true
        }
    }
    return out.isEmpty ? "licensee" : out.lowercased()
}

/// SHA-256 of `data`, lower-case hex.
public func sha256Hex(_ data: Data) -> String { Data(SHA256.hash(data: data)).hexLower }
