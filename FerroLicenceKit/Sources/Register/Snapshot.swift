public import Foundation

/// The repository's files that matter, by path: `keys/`, `signers.json` and
/// `register/`. Read from GitHub, from the offline copy, or from a folder; the
/// rest of the module never touches a disk or a network.
public struct Snapshot: Sendable, Equatable, Codable {
    /// File contents by repository path, such as `register/acme/<id>/record.json`.
    public var files: [String: Data]
    /// The commit the files were read at, when known.
    public var commit: String?

    public init(files: [String: Data] = [:], commit: String? = nil) {
        self.files = files
        self.commit = commit
    }

    /// Whether `path` is one of the files a snapshot keeps.
    public static func keeps(_ path: String) -> Bool {
        path == "signers.json" || (path.hasPrefix("keys/") && path.hasSuffix(".asc"))
            || (path.hasPrefix("register/") && (path.hasSuffix(".json") || path.hasSuffix(".asc")))
    }

    /// Read the kept files from a folder, as the Register check and the tests do.
    public static func read(folder: URL) throws -> Snapshot {
        var files: [String: Data] = [:]
        let base = folder.standardizedFileURL.path
        for sub in ["keys", "register"] {
            guard
                let walk = FileManager.default.enumerator(at: folder.appending(path: sub), includingPropertiesForKeys: [.isRegularFileKey])
            else { continue }
            for case let url as URL in walk {
                let path = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
                if keeps(path), let data = try? Data(contentsOf: url) { files[path] = data }
            }
        }
        if let signers = try? Data(contentsOf: folder.appending(path: "signers.json")) { files["signers.json"] = signers }
        return Snapshot(files: files)
    }

    /// The file at `path` as UTF-8 text.
    public func text(_ path: String) -> String? { files[path].flatMap { String(data: $0, encoding: .utf8) } }

    /// Every path under `prefix`, sorted.
    public func paths(under prefix: String) -> [String] { files.keys.filter { $0.hasPrefix(prefix) }.sorted() }

    /// This snapshot with `change`'s files written and removed.
    public func applying(_ change: Change) -> Snapshot {
        var copy = self
        for (path, data) in change.writes { copy.files[path] = data }
        for path in change.deletes { copy.files[path] = nil }
        return copy
    }
}

/// What one pull request adds to the repository.
public struct Change: Sendable, Equatable {
    public enum Kind: String, Sendable { case licence, revocation, key }

    public let kind: Kind
    /// Files to add or replace, by path.
    public var writes: [String: Data]
    /// Files to remove (a retired key's old place).
    public var deletes: [String]
    /// The branch, `licence/<customer>-<first-day>` and the like.
    public let branch: String
    /// The pull request's title, also the squash commit's.
    public let title: String
    /// The pull request's description, written so the change reads at a glance.
    public let body: String

    public init(kind: Kind, writes: [String: Data], deletes: [String] = [], branch: String, title: String, body: String) {
        self.kind = kind
        self.writes = writes
        self.deletes = deletes
        self.branch = branch
        self.title = title
        self.body = body
    }
}
