import Foundation
import GitHubKit
import LicenceCore
import Register
import Signing

/// A change recorded on `main`.
struct RecordedChange: Sendable, Equatable {
    let number: Int
    let url: URL
    let commit: String
}

/// The repository on GitHub, as the signed-in person sees it.
protocol RepositoryService: Sendable {
    var repositoryURL: URL { get }
    var isSignedIn: Bool { get async }
    func startSignIn() async throws -> DeviceCode
    func finishSignIn(_ code: DeviceCode) async throws
    func signOut() async
    func whoAmI() async throws -> (login: String, name: String?, canPush: Bool)
    func sync(etag: String?) async throws -> SyncResult
    func activity() async throws -> [Merged]
    func record(_ change: Change, progress: @escaping @Sendable (RecordingStep) -> Void) async throws -> RecordedChange
    func latestRelease(includingPrereleases: Bool) async throws -> Release?
    func download(_ asset: Release.Asset) async throws -> Data
    func storageURL(_ asset: Release.Asset) async throws -> URL
}

/// What is installed for signing: GnuPG and its PIN window.
struct Tools: Sendable, Equatable {
    var gnupgVersion: String?
    var gnupgFolder: String?
    var pinentryMac: Bool
}

/// GnuPG and the YubiKey plugged in.
protocol SigningService: Sendable {
    func tools() async -> Tools
    func card() async -> CardStatus?
    func signingKey(keys: Keys) async throws(NoSigningKey) -> SigningKey
    func sign(_ text: String, with key: SigningKey) async throws(GnuPGError) -> String
    func probe(keys: Keys, pinsChanged: Bool) async -> SetupProbe
    func run(_ step: SetupStep, card: CardStatus?, status: @escaping @Sendable (String) -> Void) async throws(GnuPGError)
    func exportPublic(_ fingerprint: String) async throws(GnuPGError) -> String
}

// MARK: - Live

/// GitHub through the FerroLICENCE GitHub App, with the blob cache on disk.
struct LiveRepository: RepositoryService {
    let config: GitHubConfig
    let flow: DeviceFlow
    let credentials: Credentials
    let github: GitHub
    let cache: any BlobCache

    init(clientID: String, cache: any BlobCache) {
        config = GitHubConfig(
            owner: Launch.repository.owner, repo: Launch.repository.name, releases: Launch.releases, clientID: clientID)
        flow = DeviceFlow(config: config)
        credentials = Credentials(flow: flow)
        github = GitHub(config: config, credentials: credentials)
        self.cache = cache
    }

    var repositoryURL: URL { config.repoURL }
    var isSignedIn: Bool { get async { await credentials.isSignedIn } }

    func startSignIn() async throws -> DeviceCode { try await flow.start() }

    func finishSignIn(_ code: DeviceCode) async throws {
        await credentials.signedIn(try await flow.waitForToken(code))
    }

    func signOut() async { await credentials.signOut() }

    func whoAmI() async throws -> (login: String, name: String?, canPush: Bool) {
        async let user = github.user()
        async let push = github.canPush()
        let u = try await user
        return (u.login, u.name, try await push)
    }

    func sync(etag: String?) async throws -> SyncResult { try await github.sync(etag: etag, cache: cache) }
    func activity() async throws -> [Merged] { try await github.activity() }

    func record(_ change: Change, progress: @escaping @Sendable (RecordingStep) -> Void) async throws -> RecordedChange {
        let r = try await github.record(change, progress: progress)
        return RecordedChange(number: r.number, url: r.url, commit: r.commit)
    }

    func latestRelease(includingPrereleases: Bool) async throws -> Release? {
        try await github.latestRelease(includingPrereleases: includingPrereleases)
    }

    func download(_ asset: Release.Asset) async throws -> Data { try await github.download(asset) }

    func storageURL(_ asset: Release.Asset) async throws -> URL { try await github.storageURL(asset) }
}

/// The installed GnuPG; every key operation goes through it.
struct LiveSigning: SigningService {
    func gpg() -> GnuPG? { GnuPG.find() }

    func tools() async -> Tools {
        guard let gpg = gpg() else { return Tools(pinentryMac: AgentConf.pinentryMac != nil) }
        let version = await gpg.version().map { $0.replacingOccurrences(of: "gpg (GnuPG) ", with: "") }
        return Tools(
            gnupgVersion: version, gnupgFolder: gpg.executable.deletingLastPathComponent().path(), pinentryMac: AgentConf.pinentryMac != nil
        )
    }

    func card() async -> CardStatus? {
        guard let gpg = gpg() else { return nil }
        return (try? await gpg.cardStatus()) ?? nil
    }

    func signingKey(keys: Keys) async throws(NoSigningKey) -> SigningKey {
        guard let gpg = gpg() else { throw .gnupg(.notInstalled) }
        return try await gpg.signingKey(keys: keys)
    }

    func sign(_ text: String, with key: SigningKey) async throws(GnuPGError) -> String {
        guard let gpg = gpg() else { throw .notInstalled }
        return try await gpg.sign(text, with: key)
    }

    func probe(keys: Keys, pinsChanged: Bool) async -> SetupProbe {
        guard let gpg = gpg() else { return SetupProbe(card: nil, agentConfigured: false, trusted: false, pinsChanged: pinsChanged) }
        return await gpg.probe(keys: keys, pinsChanged: pinsChanged)
    }

    func run(_ step: SetupStep, card: CardStatus?, status: @escaping @Sendable (String) -> Void) async throws(GnuPGError) {
        guard let gpg = gpg() else { throw .notInstalled }
        try await gpg.run(step, card: card, status: status)
    }

    func exportPublic(_ fingerprint: String) async throws(GnuPGError) -> String {
        guard let gpg = gpg() else { throw .notInstalled }
        return try await gpg.exportPublic(fingerprint)
    }
}
