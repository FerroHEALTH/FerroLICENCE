import Foundation

/// A JSON value written the way serde_json's pretty printer writes it: two
/// spaces, `"key": value`, keys in the order given. The register's files keep
/// one format whichever program wrote them.
public indirect enum PrettyJSON: Sendable, Equatable {
    case string(String)
    case int(Int)
    case object([(String, PrettyJSON)])
    case array([PrettyJSON])

    public static func == (a: PrettyJSON, b: PrettyJSON) -> Bool { a.text == b.text }

    /// The text, with one trailing newline.
    public var text: String { render(indent: "") + "\n" }

    func render(indent: String) -> String {
        let inner = indent + "  "
        switch self {
        case .string(let s): return Licence.quote(s)
        case .int(let n): return String(n)
        case .object(let pairs) where pairs.isEmpty: return "{}"
        case .array(let items) where items.isEmpty: return "[]"
        case .object(let pairs):
            let body = pairs.map { "\(inner)\(Licence.quote($0.0)): \($0.1.render(indent: inner))" }.joined(separator: ",\n")
            return "{\n\(body)\n\(indent)}"
        case .array(let items):
            let body = items.map { "\(inner)\($0.render(indent: inner))" }.joined(separator: ",\n")
            return "[\n\(body)\n\(indent)]"
        }
    }
}

extension Licence {
    /// The licence as the register's `record.json` nests it.
    public var prettyJSON: PrettyJSON {
        .object([
            ("licence_id", .string(id.uuidString.lowercased())), ("licensee", .string(licensee)),
            ("issued", .string(issued.description)), ("not_before", .string(notBefore.description)),
            ("not_after", .string(notAfter.description)), ("use", .string(use.rawValue)),
        ])
    }
}
