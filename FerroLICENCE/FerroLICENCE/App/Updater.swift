import Foundation
import GitHubKit
import Observation
import Sparkle

/// App updates from FerroLICENCE's GitHub releases. The app reads the
/// release's `appcast.xml` through the API with the GitHub token, then gives
/// Sparkle GitHub's signed storage links to the feed and the `.zip`, which
/// need no token. Sparkle checks the EdDSA signature
/// before it unpacks, then the Developer ID signature, installs and
/// relaunches.
@Observable
final class Updater: NSObject, SPUUpdaterDelegate {
    struct Available: Equatable {
        let version: String
        let build: Int
    }

    @ObservationIgnored let repository: any RepositoryService
    @ObservationIgnored let enabled: Bool
    @ObservationIgnored var controller: SPUStandardUpdaterController?
    @ObservationIgnored var feedLink: URL?
    @ObservationIgnored var updateLink: URL?

    var available: Available?
    var lastChecked: Date?
    var checking = false
    var problem: LocalizedStringResource?

    var checkAutomatically: Bool {
        get { access(keyPath: \.checkAutomatically); return UserDefaults.standard.object(forKey: "updates.check") as? Bool ?? true }
        set { withMutation(keyPath: \.checkAutomatically) { UserDefaults.standard.set(newValue, forKey: "updates.check") } }
    }

    var installAutomatically: Bool {
        get { access(keyPath: \.installAutomatically); return UserDefaults.standard.bool(forKey: "updates.install") }
        set {
            withMutation(keyPath: \.installAutomatically) { UserDefaults.standard.set(newValue, forKey: "updates.install") }
            controller?.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    var includePrereleases: Bool {
        get { access(keyPath: \.includePrereleases); return UserDefaults.standard.bool(forKey: "updates.prereleases") }
        set { withMutation(keyPath: \.includePrereleases) { UserDefaults.standard.set(newValue, forKey: "updates.prereleases") } }
    }

    init(repository: any RepositoryService, enabled: Bool) {
        self.repository = repository
        self.enabled = enabled
        super.init()
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    static var build: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0 }

    /// Once a day while the app runs, when checking automatically.
    func runDaily() async {
        while !Task.isCancelled {
            if checkAutomatically { await check(userInitiated: false) }
            try? await Task.sleep(for: .seconds(24 * 3600))
        }
    }

    func check(userInitiated: Bool) async {
        guard enabled, !checking else { return }
        checking = true
        defer {
            checking = false
            lastChecked = Date()
        }
        do {
            guard let release = try await repository.latestRelease(includingPrereleases: includePrereleases),
                let feedAsset = release.assets.first(where: { $0.name == "appcast.xml" })
            else {
                available = nil
                return
            }
            let feed = String(decoding: try await repository.download(feedAsset), as: UTF8.self)
            guard let build = Appcast.build(feed), build > Self.build,
                let zipName = Appcast.enclosure(feed).map({ URL(string: $0)?.lastPathComponent ?? $0 }),
                let zipAsset = release.assets.first(where: { $0.name == zipName })
            else {
                available = nil
                return
            }
            available = Available(version: release.tagName.trimmingPrefix("v").description, build: build)
            // Sparkle reads only http(s), and never gets the token: it fetches
            // the feed and the update from GitHub's signed storage links,
            // found fresh on every check.
            feedLink = try await repository.storageURL(feedAsset)
            updateLink = try await repository.storageURL(zipAsset)
            startSparkle()
            if userInitiated {
                controller?.checkForUpdates(nil)
            } else {
                controller?.updater.checkForUpdatesInBackground()
            }
            problem = nil
        } catch {
            problem = message(error)
        }
    }

    /// Sparkle's own schedule stays off (`SUEnableAutomaticChecks` is NO in
    /// Info.plist): the app checks GitHub itself and hands Sparkle the feed.
    func startSparkle() {
        guard controller == nil else { return }
        let c = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        if c.updater.automaticallyDownloadsUpdates != installAutomatically {
            c.updater.automaticallyDownloadsUpdates = installAutomatically
        }
        c.startUpdater()
        controller = c
    }

    func feedURLString(for updater: SPUUpdater) -> String? { feedLink?.absoluteString }

    /// The update comes from the storage link found through the API, the
    /// same way for every repository, public or private. Sparkle still checks its EdDSA signature and length.
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        if let updateLink { request.url = updateLink }
    }

    /// A test version's feed is on the `beta` channel; Sparkle offers it only
    /// to someone who asked for test versions.
    func allowedChannels(for updater: SPUUpdater) -> Set<String> { includePrereleases ? ["beta"] : [] }
}
