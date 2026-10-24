import AppKit
import Foundation
import GitHubKit
import LicenceCore
import Register
import SwiftData

/// How this launch was asked to run. Debug builds accept launch arguments
/// for the screenshot tour: `-FLFixtures YES -FLScreen customers
/// -FLAppearance dark -FLWindowSize 1100x700`.
struct Launch {
    var fixtures = false
    var screen: Screen?
    var dark: Bool?
    var windowSize: CGSize?

    static var current: Launch {
        var launch = Launch()
        #if DEBUG
            let defaults = UserDefaults.standard
            launch.fixtures =
                defaults.bool(forKey: "FLFixtures") || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            launch.screen = defaults.string(forKey: "FLScreen").flatMap(Screen.init(rawValue:))
            launch.dark = defaults.string(forKey: "FLAppearance").map { $0 == "dark" }
            if let size = defaults.string(forKey: "FLWindowSize")?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
                launch.windowSize = CGSize(width: size[0], height: size[1])
            }
        #endif
        return launch
    }

    /// The register's repository from the build settings, `owner/name`.
    static var repository: (owner: String, name: String) {
        let parts = (Bundle.main.object(forInfoDictionaryKey: "FLRepository") as? String ?? "").split(separator: "/").map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : ("FerroHEALTH", "FerroLICENCE-register")
    }

    /// The repository the app's releases come from, `owner/name`.
    static var releases: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "FLReleases") as? String ?? ""
        return value.split(separator: "/").count == 2 ? value : "FerroHEALTH/FerroLICENCE"
    }

    /// The GitHub App's client id from the build settings.
    static var clientID: String { Bundle.main.object(forInfoDictionaryKey: "FLGitHubClientID") as? String ?? "" }
}

/// Every screen the tour photographs, in the design's order.
enum Screen: String, CaseIterable {
    case signIn, ready, customers, draft, check, sign, recording, recorded, revoke
    case activity, checkFile, attest, keys, stopKey, trustKey, setup, sync, settings
}

/// The services this launch uses: GitHub and GnuPG, or the fixtures.
@MainActor
func makeModel(_ launch: Launch) -> (AppModel, Updater) {
    #if DEBUG
        if launch.fixtures {
            let container = try! OfflineStore.container(inMemory: true)
            let repository = FixtureRepository(signedIn: launch.screen != .signIn)
            let card = launch.screen == .setup ? nil : Fixtures.readyCard
            let model = AppModel(
                repository: repository, signing: FixtureSigning(plugged: card, setupCard: Fixtures.blankCard),
                store: OfflineStore(modelContainer: container), notifier: Notifier(enabled: false),
                fixedToday: Fixtures.today)
            return (model, Updater(repository: repository, enabled: false))
        }
    #endif
    let container: ModelContainerBox = .shared
    let repository = LiveRepository(clientID: Launch.clientID, cache: container.store)
    let model = AppModel(repository: repository, signing: LiveSigning(), store: container.store, notifier: Notifier(enabled: true))
    // A build without Sparkle's public key (one built from source) cannot
    // verify an update, so it never offers one; the release lane refuses to
    // publish an app without it.
    let updateKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
    return (model, Updater(repository: repository, enabled: !updateKey.isEmpty))
}

/// The on-disk offline copy, opened once.
@MainActor
final class ModelContainerBox {
    static let shared = ModelContainerBox()
    let store: OfflineStore

    init() {
        do {
            store = OfflineStore(modelContainer: try OfflineStore.container(inMemory: false))
        } catch {
            // A damaged copy is only a cache: start again in memory.
            store = OfflineStore(modelContainer: try! OfflineStore.container(inMemory: true))
        }
    }
}

#if DEBUG
    extension AppModel {
        /// Put the model in the state one screen of the design shows.
        func apply(_ screen: Screen) {
            let hospital = register.entry(Fixtures.hospital)
            switch screen {
            case .signIn:
                phase = .signedOut
                deviceCode = DeviceCode(
                    userCode: "WDJB-MJHT", verificationURL: URL(string: "https://github.com/login/device")!,
                    expiresAt: Date().addingTimeInterval(900), deviceCode: "fixture", interval: 5)
            case .ready:
                phase = .checking
            case .customers, .sync:
                selectedCustomer = "example-hospital-nv"
            case .draft, .check, .sign, .recording, .recorded:
                selectedCustomer = "example-hospital-nv"
                guard let hospital else { return }
                renew(hospital)
                issue?.draft.contract = "EH-2026-021"
                if screen == .draft { return }
                issue?.toCheck()
                if screen == .check { return }
                issue?.step = .sign
                if screen == .sign { return }
                issue?.step = .recording
                issue?.recording =
                    screen == .recording
                    ? .inProgress(.opened(number: 41, url: Fixtures.pull(41)))
                    : .recorded(RecordedChange(number: 41, url: Fixtures.pull(41), commit: "8f3e2d1"))
                issue?.signedFile = Fixtures.freeLicenceFile
            case .revoke:
                selectedCustomer = "voorbeeld-zorggroep-b-v"
                guard let entry = register.entry(Fixtures.zorggroep) else { return }
                startRevoke(entry)
                revoke?.reason = "Contract ended under clause 9.2"
                revoke?.typed = "REVOKE"
            case .activity: section = .activity
            case .checkFile:
                section = .checkFile
                checkedFile = CheckedFile(name: "everyone.licence.asc", text: Fixtures.freeLicenceFile)
            case .attest:
                section = .attest
                attestedFile = CheckedFile(name: "ehr-sample.json", text: Fixtures.sample)
            case .keys, .setup: section = .keys
            case .stopKey:
                section = .keys
                stopKey = StopKeyFlow(model: self, fingerprint: Fixtures.alessandro)
            case .trustKey:
                section = .keys
                trustKey = TrustKeyFlow(model: self)
                trustKey?.request = Fixtures.keyRequest
                trustKey?.fileName = "sanne-de-vries.key.json"
            case .settings: break
            }
        }
    }
#endif
