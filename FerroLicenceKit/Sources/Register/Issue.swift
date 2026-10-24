public import Foundation
public import LicenceCore

/// What the licensor fills in for a new licence.
public struct Draft: Sendable, Equatable {
    public static let maxLicensee = 200

    public var licensee: String
    public var use: Use
    public var notBefore: CivilDate
    public var notAfter: CivilDate
    /// The licensor's reference to the agreement; stays in the register.
    public var contract: String
    /// The licence this one renews.
    public var renews: UUID?

    public init(licensee: String, use: Use, notBefore: CivilDate, notAfter: CivilDate, contract: String = "", renews: UUID? = nil) {
        self.licensee = licensee
        self.use = use
        self.notBefore = notBefore
        self.notAfter = notAfter
        self.contract = contract
        self.renews = renews
    }

    /// A one-year commercial licence for a new customer, from `today`.
    public static func newCustomer(today: CivilDate) -> Draft {
        Draft(licensee: "", use: .commercial, notBefore: today, notAfter: today.oneYearLater)
    }

    /// A one-year licence for the same customer and use as `entry`, starting
    /// the day after it ends, or today when it already ended. A new start
    /// after a revocation renews nothing.
    public static func renewal(of entry: Entry, today: CivilDate) -> Draft {
        let start = max(entry.licence.notAfter.adding(days: 1), today)
        return Draft(
            licensee: entry.licence.licensee, use: entry.licence.use, notBefore: start,
            notAfter: start.oneYearLater, renews: entry.revocation == nil ? entry.id : nil)
    }

    /// Why this draft cannot be signed, in words; `nil` when it can.
    public var problem: LocalizedStringResource? {
        let name = licensee.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return LocalizedStringResource("Type the customer's legal name, as in the agreement.", bundle: #bundle) }
        if name.count > Self.maxLicensee {
            return LocalizedStringResource("The name is longer than \(Self.maxLicensee) characters.", bundle: #bundle)
        }
        if (name + contract).unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return LocalizedStringResource("Remove the tab or line break from the text.", bundle: #bundle)
        }
        if notAfter < notBefore { return LocalizedStringResource("The last day comes before the first day.", bundle: #bundle) }
        return nil
    }
}

/// A draft with its licence id minted: exactly the document the card signs.
public struct Prepared: Sendable, Equatable {
    public let licence: Licence
    public let contract: String?
    public let renews: UUID?

    /// The bytes the YubiKey signs.
    public var text: String { licence.canonicalJSON }

    public init(_ draft: Draft, today: CivilDate, id: UUID = .v7()) throws(PreparationError) {
        if let p = draft.problem { throw PreparationError(message: p) }
        licence = Licence(
            id: id, licensee: draft.licensee.trimmingCharacters(in: .whitespaces), issued: today,
            notBefore: draft.notBefore, notAfter: draft.notAfter, use: draft.use)
        let c = draft.contract.trimmingCharacters(in: .whitespaces)
        contract = c.isEmpty ? nil : c
        renews = draft.renews
    }
}

public struct PreparationError: Error, Equatable, Sendable {
    public let message: LocalizedStringResource
    public init(message: LocalizedStringResource) { self.message = message }
}

/// Why a signed licence may not be recorded.
public enum RecordingError: Error, Equatable, Sendable, CustomStringConvertible {
    case notALicenceFile
    case refused(VerifyError)
    case different
    case renewsUnknown(UUID)
    case exists(String)

    public var message: LocalizedStringResource {
        switch self {
        case .notALicenceFile: LocalizedStringResource("GnuPG returned something that is not a licence file.", bundle: #bundle)
        case .refused(let e):
            LocalizedStringResource("The signed licence fails FerroEHR's check “\(Check(e).title)”. Nothing was recorded.", bundle: #bundle)
        case .different: LocalizedStringResource("The signed licence differs from the draft. Nothing was recorded.", bundle: #bundle)
        case .renewsUnknown(let id):
            LocalizedStringResource("The licence this renews (\(id.uuidString.lowercased())) is not in the register.", bundle: #bundle)
        case .exists(let p): LocalizedStringResource("\(p) already exists; a licence is recorded once.", bundle: #bundle)
        }
    }

    public var description: String { String(localized: message) }
}

/// Check a freshly signed licence file with the product's checks, as of its
/// first day, against the trusted keys, and turn it into the pull request
/// that records it. A licence that would not pass is never recorded.
public func licenceChange(
    prepared: Prepared, signedFile: String, keys: Keys, register: LicenceRegister,
    now: Date = Date()
) throws(RecordingError) -> (Record, Change) {
    let token: Token
    do { token = try Token(signedFile) } catch { throw .notALicenceFile }
    let verified: Verified
    do { verified = try verify(token, anchors: keys.certificates, on: prepared.licence.notBefore) } catch { throw .refused(error) }
    guard verified.licence == prepared.licence else { throw .different }
    if let renews = prepared.renews, register.entry(renews) == nil { throw .renewsUnknown(renews) }
    let l = prepared.licence
    let folder = "register/\(slug(l.licensee))/\(l.id.uuidString.lowercased())"
    if register.entries.contains(where: { $0.folder == folder }) { throw .exists(folder) }
    let file = Data(signedFile.utf8)
    let record = Record(
        licence: l, signer: verified.signer, tokenSHA256: sha256Hex(file), contract: prepared.contract,
        renews: prepared.renews, recordedAt: now)
    let renewed = prepared.renews.flatMap(register.entry)
    let verb = renewed == nil ? "Licence for" : "Renew"
    let title = "\(verb) \(l.licensee) until \(l.notAfter)"
    var rows: [(String, String)] = [
        ("Customer", "**\(l.licensee)**"),
        ("Valid", "**\(l.notBefore) to \(l.notAfter)** · \(l.notBefore.days(until: l.notAfter) + 1) days"),
        ("Type", l.use.rawValue),
    ]
    if let c = prepared.contract { rows.append(("Contract", c)) }
    if let r = renewed { rows.append(("Renews", "\(r.id.uuidString.lowercased()) · \(r.licence.notBefore) to \(r.licence.notAfter)")) }
    rows.append(("Signed by", keys.holder(verified.signer) + " · `\(short(verified.signer))`"))
    rows.append(("Licence id", "`\(l.id.uuidString.lowercased())`"))
    let change = Change(
        kind: .licence,
        writes: ["\(folder)/licence.asc": file, "\(folder)/record.json": record.json],
        branch: "licence/\(slug(l.licensee))-\(l.notBefore)-\(l.id.uuidString.prefix(8).lowercased())",
        title: title,
        body: describe(
            rows,
            footer: "Signed on a YubiKey and recorded by FerroLICENCE, which ran the Register check on it before opening this pull request."
        ))
    return (record, change)
}

/// A pull request description: a two-column table and one sentence.
func describe(_ rows: [(String, String)], footer: String) -> String {
    let table = rows.map { "| \($0.0) | \($0.1.replacingOccurrences(of: "|", with: "\\|")) |" }.joined(separator: "\n")
    return "| | |\n|---|---|\n\(table)\n\n\(footer)\n"
}

extension UUID {
    /// A version 7 UUID: 48 bits of milliseconds, then random bits.
    public static func v7(now: Date = Date()) -> UUID {
        var bytes = [UInt8](UUID().data)
        let ms = UInt64(now.timeIntervalSince1970 * 1000)
        for i in 0..<6 { bytes[i] = UInt8(ms >> (8 * UInt64(5 - i)) & 0xFF) }
        bytes[6] = 0x70 | (bytes[6] & 0x0F)
        bytes[8] = 0x80 | (bytes[8] & 0x3F)
        return UUID(data: Data(bytes))!
    }
}
