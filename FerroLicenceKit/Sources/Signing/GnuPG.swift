public import Foundation
import Subprocess
import System

/// Why a GnuPG call failed.
public enum GnuPGError: Error, Equatable, Sendable, CustomStringConvertible {
    /// No `gpg` binary was found.
    case notInstalled
    /// `gpg` exited non-zero; what it said.
    case failed(arguments: [String], stderr: String)
    /// The person cancelled and `gpg` was stopped.
    case cancelled
    /// `gpg --card-edit` asked a question with no known answer, so it was
    /// stopped instead of guessing.
    case unexpected(question: String, output: String)

    public var message: LocalizedStringResource {
        switch self {
        case .notInstalled: LocalizedStringResource("GnuPG is not installed. Run: brew install gnupg pinentry-mac", bundle: #bundle)
        case .failed(let args, let stderr):
            if stderr.contains("Bad PIN") {
                LocalizedStringResource("Wrong PIN. Each wrong PIN uses one of the card's three tries.", bundle: #bundle)
            } else if stderr.contains("Operation cancelled") || stderr.contains("Canceled") {
                LocalizedStringResource("Signing was cancelled in the PIN window.", bundle: #bundle)
            } else {
                LocalizedStringResource(
                    "gpg \(args.first ?? "") failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))", bundle: #bundle)
            }
        case .cancelled: LocalizedStringResource("Cancelled.", bundle: #bundle)
        case .unexpected(let q, _):
            LocalizedStringResource("GnuPG asked something unexpected (\(q)); nothing more was answered.", bundle: #bundle)
        }
    }

    public var description: String { String(localized: message) }
}

extension GnuPGError {
    /// Whether the card refused the PIN.
    public var isBadPIN: Bool {
        if case .failed(_, let stderr) = self { stderr.contains("Bad PIN") } else { false }
    }
}

/// What a person reads after a wrong PIN, with the tries the card has left.
public func wrongPIN(triesLeft: Int?) -> LocalizedStringResource {
    switch triesLeft {
    case 0?:
        LocalizedStringResource(
            "The PIN is blocked after three wrong tries. Unblock it with the Admin PIN: in Terminal run gpg --card-edit, then admin, passwd, and choose 2.",
            bundle: #bundle)
    case 1?: LocalizedStringResource("Wrong PIN. 1 try left before the PIN is blocked.", bundle: #bundle)
    case let n?: LocalizedStringResource("Wrong PIN. \(n) tries left.", bundle: #bundle)
    case nil: LocalizedStringResource("Wrong PIN. Each wrong PIN uses one of the card's three tries.", bundle: #bundle)
    }
}

/// A thin, explicit wrapper over the `gpg` command line. Every key operation
/// goes through here with its arguments visible: GnuPG generates the key on
/// the YubiKey, lists it, exports its public certificate and signs. The app
/// reads only public exports, colon listings, the card status, status lines
/// and armored signatures. Every PIN is asked by GnuPG's own pinentry window.
public struct GnuPG: Sendable {
    /// The `gpg` binary.
    public let executable: URL
    /// The GnuPG home, `nil` for GnuPG's default.
    public let home: URL?
    /// Tests only: a passphrase for software keys in a throwaway keyring.
    let loopbackPassphrase: String?

    /// The installed GnuPG, looked for where Homebrew and GPG installers put it.
    public static func find(home: URL? = nil) -> GnuPG? {
        let candidates = ["/opt/homebrew/bin/gpg", "/usr/local/bin/gpg", "/usr/local/MacGPG2/bin/gpg", "/usr/bin/gpg"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        return GnuPG(executable: URL(filePath: path), home: home, loopbackPassphrase: nil)
    }

    public init(executable: URL, home: URL? = nil, loopbackPassphrase: String? = nil) {
        self.executable = executable
        self.home = home
        self.loopbackPassphrase = loopbackPassphrase
    }

    /// `gpgconf`, beside `gpg`.
    var gpgconf: URL { executable.deletingLastPathComponent().appending(path: "gpgconf") }

    /// The folder GnuPG reads `gpg-agent.conf` from.
    public var homeOrDefault: URL {
        home ?? ProcessInfo.processInfo.environment["GNUPGHOME"].map { URL(filePath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".gnupg")
    }

    var baseArguments: [String] {
        var args = ["--batch", "--yes"]
        if let home { args += ["--homedir", home.path] }
        if let loopbackPassphrase { args += ["--pinentry-mode", "loopback", "--passphrase", loopbackPassphrase] }
        return args
    }

    /// Run `gpg` with `arguments`, feeding `input`, returning stdout.
    public func run(_ arguments: [String], input: String? = nil) async throws(GnuPGError) -> String {
        let result = try await Command.run(executable, baseArguments + arguments, input: input)
        guard result.status.isSuccess else { throw .failed(arguments: arguments, stderr: result.stderr) }
        return result.stdout
    }

    /// The first line of `gpg --version`.
    public func version() async -> String? {
        try? await run(["--version"]).split(separator: "\n").first.map(String.init)
    }

    /// The YubiKey plugged in now, or `nil` when there is none. Unlike the
    /// keyring, which remembers cards, this asks the card itself.
    public func cardStatus() async throws(GnuPGError) -> CardStatus? {
        do {
            return CardStatus(colons: try await run(["--with-colons", "--card-status"]))
        } catch .failed(_, let stderr)
            where stderr.contains("card not available") || stderr.contains("selecting card failed")
            || stderr.contains("No such device") || stderr.contains("Card not present")
        {
            return nil
        }
    }

    /// Every primary key whose secret is on a card, as the keyring lists it.
    public func cardKeys() async throws(GnuPGError) -> [CardKey] {
        CardKey.parse(try await run(["--with-colons", "--with-fingerprint", "--list-secret-keys"]))
    }

    /// The primary key `fingerprint` as this keyring lists it.
    public func publicPrimary(_ fingerprint: String) async throws(GnuPGError) -> PublicPrimary? {
        PublicPrimary.parse(try await run(["--with-colons", "--with-fingerprint", "--list-keys", fingerprint]))
    }

    /// The armored public certificate: primary, user id, all subkeys.
    public func exportPublic(_ fingerprint: String) async throws(GnuPGError) -> String {
        try await run(["--armor", "--export", fingerprint])
    }

    /// Bring a public certificate into the keyring, so GnuPG can use the
    /// card's key without a manual step.
    public func importPublic(_ armored: String) async throws(GnuPGError) {
        _ = try await run(["--import"], input: armored)
    }

    /// Cleartext-sign `text` with exactly the primary key `fingerprint`; the
    /// trailing `!` pins GnuPG to that key, never one of its subkeys.
    /// Cancelling the task stops `gpg`.
    public func clearsign(_ text: String, with fingerprint: String) async throws(GnuPGError) -> String {
        try await run(["--armor", "--clearsign", "--digest-algo", "SHA512", "--local-user", "\(fingerprint)!"], input: text)
    }

    /// Stop GnuPG's card daemon, so a stuck card is found again; GnuPG
    /// restarts it on its next use.
    public func releaseCard() async {
        _ = try? await Command.run(gpgconf, (home.map { ["--homedir", $0.path] } ?? []) + ["--kill", "scdaemon"])
    }

    /// Restart `gpg-agent`, so it reads a changed `gpg-agent.conf`.
    public func restartAgent() async {
        _ = try? await Command.run(gpgconf, (home.map { ["--homedir", $0.path] } ?? []) + ["--kill", "gpg-agent"])
    }

    /// Change the card's PIN (`OPENPGP.1`) or Admin PIN (`OPENPGP.3`). The
    /// card's daemon asks for the old and new PIN in the pinentry window.
    public func changePIN(admin: Bool) async throws(GnuPGError) {
        let agent = executable.deletingLastPathComponent().appending(path: "gpg-connect-agent")
        let args = (home.map { ["--homedir", $0.path] } ?? []) + ["SCD PASSWD \(admin ? "OPENPGP.3" : "OPENPGP.1")", "/bye"]
        let result = try await Command.run(agent, args)
        if result.stdout.contains("ERR") || !result.status.isSuccess {
            throw .failed(arguments: ["passwd"], stderr: result.stdout + result.stderr)
        }
    }

    /// Drive `gpg --card-edit` through its command and status descriptors,
    /// answering each question by name, as a person would at its prompts.
    /// `commands` are typed at the menu prompt in order. A question not in
    /// the table stops `gpg`. GnuPG asks for every PIN in its pinentry window.
    public func cardEdit(
        _ commands: [String], name: String = "", email: String = "",
        status: @Sendable (String) -> Void = { _ in }
    ) async throws(GnuPGError) {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw .notInstalled }
        let arguments = (home.map { ["--homedir", $0.path] } ?? []) + ["--no-tty", "--command-fd", "0", "--status-fd", "1", "--card-edit"]
        let result: ExecutionResult<String?, SequenceOutput, StringOutput<UTF8>>
        do {
            result = try await Subprocess.run(
                .path(FilePath(executable.path)), arguments: Arguments(arguments),
                input: .inputWriter, output: .sequence, error: .string(limit: Command.limit)
            ) { execution in
                var remaining = commands
                var printed = ""
                for try await line in execution.standardOutput.strings() {
                    let line = line.trimmingCharacters(in: .newlines)
                    guard line.hasPrefix("[GNUPG:] ") else {
                        printed += line + "\n"
                        continue
                    }
                    status(line)
                    switch CardEdit.answer(line, commands: &remaining, name: name, email: email) {
                    case .none: continue
                    case .line(let answer): _ = try await execution.standardInputWriter.write(answer + "\n")
                    case .stop:
                        try? execution.send(signal: .terminate)
                        try? await execution.standardInputWriter.finish()
                        throw CardEdit.Stopped(question: line, output: printed)
                    }
                }
                try await execution.standardInputWriter.finish()
                return printed
            }
        } catch let stopped as CardEdit.Stopped {
            throw .unexpected(question: stopped.question, output: stopped.output)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw Task.isCancelled ? .cancelled : .failed(arguments: ["--card-edit"], stderr: String(describing: error))
        }
        if Task.isCancelled { throw .cancelled }
        guard result.terminationStatus.isSuccess else {
            throw .failed(arguments: ["--card-edit"], stderr: (result.closureResult ?? "") + result.standardError)
        }
    }
}

/// The answer to one `[GNUPG:]` status line of `gpg --card-edit`.
public enum CardEdit {
    public enum Answer: Equatable, Sendable { case none, line(String), stop }

    struct Stopped: Error {
        let question: String
        let output: String
    }

    /// `commands` are the menu commands still to type; the menu prompt takes the next.
    public static func answer(_ line: String, commands: inout [String], name: String, email: String) -> Answer {
        guard line.hasPrefix("[GNUPG:] ") else { return .none }
        let rest = line.dropFirst("[GNUPG:] ".count)
        let question: Substring
        if rest.hasPrefix("GET_LINE ") {
            question = rest.dropFirst(9)
        } else if rest.hasPrefix("GET_BOOL ") {
            question = rest.dropFirst(9)
        } else if rest.hasPrefix("GET_") {
            return .stop
        } else {
            return .none
        }
        switch question.trimmingCharacters(in: .whitespaces) {
        case "cardedit.prompt": return .line(commands.isEmpty ? "quit" : commands.removeFirst())
        case "cardedit.genkeys.algo": return .line("2")  // ECC
        case "keygen.curve": return .line("1")  // Curve 25519
        case "cardedit.genkeys.backup_enc", "cardedit.genkeys.replace_keys": return .line("n")
        case "keygen.valid": return .line("0")
        case "keygen.valid.okay": return .line("y")
        case "keygen.name": return .line(name)
        case "keygen.email": return .line(email)
        case "keygen.comment": return .line("")
        case "keygen.userid.cmd": return .line("O")
        default: return .stop
        }
    }
}

/// One run of a command line tool.
enum Command {
    /// The most output a GnuPG call may print: far above a certificate or a listing.
    static let limit = 4 << 20

    struct Result: Sendable {
        let status: TerminationStatus
        let stdout: String
        let stderr: String
    }

    /// Run `executable`, feeding it `input`. Cancelling the task stops the
    /// process, with SIGTERM and then SIGKILL.
    static func run(_ executable: URL, _ arguments: [String], input: String? = nil) async throws(GnuPGError) -> Result {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw .notInstalled }
        let result: ExecutionResult<Void, StringOutput<UTF8>, StringOutput<UTF8>>
        do {
            result = try await Subprocess.run(
                .path(FilePath(executable.path)), arguments: Arguments(arguments),
                input: .string(input ?? ""), output: .string(limit: limit), error: .string(limit: limit))
        } catch {
            throw Task.isCancelled ? .cancelled : .failed(arguments: arguments, stderr: String(describing: error))
        }
        // A cancelled run is torn down and returns; it does not throw.
        if Task.isCancelled { throw .cancelled }
        return Result(status: result.terminationStatus, stdout: result.standardOutput, stderr: result.standardError)
    }
}
