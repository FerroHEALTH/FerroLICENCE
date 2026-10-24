// swift scripts/release/verify-update.swift <FerroLICENCE.app> <appcast.xml> <update.zip>
//
// Proves the update verifies the way the installed app will verify it: the
// EdDSA signature in the appcast, checked with the public key inside the
// app's own Info.plist (SUPublicEDKey), over the zip's bytes, and the length
// matches. A release whose app carries no key, or another key, fails here
// instead of on every Mac that tries to update.

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("verify-update: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments.dropFirst()
guard args.count == 3 else { fail("usage: verify-update.swift <app> <appcast.xml> <update.zip>") }
let (app, appcast, zip) = (
    URL(filePath: args[args.startIndex]), URL(filePath: args[args.startIndex + 1]), URL(filePath: args[args.startIndex + 2])
)

guard let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")),
    let key = info["SUPublicEDKey"] as? String, !key.isEmpty
else { fail("\(app.lastPathComponent) carries no SUPublicEDKey") }
guard let keyData = Data(base64Encoded: key), let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
else { fail("SUPublicEDKey is not a base64 Ed25519 public key") }

guard let feed = try? String(contentsOf: appcast, encoding: .utf8) else { fail("cannot read \(appcast.path())") }
guard let enclosure = feed.firstMatch(of: #/<enclosure\b[^>]*>/#)?.output else { fail("the appcast has no enclosure") }
let attributes = Dictionary(
    enclosure.matches(of: #/([\w:]+)="([^"]*)"/#).map { (String($0.output.1), String($0.output.2)) }, uniquingKeysWith: { a, _ in a })
func attribute(_ name: String) -> String? { attributes[name] }
guard let signature = attribute("sparkle:edSignature").flatMap({ Data(base64Encoded: $0) }) else {
    fail("the enclosure has no edSignature")
}
guard let bytes = try? Data(contentsOf: zip) else { fail("cannot read \(zip.path())") }
guard attribute("length") == String(bytes.count) else { fail("the enclosure's length is not the zip's size") }
guard publicKey.isValidSignature(signature, for: bytes) else { fail("the signature does not verify with the app's SUPublicEDKey") }
print("verify-update: \(zip.lastPathComponent) verifies with the app's SUPublicEDKey")
