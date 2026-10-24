public import Foundation

/// A day on the UTC calendar, the only calendar licence windows are read in.
public struct CivilDate: Hashable, Comparable, Sendable, CustomStringConvertible, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// A valid date, or `nil`.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let parts = DateComponents(year: year, month: month, day: day)
        guard let date = Self.calendar.date(from: parts),
            Self.calendar.component(.day, from: date) == day,
            Self.calendar.component(.month, from: date) == month
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// `YYYY-MM-DD`, strictly.
    public init?(_ text: some StringProtocol) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
            let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// The UTC day `date` falls on.
    public init(_ date: Date) {
        let c = Self.calendar.dateComponents([.year, .month, .day], from: date)
        year = c.year!
        month = c.month!
        day = c.day!
    }

    /// Today in UTC.
    public static var today: CivilDate { CivilDate(Date()) }

    /// Midnight UTC at the start of this day.
    public var start: Date { Self.calendar.date(from: DateComponents(year: year, month: month, day: day))! }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (a: CivilDate, b: CivilDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    /// `count` days later, or earlier when negative.
    public func adding(days count: Int) -> CivilDate {
        CivilDate(Self.calendar.date(byAdding: .day, value: count, to: start)!)
    }

    /// Whole days from `self` to `other`.
    public func days(until other: CivilDate) -> Int {
        Self.calendar.dateComponents([.day], from: start, to: other.start).day!
    }

    /// The last day of a one-year licence starting on this day: the day before
    /// its anniversary. A licence starting on 29 February has its anniversary
    /// on 1 March of a common year, so it ends on 28 February.
    public var oneYearLater: CivilDate {
        if month == 2, day == 29 { return CivilDate(year: year + 1, month: 2, day: 28)! }
        let anniversary = CivilDate(year: year + 1, month: month, day: day)!
        return anniversary.adding(days: -1)
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let date = CivilDate(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a YYYY-MM-DD date: \(text)"))
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

/// What a licence grants.
public enum Use: String, Codable, Sendable, CaseIterable {
    /// Production use in the course of a business: a paid licence.
    case commercial
    /// What BUSL-1.1 gives everyone; every FerroEHR build embeds it.
    case nonCommercial = "non-commercial"
}

/// The signed document: six fields, nothing more.
public struct Licence: Equatable, Hashable, Sendable {
    /// Stable identity of the grant, also the material of its stamp key.
    public var id: UUID
    /// The legal entity the grant is issued to.
    public var licensee: String
    /// The day the token was signed.
    public var issued: CivilDate
    /// First valid day, inclusive, UTC.
    public var notBefore: CivilDate
    /// Last valid day, inclusive, UTC.
    public var notAfter: CivilDate
    /// What the grant permits.
    public var use: Use

    public init(id: UUID, licensee: String, issued: CivilDate, notBefore: CivilDate, notAfter: CivilDate, use: Use) {
        self.id = id
        self.licensee = licensee
        self.issued = issued
        self.notBefore = notBefore
        self.notAfter = notAfter
        self.use = use
    }

    /// The field names, in wire order.
    static let keys = ["licence_id", "licensee", "issued", "not_before", "not_after", "use"]

    /// Why a text is not a licence document.
    public enum Failure: Error, Equatable, Sendable {
        /// Not a JSON object.
        case notAnObject
        /// A field is missing, unknown or of the wrong type; the name says which.
        case field(String)
    }

    /// Parse a signed text strictly: exactly the six fields, each a string of
    /// the right shape. An unknown field refuses the document.
    public static func parse(_ text: String) throws(Failure) -> Licence {
        do {
            return try JSONDecoder().decode(Licence.self, from: Data(text.utf8))
        } catch let failure as Failure {
            throw failure
        } catch DecodingError.typeMismatch(_, let context) where !context.codingPath.isEmpty {
            throw .field(context.codingPath[0].stringValue)
        } catch DecodingError.keyNotFound(let key, _) {
            throw .field(key.stringValue)
        } catch {
            throw .notAnObject
        }
    }

    /// The exact text that is signed: pretty JSON in field order, two-space
    /// indent, `"key": value`, one trailing newline, written as serde_json
    /// writes it so the bytes match FerroEHR's reader.
    public var canonicalJSON: String {
        let values = [
            id.uuidString.lowercased(), licensee, issued.description, notBefore.description,
            notAfter.description, use.rawValue,
        ]
        let body = zip(Self.keys, values).map { "  \(Self.quote($0)): \(Self.quote($1))" }.joined(separator: ",\n")
        return "{\n\(body)\n}\n"
    }

    /// A JSON string literal, escaped the way serde_json escapes it.
    static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case let c where c.value < 0x20: out += String(format: "\\u%04x", c.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// Where `day` falls relative to the window.
    public func window(on day: CivilDate) -> Window {
        day < notBefore ? .notYetValid : day > notAfter ? .expired : .active
    }

    /// Where a day falls relative to a licence's window.
    public enum Window: Sendable { case notYetValid, active, expired }
}

extension Licence: Decodable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: JSONKey.self)
        if let extra = c.allKeys.map(\.stringValue).filter({ !Self.keys.contains($0) }).sorted().first { throw Failure.field(extra) }
        func date(_ key: String) throws -> CivilDate {
            guard let d = CivilDate(try c.decode(String.self, forKey: JSONKey(key))) else { throw Failure.field(key) }
            return d
        }
        guard let id = UUID(uuidString: try c.decode(String.self, forKey: JSONKey("licence_id"))) else { throw Failure.field("licence_id") }
        guard let use = Use(rawValue: try c.decode(String.self, forKey: JSONKey("use"))) else { throw Failure.field("use") }
        self.init(
            id: id, licensee: try c.decode(String.self, forKey: JSONKey("licensee")), issued: try date("issued"),
            notBefore: try date("not_before"), notAfter: try date("not_after"), use: use)
    }
}

/// A JSON object key by name, for readers that refuse unknown fields.
public struct JSONKey: CodingKey, Sendable {
    public let stringValue: String
    public var intValue: Int? { nil }
    public init(_ name: String) { stringValue = name }
    public init(stringValue: String) { self.stringValue = stringValue }
    public init?(intValue: Int) { nil }
}

extension CivilDate: CustomLocalizedStringResourceConvertible {
    /// The day as the reader's language writes it, `1 Dec 2025` or
    /// `1 dec 2025`, in UTC so it is the same day everywhere.
    ///
    /// Its spaces are no-break spaces, so a sentence wraps around a day and
    /// never through it.
    public var localizedStringResource: LocalizedStringResource {
        let day = start.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
        return "\(day.replacing(" ", with: "\u{00A0}"))"
    }
}
