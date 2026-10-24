public import Foundation

/// Why a GitHub call failed.
public enum GitHubError: Error, Equatable, Sendable, CustomStringConvertible {
    case status(Int, String)
    case offline

    public var message: LocalizedStringResource {
        switch self {
        case .status(let code, let message): LocalizedStringResource("GitHub answered \(code): \(message)", bundle: #bundle)
        case .offline: LocalizedStringResource("No connection to GitHub.", bundle: #bundle)
        }
    }

    public var description: String { String(localized: message) }
}

/// The REST API calls the app makes, on one repository, as the signed-in person.
public struct GitHub: Sendable {
    public let config: GitHubConfig
    let credentials: Credentials
    let session: URLSession

    public init(config: GitHubConfig, credentials: Credentials, session: URLSession = .shared) {
        self.config = config
        self.credentials = credentials
        self.session = session
    }

    struct Response: Sendable {
        let data: Data
        let status: Int
        let etag: String?
    }

    func call(
        _ method: String, _ path: String, body: (any Encodable & Sendable)? = nil, etag: String? = nil,
        query: [URLQueryItem] = []
    ) async throws -> Response {
        var url = config.api.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(try await credentials.accessToken())", forHTTPHeaderField: "Authorization")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let body {
            request.httpBody = try JSONEncoder.github.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) } catch { throw GitHubError.offline }
        let http = response as! HTTPURLResponse
        guard (200..<300).contains(http.statusCode) || http.statusCode == 304 else {
            let message = (try? JSONDecoder.github.decode([String: String?].self, from: data))?["message"] ?? nil
            throw GitHubError.status(http.statusCode, message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
        return Response(data: data, status: http.statusCode, etag: http.value(forHTTPHeaderField: "ETag"))
    }

    func json<T: Decodable>(
        _ method: String, _ path: String, body: (any Encodable & Sendable)? = nil, query: [URLQueryItem] = []
    ) async throws -> T {
        try JSONDecoder.github.decode(T.self, from: try await call(method, path, body: body, query: query).data)
    }

    // MARK: Who

    public struct User: Decodable, Sendable { public let login: String; public let name: String? }

    public func user() async throws -> User { try await json("GET", "/user") }

    /// Whether the signed-in person may push to the repository.
    public func canPush() async throws -> Bool {
        struct R: Decodable { struct P: Decodable { let push: Bool }; let permissions: P? }
        let r: R = try await json("GET", config.repoPath)
        return r.permissions?.push ?? false
    }
}

extension JSONDecoder {
    static var github: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
}

extension JSONEncoder {
    static var github: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }
}
