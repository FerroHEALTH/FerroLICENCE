public import Foundation
import Security

/// The repository the app works on, and the GitHub App it signs in through.
public struct GitHubConfig: Sendable, Equatable {
    /// The register's repository, which the app reads and writes.
    public var owner: String
    public var repo: String
    /// Where the app's releases are, as `owner/name`: the public FerroLICENCE
    /// repository, apart from the private register.
    public var releases: String
    /// The FerroLICENCE GitHub App's client id. Public; the device flow
    /// needs no client secret.
    public var clientID: String
    public var api: URL
    public var web: URL

    public init(
        owner: String = "FerroHEALTH", repo: String = "FerroLICENCE-register", releases: String = "FerroHEALTH/FerroLICENCE",
        clientID: String,
        api: URL = URL(string: "https://api.github.com")!, web: URL = URL(string: "https://github.com")!
    ) {
        self.owner = owner
        self.repo = repo
        self.releases = releases
        self.clientID = clientID
        self.api = api
        self.web = web
    }

    public var repoPath: String { "/repos/\(owner)/\(repo)" }
    public var releasesPath: String { "/repos/\(releases)" }
    public var repoURL: URL { web.appending(path: "\(owner)/\(repo)") }
}

/// A user access token and its refresh token, as the GitHub App issues them:
/// the token lasts 8 hours, the refresh token 6 months.
public struct Tokens: Codable, Sendable, Equatable {
    public var access: String
    public var accessExpires: Date
    public var refresh: String?
    public var refreshExpires: Date?

    public init(access: String, accessExpires: Date, refresh: String? = nil, refreshExpires: Date? = nil) {
        self.access = access
        self.accessExpires = accessExpires
        self.refresh = refresh
        self.refreshExpires = refreshExpires
    }

    init(_ r: TokenResponse, now: Date = Date()) {
        access = r.accessToken
        accessExpires = now.addingTimeInterval(TimeInterval(r.expiresIn ?? 8 * 3600))
        refresh = r.refreshToken
        refreshExpires = r.refreshTokenExpiresIn.map { now.addingTimeInterval(TimeInterval($0)) }
    }
}

struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int?
    let refreshToken: String?
    let refreshTokenExpiresIn: Int?
}

/// Why signing in failed.
public enum AuthError: Error, Equatable, Sendable, CustomStringConvertible {
    case expired
    case denied
    case notSignedIn
    case github(String)

    public var message: LocalizedStringResource {
        switch self {
        case .expired: LocalizedStringResource("The code expired. Start again.", bundle: #bundle)
        case .denied: LocalizedStringResource("GitHub said no. Start again and approve FerroLICENCE.", bundle: #bundle)
        case .notSignedIn: LocalizedStringResource("Sign in with GitHub first.", bundle: #bundle)
        case .github(let m): LocalizedStringResource("GitHub answered: \(m)", bundle: #bundle)
        }
    }

    public var description: String { String(localized: message) }
}

/// The code to type on github.com/login/device.
public struct DeviceCode: Sendable, Equatable {
    public let userCode: String
    public let verificationURL: URL
    public let expiresAt: Date
    let deviceCode: String
    let interval: Int

    public init(userCode: String, verificationURL: URL, expiresAt: Date, deviceCode: String, interval: Int) {
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.expiresAt = expiresAt
        self.deviceCode = deviceCode
        self.interval = interval
    }
}

/// GitHub's device flow (RFC 8628) for a GitHub App: show a code, the person
/// enters it on github.com, the app polls until GitHub hands out a token.
public struct DeviceFlow: Sendable {
    let config: GitHubConfig
    let session: URLSession
    /// What one second of GitHub's polling interval lasts; shorter in tests.
    var second: Duration = .seconds(1)

    public init(config: GitHubConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func post<T: Decodable>(_ path: String, _ form: [String: String]) async throws -> T {
        var request = URLRequest(url: config.web.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var c = URLComponents()
        c.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((c.percentEncodedQuery ?? "").utf8)
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder.github.decode(T.self, from: data)
    }

    public func start() async throws -> DeviceCode {
        struct R: Decodable {
            let deviceCode: String; let userCode: String; let verificationUri: String; let expiresIn: Int; let interval: Int
        }
        let r: R = try await post("login/device/code", ["client_id": config.clientID])
        return DeviceCode(
            userCode: r.userCode, verificationURL: URL(string: r.verificationUri)!,
            expiresAt: Date().addingTimeInterval(TimeInterval(r.expiresIn)), deviceCode: r.deviceCode, interval: r.interval)
    }

    /// Poll until GitHub approves, refuses or the code expires.
    public func waitForToken(_ code: DeviceCode) async throws -> Tokens {
        struct R: Decodable {
            let accessToken: String?; let expiresIn: Int?; let refreshToken: String?; let refreshTokenExpiresIn: Int?
            let error: String?; let interval: Int?
        }
        var interval = max(code.interval, 1)
        while Date() < code.expiresAt {
            try await Task.sleep(for: second * interval)
            let r: R = try await post(
                "login/oauth/access_token",
                [
                    "client_id": config.clientID, "device_code": code.deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                ])
            if let token = r.accessToken {
                return Tokens(
                    TokenResponse(
                        accessToken: token, expiresIn: r.expiresIn, refreshToken: r.refreshToken,
                        refreshTokenExpiresIn: r.refreshTokenExpiresIn))
            }
            switch r.error {
            case "authorization_pending": continue
            case "slow_down": interval = (r.interval ?? interval + 5)
            case "expired_token": throw AuthError.expired
            case "access_denied": throw AuthError.denied
            default: throw AuthError.github(r.error ?? "unknown answer from GitHub")
            }
        }
        throw AuthError.expired
    }

    /// A new token from the refresh token; the old pair stops working.
    public func refresh(_ tokens: Tokens) async throws -> Tokens {
        struct R: Decodable {
            let accessToken: String?; let expiresIn: Int?; let refreshToken: String?; let refreshTokenExpiresIn: Int?; let error: String?
        }
        guard let refresh = tokens.refresh else { throw AuthError.notSignedIn }
        let r: R = try await post(
            "login/oauth/access_token", ["client_id": config.clientID, "grant_type": "refresh_token", "refresh_token": refresh])
        guard let token = r.accessToken else { throw AuthError.notSignedIn }
        return Tokens(
            TokenResponse(
                accessToken: token, expiresIn: r.expiresIn, refreshToken: r.refreshToken,
                refreshTokenExpiresIn: r.refreshTokenExpiresIn))
    }
}

/// Where the tokens are kept between launches.
public protocol TokenStorage: Sendable {
    func load() -> Tokens?
    func save(_ tokens: Tokens)
    func delete()
}

/// The tokens in the login Keychain, never in a file.
public struct KeychainTokenStore: TokenStorage {
    let service: String
    let account = "github"

    public init(service: String = "eu.FerroHEALTH.FerroLICENCE") { self.service = service }

    var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func load() -> Tokens? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: data)
    }

    public func save(_ tokens: Tokens) {
        let data = (try? JSONEncoder().encode(tokens)) ?? Data()
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    public func delete() { SecItemDelete(query as CFDictionary) }
}

/// Hands out a valid access token, refreshing it and saving the new pair.
public actor Credentials {
    let flow: DeviceFlow
    let store: any TokenStorage
    var tokens: Tokens?

    public init(flow: DeviceFlow, store: any TokenStorage = KeychainTokenStore()) {
        self.flow = flow
        self.store = store
        tokens = store.load()
    }

    public var isSignedIn: Bool { tokens != nil }

    public func signedIn(_ new: Tokens) {
        tokens = new
        store.save(new)
    }

    public func signOut() {
        tokens = nil
        store.delete()
    }

    public func accessToken() async throws -> String {
        guard let t = tokens else { throw AuthError.notSignedIn }
        if t.accessExpires > Date().addingTimeInterval(120) { return t.access }
        do {
            let fresh = try await flow.refresh(t)
            signedIn(fresh)
            return fresh.access
        } catch {
            signOut()
            throw AuthError.notSignedIn
        }
    }
}
