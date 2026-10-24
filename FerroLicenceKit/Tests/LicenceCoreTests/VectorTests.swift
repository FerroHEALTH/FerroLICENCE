import Foundation
import Testing

@testable import LicenceCore

/// The cases in `Vectors/vectors.json` were answered by the Rust checker that
/// FerroEHR runs. Every answer here must be the same; a difference fails the
/// build, so the two checkers never drift apart.
struct Vectors: Decodable {
    struct Case: Decodable {
        let name: String
        let token: String
        let anchors: [String]
        let day: String
        let result: String
        let licence: [String: String]?
    }
    struct Canonical: Decodable {
        let licence: [String: String]
        let canonical: String
    }
    struct Stamp: Decodable {
        let licence_id: String?
        let timestamp_ms: UInt64
        let stamp: String
    }
    struct StampUUID: Decodable {
        let licence_id: String
        let input: String
        let output: String
    }
    struct Tail: Decodable {
        let n: Int
        let k: Int
        let p: Double
        let tail: Double
    }
    let cases: [Case]
    let canonical: [Canonical]
    let stamps: [Stamp]
    let stamp_uuid: StampUUID
    let binomial_tail: [Tail]

    static let dir = Bundle.module.resourceURL!.appending(path: "Vectors")
    /// The register as it was when it moved to its own repository
    /// (`Tests/RegisterSnapshot`): its keys and licence files.
    static let repo = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../RegisterSnapshot").standardized
    static let all: Vectors = try! JSONDecoder().decode(Vectors.self, from: Data(contentsOf: dir.appending(path: "vectors.json")))
}

func name(of error: VerifyError) -> String {
    switch error {
    case .untrustedPrimary: "UntrustedPrimary"
    case .brokenBindings: "BrokenBindings"
    case .noSignature: "NoSignature"
    case .extraSignatures: "ExtraSignatures"
    case .notTextSignature: "NotTextSignature"
    case .noIssuer: "NoIssuer"
    case .unknownSigner: "UnknownSigner"
    case .notSigningCapable: "NotSigningCapable"
    case .noSigningTime: "NoSigningTime"
    case .expiredAtSigning: "ExpiredAtSigning"
    case .badSignature: "BadSignature"
    case .payload: "Payload"
    case .notYetValid: "NotYetValid"
    case .expired: "Expired"
    }
}

func tokenName(_ failure: Token.Failure) -> String {
    switch failure {
    case .missingSignedMessage: "Token:MissingSignedMessage"
    case .missingCertificate: "Token:MissingCertificate"
    case .message: "Token:Message"
    case .certificate: "Token:Certificate"
    }
}

func file(_ name: String, register: Bool) -> URL {
    if register {
        // Register cases name the repository's own files.
        let all = FileManager.default.enumerator(at: Vectors.repo.appending(path: "register"), includingPropertiesForKeys: nil)!
        return all.compactMap { $0 as? URL }.first { $0.lastPathComponent == name && $0.path.contains("01a") }!
    }
    return Vectors.dir.appending(path: "tokens/\(name)")
}

@Test(arguments: Vectors.all.cases.map(\.name))
func theSwiftCheckerAgreesWithTheRustChecker(_ caseName: String) throws {
    let c = Vectors.all.cases.first { $0.name == caseName }!
    let isRegister = c.name.hasPrefix("register_")
    let anchorURLs = c.anchors.map {
        isRegister ? Vectors.repo.appending(path: "keys/\($0)") : Vectors.dir.appending(path: "anchors/\($0)")
    }
    let anchors = try anchorURLs.map { try Certificate(armored: String(contentsOf: $0, encoding: .utf8)) }
    let tokenURL: URL
    if isRegister {
        let id = c.name == "register_free_licence" ? "01a1175c-cd67-777d-bdc0-c95bf1c900d3" : "01a090a8-59e4-76da-92f5-3f7e4ea9d7c0"
        tokenURL = Vectors.repo.appending(path: "register/everyone-under-the-business-source-license-1-1/\(id)/licence.asc")
    } else {
        tokenURL = Vectors.dir.appending(path: "tokens/\(c.token)")
    }
    let text = try String(contentsOf: tokenURL, encoding: .utf8)
    let result: String
    var licence: Licence?
    do {
        let token = try Token(text)
        do {
            licence = try verify(token, anchors: anchors, on: CivilDate(c.day)!).licence
            result = "ok"
        } catch {
            result = name(of: error)
            licence = try? Licence.parse(token.signedText)
        }
    } catch {
        result = tokenName(error)
    }
    #expect(result == c.result, "\(c.name)")
    if let expected = c.licence {
        #expect(licence?.id.uuidString.lowercased() == expected["licence_id"])
        #expect(licence?.licensee == expected["licensee"])
        #expect(licence?.notAfter.description == expected["not_after"])
    } else {
        #expect(licence == nil, "\(c.name)")
    }
}

@Test func canonicalJSONMatchesSerdeByteForByte() throws {
    for v in Vectors.all.canonical {
        let l = try Licence.parse(v.canonical)
        #expect(l.canonicalJSON == v.canonical)
        #expect(l.licensee == v.licence["licensee"])
    }
}

@Test func stampsMatch() {
    for s in Vectors.all.stamps {
        let key = s.licence_id.map { StampKey.licence(UUID(uuidString: $0)!) } ?? .unlicensed
        #expect(key.stamp16(s.timestamp_ms).hexLower == s.stamp, "\(String(describing: s.licence_id)) \(s.timestamp_ms)")
    }
    let v = Vectors.all.stamp_uuid
    let stamped = StampKey.licence(UUID(uuidString: v.licence_id)!).stamp(UUID(uuidString: v.input)!)
    #expect(stamped?.uuidString.lowercased() == v.output)
    #expect(StampKey.licence(UUID(uuidString: v.licence_id)!).carries(UUID(uuidString: v.output)!))
}

@Test func binomialTailsMatch() {
    for t in Vectors.all.binomial_tail {
        let got = Attest.binomialUpperTail(n: t.n, k: t.k, p: t.p)
        if t.tail == 0 {
            #expect(got == 0)
        } else {
            #expect(abs(got - t.tail) <= abs(t.tail) * 1e-12, "n=\(t.n) k=\(t.k) p=\(t.p): \(got) vs \(t.tail)")
        }
    }
}
