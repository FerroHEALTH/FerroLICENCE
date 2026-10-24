public import Foundation
public import LicenceCore

// MARK: - Revoke

/// What the licensor fills in to revoke a licence.
public struct RevokeDraft: Sendable, Equatable {
    public var reason: String
    public var effective: CivilDate

    public init(reason: String, effective: CivilDate) {
        self.reason = reason
        self.effective = effective
    }

    /// Why this cannot be recorded for `entry`, in words; `nil` when it can.
    public func problem(for entry: Entry) -> LocalizedStringResource? {
        if entry.revocation != nil { return LocalizedStringResource("This licence is already revoked.", bundle: #bundle) }
        if reason.trimmingCharacters(in: .whitespaces).isEmpty {
            return LocalizedStringResource("Say why, for example the contract clause or the letter.", bundle: #bundle)
        }
        if reason.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return LocalizedStringResource("Remove the tab or line break from the reason.", bundle: #bundle)
        }
        if effective < entry.licence.notBefore {
            return LocalizedStringResource(
                "The licence only starts on \(entry.licence.notBefore); pick that day or later.", bundle: #bundle)
        }
        if effective > entry.licence.notAfter {
            return LocalizedStringResource(
                "The licence already ended on \(entry.licence.notAfter); there is nothing to revoke.", bundle: #bundle)
        }
        return nil
    }

    /// The pull request that records the revocation.
    public func change(for entry: Entry, now: Date = Date()) throws(PreparationError) -> Change {
        if let p = problem(for: entry) { throw PreparationError(message: p) }
        let r = Revocation(licenceID: entry.id, effective: effective, reason: reason.trimmingCharacters(in: .whitespaces), recordedAt: now)
        return Change(
            kind: .revocation, writes: ["\(entry.folder)/revocation.json": r.json],
            branch: "revocation/\(entry.customer)-\(effective)-\(entry.id.uuidString.prefix(8).lowercased())",
            title: "Revoke \(entry.licence.licensee) from \(effective)",
            body: describe(
                [
                    ("Customer", "**\(entry.licence.licensee)**"),
                    ("Licence", "`\(entry.id.uuidString.lowercased())` · \(entry.licence.notBefore) to \(entry.licence.notAfter)"),
                    ("Stops counting from", "**\(effective)**"), ("Reason", r.reason),
                ],
                footer:
                    "Recorded by FerroLICENCE. FerroEHR never sees a revocation; attestation reports identifiers minted on or after this day."
            ))
    }
}

// MARK: - Keys

/// The pull request that trusts a new master key: its public certificate
/// under `keys/` and its holder in `signers.json`.
public func trustChange(
    certificate armored: String, holder: String, medium: String, github: String?, keys: Keys,
    today: CivilDate
) throws(PreparationError) -> Change {
    let name = holder.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else {
        throw PreparationError(message: LocalizedStringResource("Name the person who holds the key.", bundle: #bundle))
    }
    guard armored.contains("-----BEGIN PGP PUBLIC KEY BLOCK-----"), !armored.contains("PRIVATE KEY"),
        let cert = try? Certificate(armored: armored), cert.bindingsVerify()
    else {
        throw PreparationError(
            message: LocalizedStringResource("GnuPG exported something other than a public certificate.", bundle: #bundle))
    }
    let fpr = cert.primary.fingerprintHex
    guard !keys.isTrusted(fpr) else {
        throw PreparationError(message: LocalizedStringResource("\(short(fpr)) is already trusted.", bundle: #bundle))
    }
    var signers = keys.signers.filter { $0.fingerprint.caseInsensitiveCompare(fpr) != .orderedSame }
    signers.append(Signer(fingerprint: fpr, holder: name, medium: medium, added: today, status: .active, github: github))
    return Change(
        kind: .key, writes: ["keys/\(fpr).asc": Data(armored.utf8), "signers.json": Keys.encode(signers)],
        branch: "key/\(fpr.prefix(8).lowercased())", title: "Trust the master key of \(name)",
        body: describe(
            [("Holder", "**\(name)**"), ("Key", "`\(grouped(fpr))`"), ("Where", medium)],
            footer:
                "Created on the YubiKey by GnuPG and exported by FerroLICENCE. FerroEHR trusts it from the first release that embeds this file."
        ))
}

/// A new key on its way to an owner. Set Up a YubiKey writes it on the Mac
/// of someone who holds no key yet; an owner opens it with Trust a New Key…
/// and records it from their own account, because only an active key
/// holder may change the keys (`RegisterCheck.authorProblems`).
public struct KeyRequest: Sendable, Equatable, Codable {
    /// What the file is, so another JSON file is never taken for one.
    public static let format = "ferrolicence-key-request-1"

    public var format: String
    public var holder: String
    public var github: String
    public var medium: String
    public var certificate: String

    public init(holder: String, github: String, medium: String, certificate: String) {
        self.format = Self.format
        self.holder = holder
        self.github = github
        self.medium = medium
        self.certificate = certificate
    }

    /// The file's bytes, keys sorted so the same request is the same file.
    public var json: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data()
    }

    public init(json: Data) throws(PreparationError) {
        guard let request = try? JSONDecoder().decode(Self.self, from: json), request.format == Self.format else {
            throw PreparationError(message: LocalizedStringResource("That file is not a key from Set Up a YubiKey.", bundle: #bundle))
        }
        guard !request.github.isEmpty, request.github.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw PreparationError(message: LocalizedStringResource("The key file gives no GitHub login.", bundle: #bundle))
        }
        self = request
    }

    /// The key's fingerprint, to read out and compare before trusting it.
    public var fingerprint: String? { (try? Certificate(armored: certificate))?.primary.fingerprintHex }

    /// The pull request that trusts the key, from the owner's account.
    public func change(keys: Keys, today: CivilDate) throws(PreparationError) -> Change {
        try trustChange(certificate: certificate, holder: holder, medium: medium, github: github, keys: keys, today: today)
    }
}

/// The pull request that stops a key signing. Lost (the card is gone) and
/// handed over (its holder passed the work to someone with their own key)
/// keep it trusted, so its licences stay valid; retired (someone else may
/// hold it) moves it to `keys/retired/`.
public func stopKeyChange(fingerprint: String, to status: KeyStatus, keys: Keys, today: CivilDate) throws(PreparationError) -> Change {
    let retire = status == .retired
    guard let anchor = keys.trusted.first(where: { $0.fingerprint.caseInsensitiveCompare(fingerprint) == .orderedSame }) else {
        throw PreparationError(message: LocalizedStringResource("\(short(fingerprint)) is not a trusted key.", bundle: #bundle))
    }
    if retire, keys.trusted.count < 2 {
        throw PreparationError(
            message: LocalizedStringResource("This is the last trusted key; set up another YubiKey first.", bundle: #bundle))
    }
    guard let row = keys.signer(fingerprint) else {
        throw PreparationError(message: LocalizedStringResource("signers.json does not name \(short(fingerprint)).", bundle: #bundle))
    }
    // The moves the Register check allows: from in use to any other status,
    // and from lost or handed over to retired.
    guard status != .active, row.status == .active || (row.status.stoppedSigning && retire) else {
        throw PreparationError(
            message: LocalizedStringResource("This key signs nothing new already; it can only be retired.", bundle: #bundle))
    }
    if status == .handedOver,
        !keys.signers.contains(where: { $0.status == .active && $0.fingerprint.caseInsensitiveCompare(fingerprint) != .orderedSame })
    {
        throw PreparationError(
            message: LocalizedStringResource("Trust the successor's key first, so a key stays in use.", bundle: #bundle))
    }
    let signers = keys.signers.map { s -> Signer in
        guard s.fingerprint.caseInsensitiveCompare(fingerprint) == .orderedSame else { return s }
        var s = s
        s.status = status
        s.since = today
        return s
    }
    var writes = ["signers.json": Keys.encode(signers)]
    var deletes: [String] = []
    if retire {
        writes["keys/retired/\(anchor.fingerprint).asc"] = Data(anchor.armored.utf8)
        deletes.append(anchor.path)
    }
    let holder = keys.holder(fingerprint)
    let title =
        switch status {
        case .retired: "Retire the key of \(holder)"
        case .handedOver: "Mark the key of \(holder) as handed over"
        default: "Mark the key of \(holder) as lost"
        }
    return Change(
        kind: .key, writes: writes, deletes: deletes,
        branch: "key/\(status.rawValue)-\(fingerprint.prefix(8).lowercased())",
        title: title,
        body: describe(
            [
                ("Holder", holder), ("Key", "`\(grouped(anchor.fingerprint))`"),
                (
                    "Now",
                    retire
                        ? "retired; FerroEHR stops trusting it from its next release"
                        : "\(status.rawValue); still trusted, its licences keep working, it signs nothing new"
                ),
            ],
            footer: "Recorded by FerroLICENCE."))
}

// MARK: - Check a licence file

/// What the register knows about a licence id.
public enum Known: Sendable, Equatable {
    case ours(customer: String, revocation: Revocation?)
    case notOurs
}

/// The outcome of checking one licence file.
public struct FileCheck: Sendable {
    public let day: CivilDate
    public let outcome: Result<Verified, VerifyError>
    /// What the file says it carries; trustworthy only when `genuine`.
    public let claimed: Licence?
    public let signer: String
    public let known: Known?

    public init(text: String, keys: Keys, register: LicenceRegister, day: CivilDate) throws(Token.Failure) {
        let token = try Token(text)
        self.day = day
        outcome = Result { () throws(VerifyError) in try verify(token, anchors: keys.certificates, on: day) }
        claimed =
            switch outcome {
            case .success(let v): v.licence
            case .failure: try? Licence.parse(token.signedText)
            }
        signer = token.certificate.primary.fingerprintHex
        known = claimed.map { l in register.entry(l.id).map { .ours(customer: $0.customer, revocation: $0.revocation) } ?? .notOurs }
    }

    /// The check that refused the file; `nil` when all passed.
    public var failedAt: Check? { if case .failure(let e) = outcome { Check(e) } else { nil } }

    public var passed: Int { failedAt?.rawValue ?? Check.allCases.count }

    /// Whether the signature is ours and matches the text, so the claimed licence is true.
    public var genuine: Bool { failedAt.map { $0 > .signatureMatches } ?? true }

    /// The verdict in one sentence; a retired key is named as ours.
    public func headline(keys: Keys) -> LocalizedStringResource {
        switch outcome {
        case .success(let v): return LocalizedStringResource("Valid on \(day), until \(v.licence.notAfter).", bundle: #bundle)
        case .failure(let e):
            switch e {
            case .expired(let end):
                return LocalizedStringResource(
                    "Not valid on \(day). It ended on \(end), \(end.days(until: day)) days before.", bundle: #bundle)
            case .notYetValid(let start): return LocalizedStringResource("Not valid yet. It starts on \(start).", bundle: #bundle)
            case .untrustedPrimary(let fpr) where keys.retired.contains(where: { $0.fingerprint == fpr }):
                return LocalizedStringResource(
                    "Signed by a retired key (\(keys.holder(fpr)), \(short(fpr))). FerroEHR no longer trusts it.", bundle: #bundle)
            case .untrustedPrimary:
                return LocalizedStringResource("Not signed by one of our keys. FerroEHR does not trust it.", bundle: #bundle)
            case .badSignature: return LocalizedStringResource("The file was changed after it was signed.", bundle: #bundle)
            default: return LocalizedStringResource("FerroEHR refuses it at the check “\(Check(e).title)”.", bundle: #bundle)
            }
        }
    }

    /// What FerroEHR does with this file.
    public var inFerroEHR: LocalizedStringResource {
        if case .success = outcome {
            LocalizedStringResource("In force; the server reports it.", bundle: #bundle)
        } else {
            LocalizedStringResource("Ignored; the server runs on the free licence.", bundle: #bundle)
        }
    }
}

// MARK: - Attest

/// Run attestation of `text` against the unlicensed constant and every licence.
public func attest(_ text: String, register: LicenceRegister) -> Attest.Report {
    var candidates = [Attest.Candidate(label: "unlicensed", key: .unlicensed, notAfter: nil, revokedFrom: nil)]
    for e in register.entries {
        candidates.append(
            .init(
                label: e.id.uuidString.lowercased(), key: .licence(e.id), notAfter: e.licence.notAfter,
                revokedFrom: e.revocation?.effective))
    }
    return Attest.run(Attest.uuids(in: text), candidates: candidates)
}

/// The p-value at or below which a licence counts as identified.
public let identificationThreshold = 1e-9
