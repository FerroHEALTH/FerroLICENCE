public import Foundation
public import LicenceCore

/// The rules a pull request must keep before it reaches `main`: the register
/// is append-only, every new licence passes FerroEHR's checks under the keys
/// `main` already trusts, and keys change only in the ways the app makes.
/// The app runs this as the Register check before it opens a pull request;
/// the register's repository runs no CI (owner, 2026-10-24).
public enum RegisterCheck {
    /// What the pull request does, for the summary.
    public enum Finding: Sendable, Equatable {
        case licence(folder: String, licensee: String, notAfter: CivilDate, signer: String)
        case revocation(folder: String, effective: CivilDate)
        case trusted(fingerprint: String)
        case statusChanged(fingerprint: String, to: KeyStatus)
        case githubLogin(fingerprint: String, login: String)
    }

    public struct Outcome: Sendable, Equatable {
        public var findings: [Finding] = []
        public var problems: [String] = []
        public var passed: Bool { problems.isEmpty }
    }

    /// Compare `head` with `base`. Paths outside the register, the keys and
    /// `signers.json` are not looked at.
    public static func run(base: Snapshot, head: Snapshot) -> Outcome {
        var out = Outcome()
        let baseKeys: Keys
        let headKeys: Keys
        let baseRegister: LicenceRegister
        let headRegister: LicenceRegister
        do {
            baseKeys = try Keys(base)
            baseRegister = try LicenceRegister(base)
        } catch {
            out.problems.append("main itself does not read: \(error)")
            return out
        }
        do {
            headKeys = try Keys(head)
            headRegister = try LicenceRegister(head)
        } catch {
            out.problems.append("\(error)")
            return out
        }

        let removed = Set(base.files.keys).subtracting(head.files.keys)
        let added = Set(head.files.keys).subtracting(base.files.keys)
        let changed = Set(base.files.keys).intersection(head.files.keys).filter { base.files[$0] != head.files[$0] }

        // Keys: what may move, be added or have its row changed.
        var allowedRemoved: Set<String> = []
        var allowedAdded: Set<String> = []
        var allowedChanged: Set<String> = []
        if changed.contains("signers.json") || added.contains("signers.json") {
            allowedChanged.insert("signers.json")
            allowedAdded.insert("signers.json")
            checkSigners(
                base: baseKeys, head: headKeys, added: added, removed: removed, out: &out,
                allowedAdded: &allowedAdded, allowedRemoved: &allowedRemoved)
        }

        // Licences and revocations: new files in new places only.
        var newFolders: [String: Set<String>] = [:]
        for path in added where path.hasPrefix("register/") {
            let parts = path.split(separator: "/")
            guard parts.count == 4 else {
                out.problems.append("\(path) is not register/<customer>/<licence-id>/<file>")
                continue
            }
            newFolders[parts.dropLast().joined(separator: "/"), default: []].insert(String(parts[3]))
        }
        for (folder, names) in newFolders.sorted(by: { $0.key < $1.key }) {
            let existed = baseRegister.entries.first { $0.folder == folder }
            if let entry = existed {
                if names == ["revocation.json"] {
                    allowedAdded.insert("\(folder)/revocation.json")
                    checkRevocation(entry: entry, head: headRegister, out: &out)
                } else {
                    out.problems.append("\(folder) already exists; only a revocation.json may be added to it")
                }
            } else if names == ["licence.asc", "record.json"] {
                allowedAdded.formUnion(["\(folder)/licence.asc", "\(folder)/record.json"])
                checkLicence(folder: folder, head: head, keys: baseKeys, base: baseRegister, out: &out)
            } else {
                out.problems.append("\(folder) must hold licence.asc and record.json, and nothing else")
            }
        }

        for p in removed.subtracting(allowedRemoved).sorted() { out.problems.append("\(p) was removed; the register is append-only") }
        for p in changed.subtracting(allowedChanged).sorted() { out.problems.append("\(p) was changed; the register is append-only") }
        for p in added.subtracting(allowedAdded).sorted() where !p.hasPrefix("register/") {
            out.problems.append("\(p) was added, but no signers.json row says why")
        }
        out.problems.append(contentsOf: headKeys.problems)
        if headKeys.trusted.isEmpty { out.problems.append("no key is trusted any more") }
        return out
    }

    static func checkLicence(folder: String, head: Snapshot, keys: Keys, base: LicenceRegister, out: inout Outcome) {
        guard let text = head.text("\(folder)/licence.asc"), let recordData = head.files["\(folder)/record.json"] else { return }
        let record: Record
        do { record = try Record(json: recordData, path: "\(folder)/record.json") } catch {
            out.problems.append("\(error)")
            return
        }
        let token: Token
        do { token = try Token(text) } catch {
            out.problems.append("\(folder)/licence.asc is not a licence file")
            return
        }
        let verified: Verified
        do { verified = try verify(token, anchors: keys.certificates, on: record.licence.notBefore) } catch {
            out.problems.append(
                "\(folder)/licence.asc fails FerroEHR's checks under the keys main trusts: \(String(localized: Check(error).title).lowercased())"
            )
            return
        }
        let l = verified.licence
        if l != record.licence { out.problems.append("\(folder)/record.json describes a different licence than the file") }
        if record.signer.caseInsensitiveCompare(verified.signer) != .orderedSame {
            out.problems.append("\(folder)/record.json names \(short(record.signer)) as signer, the file says \(short(verified.signer))")
        }
        if record.tokenSHA256 != sha256Hex(Data(text.utf8)) { out.problems.append("\(folder)/record.json has the wrong token_sha256") }
        if folder != "register/\(slug(l.licensee))/\(l.id.uuidString.lowercased())" {
            out.problems.append("\(folder) should be register/\(slug(l.licensee))/\(l.id.uuidString.lowercased())")
        }
        if base.entry(l.id) != nil { out.problems.append("licence id \(l.id.uuidString.lowercased()) is already in the register") }
        if let renews = record.renews, base.entry(renews) == nil {
            out.problems.append("\(folder) renews \(renews.uuidString.lowercased()), which is not in the register")
        }
        if let status = keys.signer(verified.signer)?.status, status.stoppedSigning {
            out.problems.append("\(folder) is signed by \(short(verified.signer)), which is marked \(status.rawValue)")
        }
        out.findings.append(.licence(folder: folder, licensee: l.licensee, notAfter: l.notAfter, signer: verified.signer))
    }

    static func checkRevocation(entry: Entry, head: LicenceRegister, out: inout Outcome) {
        guard let r = head.entry(entry.id)?.revocation else {
            out.problems.append("\(entry.folder)/revocation.json does not read")
            return
        }
        if r.licenceID != entry.id { out.problems.append("\(entry.folder)/revocation.json names another licence") }
        if r.effective < entry.licence.notBefore || r.effective > entry.licence.notAfter {
            out.problems.append("\(entry.folder)/revocation.json takes effect outside the licence's days")
        }
        if r.reason.trimmingCharacters(in: .whitespaces).isEmpty { out.problems.append("\(entry.folder)/revocation.json gives no reason") }
        out.findings.append(.revocation(folder: entry.folder, effective: r.effective))
    }

    /// Who may open the pull request, by the GitHub accounts `main` records
    /// in `signers.json` (owners, 2026-10-24): a new licence only the account
    /// of the holder whose key signed it; a revocation and every key change
    /// the account of an active key holder; a GitHub login given to a key
    /// only that login itself. `author` is the pull request's author.
    public static func authorProblems(_ author: String, base: Snapshot, outcome: Outcome) -> [String] {
        guard let keys = try? Keys(base) else { return ["main itself does not read"] }
        func same(_ a: String?, _ b: String) -> Bool { a?.caseInsensitiveCompare(b) == .orderedSame }
        let holder = keys.signers.contains { $0.status == .active && same($0.github, author) }
        var problems: [String] = []
        for finding in outcome.findings {
            let problem: String? =
                switch finding {
                case .licence(let folder, _, _, let signer):
                    same(keys.signer(signer)?.github, author)
                        ? nil
                        : "\(folder) is signed with \(keys.holder(signer))'s key, so only \(keys.holder(signer))'s GitHub account may record it, not `\(author)`"
                case .revocation(let folder, _):
                    holder ? nil : "\(folder) may be revoked only by an active key holder's GitHub account, not `\(author)`"
                case .trusted, .statusChanged:
                    holder ? nil : "the keys may be changed only by an active key holder's GitHub account, not `\(author)`"
                case .githubLogin(let fpr, let login):
                    same(login, author) ? nil : "only `\(login)` may give \(short(fpr)) the GitHub login `\(login)`, not `\(author)`"
                }
            if let problem, !problems.contains(problem) { problems.append(problem) }
        }
        return problems
    }

    /// Rows are never removed; a new row comes with its certificate; an
    /// existing row changes its status only (`active` to `lost` or `retired`,
    /// `lost` to `retired`), and a retired key moves to `keys/retired/`.
    static func checkSigners(
        base: Keys, head: Keys, added: Set<String>, removed: Set<String>, out: inout Outcome,
        allowedAdded: inout Set<String>, allowedRemoved: inout Set<String>
    ) {
        for old in base.signers where head.signer(old.fingerprint) == nil {
            out.problems.append("signers.json lost the row for \(short(old.fingerprint))")
        }
        for row in head.signers {
            let fpr = row.fingerprint.uppercased()
            guard let old = base.signer(fpr) else {
                let path = "keys/\(fpr).asc"
                guard added.contains(path), head.isTrusted(fpr) else {
                    out.problems.append("signers.json adds \(short(fpr)) without adding \(path)")
                    continue
                }
                if row.status != .active { out.problems.append("a new key is recorded as \(row.status.rawValue)") }
                if head.trusted.first(where: { $0.path == path })?.fingerprint != fpr {
                    out.problems.append("\(path) holds a different key than its name says")
                }
                allowedAdded.insert(path)
                out.findings.append(.trusted(fingerprint: fpr))
                continue
            }
            var same = row
            same.status = old.status
            same.since = old.since
            // A GitHub login may be given once, to a row that has none.
            if old.github == nil, row.github != nil { same.github = nil }
            if same != old { out.problems.append("signers.json changes more than the status of \(short(fpr))") }
            if old.github == nil, let login = row.github {
                if login.isEmpty || login.contains(where: { !($0.isLetter || $0.isNumber || $0 == "-") }) {
                    out.problems.append("signers.json gives \(short(fpr)) the GitHub login \"\(login)\", which is not a login")
                }
                out.findings.append(.githubLogin(fingerprint: fpr, login: login))
            }
            guard row.status != old.status else { continue }
            let allowed: Set<KeyStatus> =
                switch old.status {
                case .active: [.lost, .handedOver, .retired]
                case .lost, .handedOver: [.retired]
                case .retired: []
                }
            guard allowed.contains(row.status), row.since != nil else {
                out.problems.append("\(short(fpr)) may not go from \(old.status.rawValue) to \(row.status.rawValue)")
                continue
            }
            if row.status == .retired, let anchor = base.trusted.first(where: { $0.fingerprint == fpr }) {
                let to = "keys/retired/\(fpr).asc"
                if removed.contains(anchor.path), added.contains(to),
                    head.retired.first(where: { $0.path == to })?.armored == anchor.armored
                {
                    allowedRemoved.insert(anchor.path)
                    allowedAdded.insert(to)
                } else {
                    out.problems.append("a retired key moves from \(anchor.path) to \(to) unchanged")
                }
            }
            out.findings.append(.statusChanged(fingerprint: fpr, to: row.status))
        }
    }
}

extension RegisterCheck.Outcome {
    /// The outcome as Markdown, for the job summary on GitHub.
    public func summary(keys: Keys) -> String {
        var lines: [String] = []
        if findings.isEmpty, problems.isEmpty { lines.append("No change to the register or the keys.") }
        for f in findings {
            switch f {
            case .licence(let folder, let who, let end, _): lines.append("- New licence for **\(who)** until \(end): `\(folder)`")
            case .revocation(let folder, let from): lines.append("- Revocation from \(from): `\(folder)`")
            case .trusted(let fpr): lines.append("- Trusts a new key: `\(grouped(fpr))`")
            case .statusChanged(let fpr, let to):
                lines.append("- \(keys.holder(fpr))'s key is now \(String(localized: to.label).lowercased()): `\(short(fpr))`")
            case .githubLogin(let fpr, let login):
                lines.append("- \(keys.holder(fpr)) signs in as GitHub `\(login)`: `\(short(fpr))`")
            }
        }
        if !problems.isEmpty {
            lines.append("")
            lines.append("**Refused:**")
            lines.append(contentsOf: problems.map { "- \($0)" })
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

extension RegisterCheck {
    /// Why the Register check refused a change; nothing was recorded.
    public struct Refused: Error, Equatable, Sendable {
        public let problems: [String]

        public var message: LocalizedStringResource {
            LocalizedStringResource(
                "The Register check refuses it: \(problems.joined(separator: "; ")). Nothing was recorded.", bundle: #bundle)
        }
    }

    /// The Register check as the app runs it: `change` on top of `base`,
    /// recorded by the GitHub account `login`. Throws when a rule is broken.
    public static func check(_ change: Change, on base: Snapshot, by login: String) throws(Refused) {
        let outcome = run(base: base, head: base.applying(change))
        let problems = outcome.problems + authorProblems(login, base: base, outcome: outcome)
        if !problems.isEmpty { throw Refused(problems: problems) }
    }
}
