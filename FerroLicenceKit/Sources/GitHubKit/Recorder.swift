public import Foundation
public import Register

/// Where recording a change has got to.
public enum RecordingStep: Sendable, Equatable {
    case opening
    case opened(number: Int, url: URL)
    case merged(number: Int, url: URL, commit: String)
}

extension GitHub {
    /// Record `change`: a branch from `main`, one commit, a pull request, a
    /// squash merge, the branch deleted. The app has run the Register check
    /// on it first (`RegisterCheck.check`).
    public func record(
        _ change: Change, progress: @Sendable (RecordingStep) -> Void
    ) async throws -> (number: Int, url: URL, commit: String) {
        progress(.opening)
        let base = try await branchHead("main")
        struct Commit: Decodable { struct T: Decodable { let sha: String }; let tree: T }
        let baseCommit: Commit = try await json("GET", "\(config.repoPath)/git/commits/\(base)")

        struct NewBlob: Encodable { let content: String; let encoding = "base64" }
        struct Sha: Decodable { let sha: String }
        struct Entry: Encodable {
            let path: String; let mode = "100644"; let type = "blob"; let sha: String?
            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: K.self)
                try c.encode(path, forKey: .path)
                try c.encode(mode, forKey: .mode)
                try c.encode(type, forKey: .type)
                try c.encode(sha, forKey: .sha)  // null removes the file
            }
            enum K: String, CodingKey { case path, mode, type, sha }
        }
        var entries: [Entry] = []
        for (path, data) in change.writes.sorted(by: { $0.key < $1.key }) {
            let blob: Sha = try await json("POST", "\(config.repoPath)/git/blobs", body: NewBlob(content: data.base64EncodedString()))
            entries.append(Entry(path: path, sha: blob.sha))
        }
        for path in change.deletes { entries.append(Entry(path: path, sha: nil)) }
        struct NewTree: Encodable { let baseTree: String; let tree: [Entry] }
        let tree: Sha = try await json("POST", "\(config.repoPath)/git/trees", body: NewTree(baseTree: baseCommit.tree.sha, tree: entries))
        struct NewCommit: Encodable { let message: String; let tree: String; let parents: [String] }
        let commit: Sha = try await json(
            "POST", "\(config.repoPath)/git/commits",
            body: NewCommit(message: change.title, tree: tree.sha, parents: [base]))
        struct NewRef: Encodable { let ref: String; let sha: String }
        _ = try await call("POST", "\(config.repoPath)/git/refs", body: NewRef(ref: "refs/heads/\(change.branch)", sha: commit.sha))

        struct NewPR: Encodable { let title: String; let head: String; let base = "main"; let body: String }
        struct PR: Decodable { let number: Int; let htmlUrl: URL }
        let pr: PR = try await json(
            "POST", "\(config.repoPath)/pulls", body: NewPR(title: change.title, head: change.branch, body: change.body))
        struct Labels: Encodable { let labels: [String] }
        _ = try? await call("POST", "\(config.repoPath)/issues/\(pr.number)/labels", body: Labels(labels: [change.kind.rawValue]))
        progress(.opened(number: pr.number, url: pr.htmlUrl))

        struct Merge: Encodable { let mergeMethod = "squash"; let commitTitle: String; let sha: String }
        let merged: Sha = try await json(
            "PUT", "\(config.repoPath)/pulls/\(pr.number)/merge",
            body: Merge(commitTitle: "\(change.title) (#\(pr.number))", sha: commit.sha))
        _ = try? await call("DELETE", "\(config.repoPath)/git/refs/heads/\(change.branch)")
        progress(.merged(number: pr.number, url: pr.htmlUrl, commit: merged.sha))
        return (pr.number, pr.htmlUrl, merged.sha)
    }
}

/// A release on GitHub, for the updater.
public struct Release: Sendable, Equatable, Decodable {
    public struct Asset: Sendable, Equatable, Decodable {
        public let name: String
        /// The API address; downloading it needs the token and `Accept: application/octet-stream`.
        public let url: URL
        public let size: Int
    }
    public let tagName: String
    public let prerelease: Bool
    public let draft: Bool
    public let body: String?
    public let assets: [Asset]
}

extension GitHub {
    /// The newest published release, pre-releases included when asked.
    public func latestRelease(includingPrereleases: Bool) async throws -> Release? {
        let all: [Release] = try await json("GET", "\(config.releasesPath)/releases", query: [URLQueryItem(name: "per_page", value: "20")])
        return all.first { !$0.draft && (includingPrereleases || !$0.prerelease) }
    }

    /// The bytes of a release asset, through the API with the token. GitHub
    /// answers with a redirect to its storage host; the token is not sent there.
    public func download(_ asset: Release.Asset) async throws -> Data {
        var request = URLRequest(url: asset.url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(try await credentials.accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request, delegate: TokenStaysWithGitHub()) } catch { throw GitHubError.offline }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubError.status((response as? HTTPURLResponse)?.statusCode ?? 0, "release asset \(asset.name)")
        }
        return data
    }
}

extension GitHub {
    /// Where GitHub's storage serves an asset: a signed https link that
    /// needs no token and lasts about half an hour.
    ///
    /// Sparkle fetches the feed and the update from such links, so it never
    /// holds the token; a `HEAD` request finds the link without downloading
    /// the file, and the token is dropped at the redirect as for `download`.
    public func storageURL(_ asset: Release.Asset) async throws -> URL {
        var request = URLRequest(url: asset.url)
        request.httpMethod = "HEAD"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(try await credentials.accessToken())", forHTTPHeaderField: "Authorization")
        let response: URLResponse
        do { (_, response) = try await session.data(for: request, delegate: TokenStaysWithGitHub()) } catch { throw GitHubError.offline }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, let url = http.url, url.scheme == "https",
            url.host() != asset.url.host()
        else {
            throw GitHubError.status((response as? HTTPURLResponse)?.statusCode ?? 0, "release asset \(asset.name)")
        }
        return url
    }
}

/// Drops the `Authorization` header when a redirect leaves the host that
/// was asked, so a GitHub token never reaches a storage server.
final class TokenStaysWithGitHub: NSObject, URLSessionTaskDelegate, Sendable {
    @concurrent func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard request.url?.host() != task.originalRequest?.url?.host() else { return request }
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Authorization")
        return stripped
    }
}
