import Foundation
import Synchronization

@testable import GitHubKit

/// A fake github.com and api.github.com. Each test makes its own, so tests
/// run in parallel; requests reach it through a header on its session.
final class MockGitHub: Sendable {
    struct Request: Sendable {
        let method: String
        let path: String
        let query: [String: String]
        let headers: [String: String]
        let body: Data

        var json: [String: any Sendable] {
            (try? JSONSerialization.jsonObject(with: body) as? [String: any Sendable]) ?? [:]
        }

        var form: [String: String] {
            var c = URLComponents()
            c.percentEncodedQuery = String(decoding: body, as: UTF8.self)
            return Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        }
    }

    struct Reply: Sendable {
        var status = 200
        var body: Data
        var headers: [String: String] = [:]
        /// Answer with a 302 to this address instead.
        var redirect: URL?

        static func redirect(to url: URL) -> Reply {
            Reply(status: 302, body: Data(), headers: ["Location": url.absoluteString], redirect: url)
        }

        static func json(_ text: String, status: Int = 200, headers: [String: String] = [:]) -> Reply {
            Reply(status: status, body: Data(text.utf8), headers: headers)
        }
    }

    typealias Route = @Sendable (Request) -> Reply?

    let id = UUID().uuidString
    let routes = Mutex<[Route]>([])
    let log = Mutex<[Request]>([])

    init() { MockProtocol.servers.withLock { $0[id] = self } }

    deinit { MockProtocol.servers.withLock { $0[id] = nil } }

    /// Answer requests for `method path` with `reply`, newest route first.
    func on(_ method: String, _ path: String, _ reply: @escaping @Sendable (Request) -> Reply) {
        routes.withLock { $0.insert({ $0.method == method && $0.path == path ? reply($0) : nil }, at: 0) }
    }

    func on(_ method: String, _ path: String, json: String, status: Int = 200) {
        on(method, path) { _ in .json(json, status: status) }
    }

    var requests: [Request] { log.withLock { $0 } }

    func requests(_ method: String, _ path: String) -> [Request] { requests.filter { $0.method == method && $0.path == path } }

    var session: URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [MockProtocol.self]
        c.httpAdditionalHeaders = ["X-Mock": id]
        return URLSession(configuration: c)
    }

    let config = GitHubConfig(
        clientID: "Iv1.test", api: URL(string: "https://api.example.test")!, web: URL(string: "https://web.example.test")!)

    func flow() -> DeviceFlow {
        var f = DeviceFlow(config: config, session: session)
        f.second = .milliseconds(1)
        return f
    }

    func github(tokens: Tokens = Tokens(access: "ghu_test", accessExpires: .distantFuture)) async -> GitHub {
        let store = MemoryTokenStore()
        store.save(tokens)
        return GitHub(config: config, credentials: Credentials(flow: flow(), store: store), session: session)
    }

    func answer(_ request: Request) -> Reply {
        log.withLock { $0.append(request) }
        for route in routes.withLock({ $0 }) {
            if let reply = route(request) { return reply }
        }
        return .json(#"{"message":"Not Found"}"#, status: 404)
    }
}

final class MemoryTokenStore: TokenStorage {
    let tokens = Mutex<Tokens?>(nil)
    func load() -> Tokens? { tokens.withLock { $0 } }
    func save(_ t: Tokens) { tokens.withLock { $0 = t } }
    func delete() { tokens.withLock { $0 = nil } }
}

final class MockProtocol: URLProtocol, @unchecked Sendable {
    static let servers = Mutex<[String: MockGitHub]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Mock") ?? ""
        guard let server = Self.servers.withLock({ $0[id] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary((components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
        let reply = server.answer(
            .init(
                method: request.httpMethod ?? "GET", path: url.path(), query: query,
                headers: request.allHTTPHeaderFields ?? [:], body: body))
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        if let target = reply.redirect {
            var next = request
            next.url = target
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
