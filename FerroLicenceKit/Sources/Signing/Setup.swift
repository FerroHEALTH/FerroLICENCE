public import Foundation
public import Register

/// The steps from a new YubiKey to a trusted master key. Each is read back
/// from the card, so a setup that stopped halfway resumes where it stopped.
/// GnuPG does every step and asks for every PIN in its pinentry window.
public enum SetupStep: Int, CaseIterable, Sendable, Identifiable {
    case checkCard, pinWindow, changePINs, pinEverySignature, createKey, touchToSign, trust

    public var id: Int { rawValue }

    /// The user id on every master key: the licensor, never a person.
    public static let keyName = "FerroHEALTH Licensing"
    public static let keyEmail = "licensing@FerroHEALTH.eu"

    public var title: LocalizedStringResource {
        switch self {
        case .checkCard: LocalizedStringResource("Check the YubiKey", bundle: #bundle)
        case .pinWindow: LocalizedStringResource("Ask for PINs in a window", bundle: #bundle)
        case .changePINs: LocalizedStringResource("Change the PINs", bundle: #bundle)
        case .pinEverySignature: LocalizedStringResource("Ask for the PIN on every signature", bundle: #bundle)
        case .createKey: LocalizedStringResource("Create the key on the YubiKey", bundle: #bundle)
        case .touchToSign: LocalizedStringResource("Require a touch for every signature", bundle: #bundle)
        case .trust: LocalizedStringResource("Add the key to the trusted keys", bundle: #bundle)
        }
    }

    public var explanation: LocalizedStringResource {
        switch self {
        case .checkCard: LocalizedStringResource("One YubiKey 5 is plugged in, with no key on it yet.", bundle: #bundle)
        case .pinWindow:
            LocalizedStringResource(
                "GnuPG asks for PINs in a pinentry-mac window and never keeps one in the macOS Keychain.", bundle: #bundle)
        case .changePINs:
            LocalizedStringResource(
                "A window asks for the current PIN and a new one, then the same for the Admin PIN. Factory PINs are 123456 and 12345678. Write the Admin PIN down and keep it away from the YubiKey.",
                bundle: #bundle)
        case .pinEverySignature:
            LocalizedStringResource(
                "A window asks for your Admin PIN once. After that the card asks for the PIN for every licence.", bundle: #bundle)
        case .createKey:
            LocalizedStringResource(
                "GnuPG creates an Ed25519 key on the YubiKey: no expiry, no copy anywhere else. Windows ask for the Admin PIN several times and the PIN once; each window is a separate step. Afterwards, print the revocation certificate GnuPG writes to ~/.gnupg/openpgp-revocs.d/ and keep it with the Admin PIN, away from the YubiKey.",
                bundle: #bundle)
        case .touchToSign:
            LocalizedStringResource(
                "A window asks for your Admin PIN once. After that every licence needs a touch on the YubiKey.", bundle: #bundle)
        case .trust:
            LocalizedStringResource(
                "Records the public key in keys/ and you in signers.json through a pull request, so FerroEHR trusts it from its next release. If you hold no key yet, it saves the key as a file instead; an owner records it from their account with Trust a New Key… in Keys.",
                bundle: #bundle)
        }
    }
}

/// What the setup reads back to decide which steps are done.
public struct SetupProbe: Sendable, Equatable {
    public var card: CardStatus?
    public var agentConfigured: Bool
    public var trusted: Bool
    public var pinsChanged: Bool

    public init(card: CardStatus?, agentConfigured: Bool, trusted: Bool, pinsChanged: Bool) {
        self.card = card
        self.agentConfigured = agentConfigured
        self.trusted = trusted
        self.pinsChanged = pinsChanged
    }

    public func isDone(_ step: SetupStep) -> Bool {
        let hasKey = card?.signatureKey != nil
        switch step {
        case .checkCard: return card != nil
        case .pinWindow: return agentConfigured
        case .changePINs: return pinsChanged || hasKey
        case .pinEverySignature: return card?.pinEverySignature ?? false
        case .createKey: return hasKey
        case .touchToSign: return card?.touchToSign ?? false
        case .trust: return trusted
        }
    }

    /// The first step not done, `nil` when the card is ready.
    public var current: SetupStep? { SetupStep.allCases.first { !isDone($0) } }
}

/// `gpg-agent.conf`: a window pinentry, and no PIN cache in the Keychain.
public enum AgentConf {
    public static func isSet(_ conf: String) -> Bool {
        let lines = conf.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let window = lines.contains { $0.hasPrefix("pinentry-program ") && !$0.contains("tty") && !$0.contains("curses") }
        return window && lines.contains { $0.hasPrefix("no-allow-external-cache") }
    }

    /// `conf` with the missing lines appended; existing settings stay.
    public static func adding(to conf: String, pinentry: String) -> String {
        var out = conf
        if !out.isEmpty, !out.hasSuffix("\n") { out += "\n" }
        let lines = conf.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        if !lines.contains(where: { $0.hasPrefix("pinentry-program ") }) { out += "pinentry-program \(pinentry)\n" }
        if !lines.contains(where: { $0.hasPrefix("no-allow-external-cache") }) { out += "no-allow-external-cache\n" }
        return out
    }

    public static var pinentryMac: String? {
        ["/opt/homebrew/bin/pinentry-mac", "/usr/local/bin/pinentry-mac"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

extension GnuPG {
    /// Read back everything the setup depends on.
    public func probe(keys: Keys, pinsChanged: Bool) async -> SetupProbe {
        await releaseCard()
        let card = try? await cardStatus()
        let conf = (try? String(contentsOf: homeOrDefault.appending(path: "gpg-agent.conf"), encoding: .utf8)) ?? ""
        return SetupProbe(
            card: card ?? nil, agentConfigured: AgentConf.isSet(conf),
            trusted: (card ?? nil)?.signatureKey.map(keys.isTrusted) ?? false, pinsChanged: pinsChanged)
    }

    /// Run one setup step. `trust` is recorded by the app as a pull request,
    /// so it is not run here.
    public func run(_ step: SetupStep, card: CardStatus?, status: @Sendable @escaping (String) -> Void = { _ in }) async throws(GnuPGError)
    {
        switch step {
        case .checkCard, .trust: return
        case .pinWindow:
            guard let pinentry = AgentConf.pinentryMac else {
                throw .failed(arguments: ["pinentry"], stderr: "pinentry-mac is not installed. Run: brew install pinentry-mac")
            }
            try? FileManager.default.createDirectory(at: homeOrDefault, withIntermediateDirectories: true)
            let url = homeOrDefault.appending(path: "gpg-agent.conf")
            let conf = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            do { try AgentConf.adding(to: conf, pinentry: pinentry).write(to: url, atomically: true, encoding: .utf8) } catch {
                throw .failed(arguments: ["gpg-agent.conf"], stderr: error.localizedDescription)
            }
            await restartAgent()
        case .changePINs:
            try await changePIN(admin: false)
            try await changePIN(admin: true)
        case .pinEverySignature:
            if card?.pinEverySignature != true { try await cardEdit(["admin", "forcesig"], status: status) }
        case .createKey:
            await releaseCard()
            let commands = card?.curve25519 == true ? ["admin", "generate"] : ["admin", "key-attr", "generate"]
            try await cardEdit(commands, name: SetupStep.keyName, email: SetupStep.keyEmail, status: status)
        case .touchToSign:
            try await cardEdit(["admin", "uif 1 on"], status: status)
        }
    }
}

/// A GnuPG status line in words, when it says something a person should know.
public func describeStatus(_ line: String) -> LocalizedStringResource? {
    guard line.hasPrefix("[GNUPG:] ") else { return nil }
    let rest = line.dropFirst(9)
    if rest.hasPrefix("PINENTRY_LAUNCHED") { return LocalizedStringResource("A window asks for a PIN.", bundle: #bundle) }
    if rest.hasPrefix("KEY_CREATED") { return LocalizedStringResource("The key was created on the YubiKey.", bundle: #bundle) }
    if rest.hasPrefix("SC_OP_FAILURE 2") {
        return LocalizedStringResource("Wrong PIN. The window asks again; three wrong PINs block the card.", bundle: #bundle)
    }
    if rest.hasPrefix("GET_LINE keygen.") { return LocalizedStringResource("Creating the key…", bundle: #bundle) }
    return nil
}
