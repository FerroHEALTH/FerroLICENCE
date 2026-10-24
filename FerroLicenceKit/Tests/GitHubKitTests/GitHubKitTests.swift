import Foundation
import Register
import Synchronization
import Testing

@testable import GitHubKit

@Suite("Signing in")
struct SignInTests {
    @Test func waitsThroughPendingAndSlowDown() async throws {
        let gh = MockGitHub()
        gh.on(
            "POST", "/login/device/code",
            json:
                #"{"device_code":"dc","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#
        )
        let polls = Mutex(0)
        gh.on("POST", "/login/oauth/access_token") { _ in
            let n = polls.withLock {
                $0 += 1; return $0
            }
            return switch n {
            case 1: .json(#"{"error":"authorization_pending"}"#)
            case 2: .json(#"{"error":"slow_down","interval":10}"#)
            default: .json(#"{"access_token":"ghu_x","expires_in":28800,"refresh_token":"ghr_y","refresh_token_expires_in":15897600}"#)
            }
        }
        let flow = gh.flow()
        let code = try await flow.start()
        #expect(code.userCode == "WDJB-MJHT")
        let tokens = try await flow.waitForToken(code)
        #expect(tokens.access == "ghu_x")
        #expect(tokens.refresh == "ghr_y")
        let last = try #require(gh.requests("POST", "/login/oauth/access_token").last)
        #expect(last.form == ["client_id": "Iv1.test", "device_code": "dc", "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
    }

    @Test(arguments: [("access_denied", AuthError.denied), ("expired_token", AuthError.expired)])
    func stopsWhenGitHubSaysNo(_ answer: String, _ error: AuthError) async throws {
        let gh = MockGitHub()
        gh.on(
            "POST", "/login/device/code",
            json:
                #"{"device_code":"dc","user_code":"C","verification_uri":"https://github.com/login/device","expires_in":900,"interval":1}"#)
        gh.on("POST", "/login/oauth/access_token", json: #"{"error":"\#(answer)"}"#)
        let flow = gh.flow()
        let code = try await flow.start()
        await #expect(throws: error) { try await flow.waitForToken(code) }
    }

    @Test func refreshesAnExpiringToken() async throws {
        let gh = MockGitHub()
        gh.on(
            "POST", "/login/oauth/access_token",
            json: #"{"access_token":"ghu_new","expires_in":28800,"refresh_token":"ghr_new","refresh_token_expires_in":15897600}"#)
        gh.on("GET", "/user", json: #"{"login":"rubentalstra","name":"Ruben Talstra"}"#)
        let github = await gh.github(tokens: Tokens(access: "ghu_old", accessExpires: Date().addingTimeInterval(30), refresh: "ghr_old"))
        let user = try await github.user()
        #expect(user.login == "rubentalstra")
        #expect(gh.requests("GET", "/user").first?.headers["Authorization"] == "Bearer ghu_new")
        #expect(gh.requests("POST", "/login/oauth/access_token").first?.form["refresh_token"] == "ghr_old")
    }

    @Test func aRefusedRefreshSignsOut() async throws {
        let gh = MockGitHub()
        gh.on("POST", "/login/oauth/access_token", json: #"{"error":"bad_refresh_token"}"#)
        let github = await gh.github(tokens: Tokens(access: "a", accessExpires: .distantPast, refresh: "r"))
        await #expect(throws: AuthError.notSignedIn) { try await github.user() }
        #expect(await !github.credentials.isSignedIn)
    }
}

/// A blob cache in memory, counting what it was asked for.
actor MemoryCache: BlobCache {
    var blobs: [String: Data] = [:]
    func blob(_ sha: String) -> Data? { blobs[sha] }
    func store(_ data: Data, sha: String) { blobs[sha] = data }
}

@Suite("Fetching the register")
struct SyncTests {
    func serve(_ gh: MockGitHub) {
        gh.on("GET", "/repos/FerroHEALTH/FerroLICENCE-register/git/ref/heads/main", json: #"{"object":{"sha":"c1"}}"#)
        gh.on("GET", "/repos/FerroHEALTH/FerroLICENCE-register/git/trees/c1") { request in
            if request.headers["If-None-Match"] == #"W/"t1""# { return MockGitHub.Reply(status: 304, body: Data()) }
            return .json(
                """
                {"sha":"t1","truncated":false,"tree":[
                  {"path":"README.md","type":"blob","sha":"b0"},
                  {"path":"signers.json","type":"blob","sha":"b1"},
                  {"path":"keys","type":"tree","sha":"t2"},
                  {"path":"keys/A.asc","type":"blob","sha":"b2"},
                  {"path":"register/acme/1/record.json","type":"blob","sha":"b3"}]}
                """, headers: ["ETag": #"W/"t1""#])
        }
        for (sha, text) in [("b1", "[]"), ("b2", "key"), ("b3", "{}")] {
            gh.on(
                "GET", "/repos/FerroHEALTH/FerroLICENCE-register/git/blobs/\(sha)",
                json: #"{"content":"\#(Data(text.utf8).base64EncodedString())","encoding":"base64"}"#)
        }
    }

    @Test func downloadsOnlyTheRegisterFiles() async throws {
        let gh = MockGitHub()
        serve(gh)
        let result = try await gh.github().sync(etag: nil, cache: MemoryCache())
        let snapshot = try #require(result.snapshot)
        #expect(snapshot.files.keys.sorted() == ["keys/A.asc", "register/acme/1/record.json", "signers.json"])
        #expect(snapshot.text("keys/A.asc") == "key")
        #expect(snapshot.commit == "c1")
        #expect(result.etag == #"W/"t1""#)
        #expect(gh.requests("GET", "/repos/FerroHEALTH/FerroLICENCE-register/git/blobs/b0").isEmpty)
    }

    @Test func anUnchangedRegisterCostsOneAnswer() async throws {
        let gh = MockGitHub()
        serve(gh)
        let result = try await gh.github().sync(etag: #"W/"t1""#, cache: MemoryCache())
        #expect(result.snapshot == nil)
        #expect(!gh.requests.contains { $0.path.contains("/blobs/") })
    }

    @Test func aCachedBlobIsNotFetchedAgain() async throws {
        let gh = MockGitHub()
        serve(gh)
        let cache = MemoryCache()
        await cache.store(Data("[]".utf8), sha: "b1")
        _ = try await gh.github().sync(etag: nil, cache: cache)
        #expect(gh.requests("GET", "/repos/FerroHEALTH/FerroLICENCE-register/git/blobs/b1").isEmpty)
        #expect(gh.requests("GET", "/repos/FerroHEALTH/FerroLICENCE-register/git/blobs/b2").count == 1)
    }

    @Test func offlineSaysSo() async throws {
        let gh = MockGitHub()
        let github = GitHub(
            config: gh.config,
            credentials: Credentials(
                flow: gh.flow(),
                store: {
                    let s = MemoryTokenStore()
                    s.save(Tokens(access: "a", accessExpires: .distantFuture))
                    return s
                }()), session: URLSession(configuration: .ephemeral))
        await #expect(throws: GitHubError.offline) { try await github.branchHead("main") }
    }

    @Test func activityListsMergedChangesWithTheirPullRequest() async throws {
        let gh = MockGitHub()
        gh.on(
            "GET", "/repos/FerroHEALTH/FerroLICENCE-register/pulls",
            json: """
                [{"number":41,"title":"Licence for Acme until 2027-10-23","merged_at":"2026-10-24T10:00:00Z","user":{"login":"rubentalstra"},
                  "labels":[{"name":"licence"}],"html_url":"https://github.com/FerroHEALTH/FerroLICENCE/pull/41",
                  "head":{"ref":"licence/acme-2026-10-24-01a1175c"}},
                 {"number":40,"title":"docs: typo","merged_at":"2026-10-23T10:00:00Z","user":{"login":"x"},"labels":[{"name":"documentation"}],
                  "html_url":"https://github.com/FerroHEALTH/FerroLICENCE/pull/40","head":{"ref":"docs/typo"}},
                 {"number":39,"title":"Revoke Acme","merged_at":null,"user":{"login":"x"},"labels":[{"name":"revocation"}],
                  "html_url":"https://github.com/FerroHEALTH/FerroLICENCE/pull/39","head":{"ref":"revocation/acme-x"}}]
                """)
        let merged = try await gh.github().activity()
        #expect(merged.map(\.number) == [41])
        #expect(merged.first?.url.absoluteString == "https://github.com/FerroHEALTH/FerroLICENCE/pull/41")
        #expect(merged.first?.records(UUID(uuidString: "01a1175c-cd67-777d-bdc0-c95bf1c900d3")!) == true)
        #expect(merged.first?.records(UUID()) == false)
    }
}

@Suite("Recording a change")
struct RecorderTests {
    let repo = "/repos/FerroHEALTH/FerroLICENCE-register"
    let change = Change(
        kind: .revocation, writes: ["register/acme/1/revocation.json": Data("{}".utf8)],
        branch: "revocation/acme-2026-10-24-1", title: "Revoke Acme from 2026-10-24", body: "| | |")

    func serve(_ gh: MockGitHub) {
        gh.on("GET", "\(repo)/git/ref/heads/main", json: #"{"object":{"sha":"base"}}"#)
        gh.on("GET", "\(repo)/git/commits/base", json: #"{"tree":{"sha":"basetree"}}"#)
        gh.on("POST", "\(repo)/git/blobs", json: #"{"sha":"blob1"}"#, status: 201)
        gh.on("POST", "\(repo)/git/trees", json: #"{"sha":"tree1"}"#, status: 201)
        gh.on("POST", "\(repo)/git/commits", json: #"{"sha":"commit1"}"#, status: 201)
        gh.on("POST", "\(repo)/git/refs", json: #"{"ref":"refs/heads/x"}"#, status: 201)
        gh.on(
            "POST", "\(repo)/pulls", json: #"{"number":42,"html_url":"https://github.com/FerroHEALTH/FerroLICENCE-register/pull/42"}"#,
            status: 201)
        gh.on("POST", "\(repo)/issues/42/labels", json: "[]")
        gh.on("PUT", "\(repo)/pulls/42/merge", json: #"{"sha":"merged1","merged":true}"#)
        gh.on("DELETE", "\(repo)/git/refs/heads/revocation/acme-2026-10-24-1") { _ in MockGitHub.Reply(status: 204, body: Data()) }
    }

    /// The register's repository runs no CI: the app checks the change
    /// first, then opens the pull request and merges it.
    @Test func opensAndMerges() async throws {
        let gh = MockGitHub()
        serve(gh)
        let steps = Mutex<[RecordingStep]>([])
        let result = try await gh.github().record(change) { step in steps.withLock { $0.append(step) } }
        #expect(result.number == 42)
        #expect(result.commit == "merged1")
        let pr = URL(string: "https://github.com/FerroHEALTH/FerroLICENCE-register/pull/42")!
        #expect(steps.withLock { $0 } == [.opening, .opened(number: 42, url: pr), .merged(number: 42, url: pr, commit: "merged1")])

        let tree = try #require(gh.requests("POST", "\(repo)/git/trees").first?.json)
        #expect(tree["base_tree"] as? String == "basetree")
        let entries = try #require(tree["tree"] as? [[String: Any]])
        #expect(entries.first?["path"] as? String == "register/acme/1/revocation.json")
        #expect(entries.first?["sha"] as? String == "blob1")
        let merge = try #require(gh.requests("PUT", "\(repo)/pulls/42/merge").first?.json)
        #expect(merge["merge_method"] as? String == "squash")
        #expect(merge["sha"] as? String == "commit1")
        #expect(merge["commit_title"] as? String == "Revoke Acme from 2026-10-24 (#42)")
        #expect(gh.requests("POST", "\(repo)/issues/42/labels").first?.json["labels"] as? [String] == ["revocation"])
        #expect(gh.requests("DELETE", "\(repo)/git/refs/heads/revocation/acme-2026-10-24-1").count == 1)
        #expect(gh.requests("GET", "\(repo)/commits/commit1/check-runs").isEmpty)
    }

    @Test func deletingAFileSendsANullSha() async throws {
        let gh = MockGitHub()
        serve(gh)
        let retire = Change(
            kind: .key, writes: ["keys/retired/A.asc": Data("k".utf8)], deletes: ["keys/A.asc"],
            branch: "revocation/acme-2026-10-24-1", title: "Retire", body: "")
        _ = try await gh.github().record(retire) { _ in }
        let tree = try #require(gh.requests("POST", "\(repo)/git/trees").first?.json["tree"] as? [[String: Any]])
        let removed = try #require(tree.first { $0["path"] as? String == "keys/A.asc" })
        #expect(removed["sha"] is NSNull)
    }
}

@Suite("Updates")
struct UpdateTests {
    @Test func skipsDraftsAndPreReleasesUnlessAsked() async throws {
        let gh = MockGitHub()
        gh.on(
            "GET", "/repos/FerroHEALTH/FerroLICENCE/releases",
            json: """
                [{"tag_name":"v0.3.0","prerelease":false,"draft":true,"body":null,"assets":[]},
                 {"tag_name":"v0.3.0-beta.1","prerelease":true,"draft":false,"body":"beta","assets":[]},
                 {"tag_name":"v0.2.0","prerelease":false,"draft":false,"body":"stable",
                  "assets":[{"name":"FerroLICENCE-0.2.0.zip","url":"https://api.example.test/repos/FerroHEALTH/FerroLICENCE/releases/assets/7","size":3}]}]
                """)
        gh.on("GET", "/repos/FerroHEALTH/FerroLICENCE/releases/assets/7") { request in
            request.headers["Accept"] == "application/octet-stream" ? MockGitHub.Reply(body: Data("zip".utf8)) : .json("{}", status: 415)
        }
        let github = await gh.github()
        #expect(try await github.latestRelease(includingPrereleases: false)?.tagName == "v0.2.0")
        #expect(try await github.latestRelease(includingPrereleases: true)?.tagName == "v0.3.0-beta.1")
        let asset = try #require(try await github.latestRelease(includingPrereleases: false)?.assets.first)
        #expect(try await github.download(asset) == Data("zip".utf8))
    }

    @Test func findsTheStorageLinkWithoutSendingItTheToken() async throws {
        let gh = MockGitHub()
        let link = URL(string: "https://objects.example.test/blob/9?signature=x")!
        gh.on("HEAD", "/repos/FerroHEALTH/FerroLICENCE/releases/assets/9") { request in
            request.headers["Accept"] == "application/octet-stream" ? .redirect(to: link) : .json("{}", status: 415)
        }
        gh.on("HEAD", "/blob/9") { _ in MockGitHub.Reply(body: Data()) }
        let asset = Release.Asset(
            name: "appcast.xml", url: URL(string: "https://api.example.test/repos/FerroHEALTH/FerroLICENCE/releases/assets/9")!, size: 1)
        #expect(try await gh.github().storageURL(asset) == link)
        #expect(gh.requests("HEAD", "/blob/9").first?.headers["Authorization"] == nil)
        #expect(
            gh.requests("HEAD", "/repos/FerroHEALTH/FerroLICENCE/releases/assets/9").first?.headers["Authorization"] == "Bearer ghu_test")
    }

    @Test func anAssetGitHubServesItselfIsNoStorageLink() async throws {
        let gh = MockGitHub()
        gh.on("HEAD", "/repos/FerroHEALTH/FerroLICENCE/releases/assets/10") { _ in MockGitHub.Reply(body: Data()) }
        let asset = Release.Asset(
            name: "appcast.xml", url: URL(string: "https://api.example.test/repos/FerroHEALTH/FerroLICENCE/releases/assets/10")!, size: 1)
        await #expect(throws: GitHubError.self) { try await gh.github().storageURL(asset) }
    }

    @Test func theTokenIsNotSentToTheStorageHost() async throws {
        let gh = MockGitHub()
        gh.on("GET", "/repos/FerroHEALTH/FerroLICENCE/releases/assets/8") { _ in
            .redirect(to: URL(string: "https://objects.example.test/blob/8?signature=x")!)
        }
        gh.on("GET", "/blob/8") { _ in MockGitHub.Reply(body: Data("zip".utf8)) }
        let asset = Release.Asset(
            name: "FerroLICENCE-0.2.0.zip", url: URL(string: "https://api.example.test/repos/FerroHEALTH/FerroLICENCE/releases/assets/8")!,
            size: 3)
        #expect(try await gh.github().download(asset) == Data("zip".utf8))
        let storage = try #require(gh.requests("GET", "/blob/8").first)
        #expect(storage.headers["Authorization"] == nil)
        #expect(
            gh.requests("GET", "/repos/FerroHEALTH/FerroLICENCE/releases/assets/8").first?.headers["Authorization"] == "Bearer ghu_test")
    }
}
