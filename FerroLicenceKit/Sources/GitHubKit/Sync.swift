public import Foundation
public import Register

/// Where the app keeps file contents it has already downloaded, by git blob
/// hash, so an unchanged file is never fetched twice. The app backs this
/// with SwiftData; the tests with a dictionary.
public protocol BlobCache: Sendable {
    func blob(_ sha: String) async -> Data?
    func store(_ data: Data, sha: String) async
}

/// The result of one sync.
public struct SyncResult: Sendable, Equatable {
    /// `nil` when nothing changed since `etag`.
    public let snapshot: Snapshot?
    public let etag: String?
    public let commit: String

    public init(snapshot: Snapshot?, etag: String?, commit: String) {
        self.snapshot = snapshot
        self.etag = etag
        self.commit = commit
    }
}

extension GitHub {
    struct Tree: Decodable {
        struct Item: Decodable { let path: String; let type: String; let sha: String }
        let sha: String
        let tree: [Item]
        let truncated: Bool
    }

    /// The register as `main` holds it. With the last `etag`, an unchanged
    /// register costs one "not modified" answer, which GitHub does not count
    /// against the rate limit; only blobs the cache lacks are downloaded.
    public func sync(etag: String?, cache: any BlobCache, branch: String = "main") async throws -> SyncResult {
        let commit = try await branchHead(branch)
        let r = try await call(
            "GET", "\(config.repoPath)/git/trees/\(commit)", etag: etag, query: [URLQueryItem(name: "recursive", value: "1")])
        if r.status == 304 { return SyncResult(snapshot: nil, etag: etag, commit: commit) }
        let tree = try JSONDecoder.github.decode(Tree.self, from: r.data)
        let wanted = tree.tree.filter { $0.type == "blob" && Snapshot.keeps($0.path) }
        let files = try await withThrowingTaskGroup(of: (String, Data).self) { group in
            for item in wanted {
                group.addTask {
                    if let cached = await cache.blob(item.sha) { return (item.path, cached) }
                    let data = try await blob(item.sha)
                    await cache.store(data, sha: item.sha)
                    return (item.path, data)
                }
            }
            var out: [String: Data] = [:]
            for try await (path, data) in group { out[path] = data }
            return out
        }
        return SyncResult(snapshot: Snapshot(files: files, commit: commit), etag: r.etag, commit: commit)
    }

    public func branchHead(_ branch: String) async throws -> String {
        struct R: Decodable { struct O: Decodable { let sha: String }; let object: O }
        let r: R = try await json("GET", "\(config.repoPath)/git/ref/heads/\(branch)")
        return r.object.sha
    }

    func blob(_ sha: String) async throws -> Data {
        struct R: Decodable { let content: String; let encoding: String }
        let r: R = try await json("GET", "\(config.repoPath)/git/blobs/\(sha)")
        guard r.encoding == "base64", let data = Data(base64Encoded: r.content, options: .ignoreUnknownCharacters) else {
            throw GitHubError.status(200, "blob \(sha) is not base64")
        }
        return data
    }
}

/// A merged pull request, for Activity.
public struct Merged: Sendable, Equatable, Identifiable, Decodable {
    public let number: Int
    public let title: String
    public let mergedAt: Date
    public let author: String
    public let labels: [String]
    public let url: URL
    /// The branch it came from: `licence/<customer>-<first-day>-<id prefix>` and the like.
    public let branch: String
    public var id: Int { number }

    public init(number: Int, title: String, mergedAt: Date, author: String, labels: [String], url: URL, branch: String) {
        self.number = number
        self.title = title
        self.mergedAt = mergedAt
        self.author = author
        self.labels = labels
        self.url = url
        self.branch = branch
    }

    /// Whether this pull request recorded the licence `id`, or its revocation.
    public func records(_ id: UUID) -> Bool { branch.hasSuffix("-" + id.uuidString.prefix(8).lowercased()) }
}

extension GitHub {
    /// Pull requests the app made, merged, newest first.
    public func activity(limit: Int = 100) async throws -> [Merged] {
        struct R: Decodable {
            struct U: Decodable { let login: String }
            struct L: Decodable { let name: String }
            struct H: Decodable { let ref: String }
            let number: Int; let title: String; let mergedAt: Date?; let user: U; let labels: [L]; let htmlUrl: URL; let head: H
        }
        let rs: [R] = try await json(
            "GET", "\(config.repoPath)/pulls",
            query: [
                URLQueryItem(name: "state", value: "closed"), URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "direction", value: "desc"), URLQueryItem(name: "per_page", value: String(min(limit, 100))),
            ])
        let kinds: Set = ["licence", "revocation", "key"]
        return rs.compactMap { r in
            guard let at = r.mergedAt, r.labels.contains(where: { kinds.contains($0.name) }) else { return nil }
            return Merged(
                number: r.number, title: r.title, mergedAt: at, author: r.user.login, labels: r.labels.map(\.name), url: r.htmlUrl,
                branch: r.head.ref)
        }
    }
}
