#if DEBUG
    import Foundation
    import GitHubKit
    import LicenceCore
    import Register
    import Signing

    /// Example data for previews and the screenshot tour: the repository's real
    /// keys and free licence, and example customers. No network, no YubiKey.
    nonisolated enum Fixtures {
        static let today = CivilDate("2026-10-24")!
        static let ruben = "F2D214FC30698BA65A846B2BF2EA48D4C316406D"
        static let alessandro = "0BCE848225EFAECA912175292DBFB014CA506311"

        /// A key file from someone who set up a YubiKey but holds no key yet.
        /// Its certificate is the retired first key's, so it reads but is
        /// never trusted again.
        static let keyRequest = KeyRequest(
            holder: "Sanne de Vries", github: "sannedevries", medium: "YubiKey 40729511",
            certificate: repositoryFixtureFiles["keys/retired/5834C101A3F48578FD3CD1796C65DDBC5F712E51.asc"] ?? "")
        static let repo = URL(string: "https://github.com/FerroHEALTH/FerroLICENCE-register")!

        struct Example {
            let id: UUID
            let licensee: String
            let from: String
            let to: String
            let contract: String?
            let signer: String
            var renews: UUID?
            var revokedFrom: String?
            var reason: String?
            var pullRequest: Int?
        }

        static let hospitalOld = UUID(uuidString: "0193d8a4-5c00-7a11-8a6e-0c9d2f1e0001")!
        static let hospital = UUID(uuidString: "019ad4e2-1c00-7b22-9b7f-1d0e3a2f0002")!
        static let zorggroep = UUID(uuidString: "019a1234-2c00-7c33-8c80-2e1f4b300003")!
        static let kliniek = UUID(uuidString: "0199a1b2-3c00-7d44-9d91-3f2a5c410004")!
        static let demo = UUID(uuidString: "019c0f7e-4c00-7e55-8ea2-402b6d520005")!

        static let examples = [
            Example(
                id: hospitalOld, licensee: "Example Hospital NV", from: "2024-12-01", to: "2025-11-30", contract: "EH-2024-007",
                signer: ruben, pullRequest: 12),
            Example(
                id: hospital, licensee: "Example Hospital NV", from: "2025-12-01", to: "2026-11-30", contract: "EH-2025-014",
                signer: ruben, renews: hospitalOld, pullRequest: 38),
            Example(
                id: zorggroep, licensee: "Voorbeeld Zorggroep B.V.", from: "2026-10-23", to: "2027-10-22", contract: "VZ-2026-003",
                signer: alessandro, pullRequest: 39),
            Example(
                id: kliniek, licensee: "Kliniek Noord B.V.", from: "2025-10-01", to: "2026-09-30", contract: "KN-2025-002", signer: ruben),
            Example(
                id: demo, licensee: "Demo Clinic GmbH", from: "2026-02-01", to: "2027-01-31", contract: "DC-2026-001", signer: ruben,
                revokedFrom: "2026-10-23", reason: "Contract ended under clause 9.2", pullRequest: 40),
        ]

        /// The repository with the example customers added.
        static var snapshot: Snapshot {
            var files = repositoryFixtureFiles.mapValues { Data($0.utf8) }
            for e in examples {
                let licence = Licence(
                    id: e.id, licensee: e.licensee, issued: CivilDate(e.from)!, notBefore: CivilDate(e.from)!,
                    notAfter: CivilDate(e.to)!, use: .commercial)
                let folder = "register/\(slug(e.licensee))/\(e.id.uuidString.lowercased())"
                let file = Data("-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n\(licence.canonicalJSON)".utf8)
                files["\(folder)/licence.asc"] = file
                files["\(folder)/record.json"] =
                    Record(
                        licence: licence, signer: e.signer, tokenSHA256: sha256Hex(file), contract: e.contract,
                        renews: e.renews, recordedAt: CivilDate(e.from)!.start.addingTimeInterval(9 * 3600)
                    ).json
                if let from = e.revokedFrom {
                    files["\(folder)/revocation.json"] =
                        Revocation(
                            licenceID: e.id, effective: CivilDate(from)!, reason: e.reason ?? "",
                            recordedAt: CivilDate(from)!.start.addingTimeInterval(9 * 3600 + 40 * 60)
                        ).json
                }
            }
            return Snapshot(files: files, commit: "2836637a9f1c0e4b5d6e7f8091a2b3c4d5e6f708")
        }

        static func pull(_ n: Int) -> URL { repo.appending(path: "pull/\(n)") }

        static var activity: [Merged] {
            func at(_ day: String, _ h: Int, _ m: Int) -> Date { CivilDate(day)!.start.addingTimeInterval(TimeInterval(h * 3600 + m * 60)) }
            return [
                Merged(
                    number: 40, title: "Revoke Demo Clinic GmbH from 2026-10-23", mergedAt: at("2026-10-24", 9, 40),
                    author: "AlessandroTorrisi",
                    labels: ["revocation"], url: pull(40), branch: "revocation/demo-clinic-gmbh-2026-10-23-019c0f7e"),
                Merged(
                    number: 39, title: "Licence for Voorbeeld Zorggroep B.V. until 2027-10-22", mergedAt: at("2026-10-22", 8, 55),
                    author: "AlessandroTorrisi", labels: ["licence"], url: pull(39),
                    branch: "licence/voorbeeld-zorggroep-b-v-2026-10-23-019a1234"),
                Merged(
                    number: 38, title: "Renew Example Hospital NV until 2026-11-30", mergedAt: at("2025-12-01", 10, 2),
                    author: "rubentalstra",
                    labels: ["licence"], url: pull(38), branch: "licence/example-hospital-nv-2025-12-01-019ad4e2"),
                Merged(
                    number: 29, title: "Licence for Everyone, under the Business Source License 1.1 until 2099-12-31",
                    mergedAt: at("2026-10-07", 17, 15), author: "rubentalstra", labels: ["licence"], url: pull(29),
                    branch: "licence/everyone-under-the-business-source-license-1-1-2026-10-07-01a1175c"),
                Merged(
                    number: 28, title: "Trust the master keys of Ruben Talstra and Alessandro Torrisi", mergedAt: at("2026-10-07", 16, 40),
                    author: "rubentalstra", labels: ["key"], url: pull(28), branch: "key/f2d214fc"),
                Merged(
                    number: 12, title: "Licence for Example Hospital NV until 2025-11-30", mergedAt: at("2024-12-01", 11, 0),
                    author: "rubentalstra", labels: ["licence"], url: pull(12), branch: "licence/example-hospital-nv-2024-12-01-0193d8a4"),
            ]
        }

        /// A card that holds Ruben's key, set up and ready.
        static var readyCard: CardStatus {
            CardStatus(
                colons: "serial:40729502:\nvendor:0006:Yubico:\nforcepin:1:::\npinretry:3:0:3:\nsigcount:12:::\nuif:1:0:0:\n"
                    + "keyattr:1:22:ed25519:\nkeyattr:2:18:cv25519:\nkeyattr:3:22:ed25519:\nfpr:\(ruben):0:0:\n")!
        }

        /// A new card halfway through setup: PINs changed, no key yet.
        static var blankCard: CardStatus {
            CardStatus(
                colons: "serial:40729504:\nvendor:0006:Yubico:\nforcepin:1:::\npinretry:3:0:3:\nuif:0:0:0:\n"
                    + "keyattr:1:22:ed25519:\nkeyattr:2:18:cv25519:\nkeyattr:3:22:ed25519:\n")!
        }

        /// Identifiers made under Example Hospital's current licence, for Attest Data.
        static var sample: String {
            let key = StampKey.licence(hospital)
            let start = CivilDate("2025-12-04")!.start.timeIntervalSince1970
            let end = CivilDate("2026-10-20")!.start.timeIntervalSince1970
            let ids = (0..<412).map { i -> String in
                let t = start + (end - start) * Double(i) / 411
                let id = UUID.v7(now: Date(timeIntervalSince1970: t))
                return (i < 400 ? key.stamp(id) ?? id : id).uuidString.lowercased()
            }
            return "{\"patients\":[" + ids.map { "{\"id\":\"\($0)\"}" }.joined(separator: ",") + "]}"
        }

        /// The real free licence, signed on a YubiKey.
        static var freeLicenceFile: String {
            repositoryFixtureFiles.first { $0.key.hasSuffix("01a1175c-cd67-777d-bdc0-c95bf1c900d3/licence.asc") }!.value
        }
    }

    /// GitHub, played back from the fixtures. Recording takes a few seconds.
    actor FixtureRepository: RepositoryService {
        nonisolated let repositoryURL = Fixtures.repo
        var snapshot = Fixtures.snapshot
        var signedIn: Bool

        init(signedIn: Bool) { self.signedIn = signedIn }

        var isSignedIn: Bool { signedIn }

        func startSignIn() async throws -> DeviceCode {
            DeviceCode(
                userCode: "WDJB-MJHT", verificationURL: URL(string: "https://github.com/login/device")!,
                expiresAt: Date().addingTimeInterval(900), deviceCode: "fixture", interval: 5)
        }

        func finishSignIn(_ code: DeviceCode) async throws {
            try await Task.sleep(for: .seconds(3600))
        }

        func signOut() async { signedIn = false }

        func whoAmI() async throws -> (login: String, name: String?, canPush: Bool) { ("rubentalstra", "Ruben Talstra", true) }

        func sync(etag: String?) async throws -> SyncResult {
            SyncResult(snapshot: snapshot, etag: "W/\"fixture\"", commit: snapshot.commit ?? "")
        }

        func activity() async throws -> [Merged] { Fixtures.activity }

        func record(_ change: Change, progress: @escaping @Sendable (RecordingStep) -> Void) async throws -> RecordedChange {
            let url = Fixtures.pull(41)
            progress(.opened(number: 41, url: url))
            try await Task.sleep(for: .seconds(2))
            snapshot = snapshot.applying(change)
            progress(.merged(number: 41, url: url, commit: "8f3e2d1"))
            return RecordedChange(number: 41, url: url, commit: "8f3e2d1")
        }

        func latestRelease(includingPrereleases: Bool) async throws -> Release? { nil }

        func download(_ asset: Release.Asset) async throws -> Data { Data() }
        func storageURL(_ asset: Release.Asset) async throws -> URL { asset.url }
    }

    /// GnuPG and a YubiKey, played back. It never makes a signing key: only
    /// reading a real card does, so signing here waits until it is cancelled.
    nonisolated struct FixtureSigning: SigningService {
        let plugged: CardStatus?
        let setupCard: CardStatus?

        func tools() async -> Tools { Tools(gnupgVersion: "2.5.24", gnupgFolder: "/opt/homebrew/bin", pinentryMac: true) }

        func card() async -> CardStatus? { plugged }

        func signingKey(keys: Keys) async throws(NoSigningKey) -> SigningKey {
            try? await Task.sleep(for: .seconds(3600))
            throw .noCard
        }

        func sign(_ text: String, with key: SigningKey) async throws(GnuPGError) -> String { throw .cancelled }

        func probe(keys: Keys, pinsChanged: Bool) async -> SetupProbe {
            SetupProbe(card: setupCard, agentConfigured: true, trusted: false, pinsChanged: true)
        }

        func run(_ step: SetupStep, card: CardStatus?, status: @escaping @Sendable (String) -> Void) async throws(GnuPGError) {
            status("[GNUPG:] PINENTRY_LAUNCHED 1 curses")
            try? await Task.sleep(for: .seconds(2))
        }

        func exportPublic(_ fingerprint: String) async throws(GnuPGError) -> String { throw .notInstalled }
    }
#endif
