public import Foundation
import LicenceCore
import Subprocess
import System

/// Why a `ferrohealth-sop` call failed.
public enum SOPError: Error, Equatable, Sendable, CustomStringConvertible {
    /// No `ferrohealth-sop` binary was found.
    case notInstalled
    /// The program exited non-zero: the subcommand, its failure and what it said.
    case failed(subcommand: String, failure: SOPFailure, stderr: String)
    /// The person cancelled and the program was stopped.
    case cancelled

    public var message: LocalizedStringResource {
        switch self {
        case .notInstalled: LocalizedStringResource("ferrohealth-sop is not installed.", bundle: #bundle)
        case .cancelled: LocalizedStringResource("Cancelled.", bundle: #bundle)
        case .failed(let subcommand, let failure, let stderr):
            switch failure {
            case .noSignature: LocalizedStringResource("No valid signature.", bundle: #bundle)
            case .unsupportedAlgorithm:
                LocalizedStringResource("The key is not an ML-DSA-65+Ed25519 key (RFC 9980 algorithm 30).", bundle: #bundle)
            case .keyCannotSign: LocalizedStringResource("The key may not sign.", bundle: #bundle)
            case .noHardwareKey: LocalizedStringResource("The hardware key was not found. Plug it in.", bundle: #bundle)
            case .hardwareKeyFailure: LocalizedStringResource("The hardware key refused to sign.", bundle: #bundle)
            default:
                LocalizedStringResource(
                    "ferrohealth-sop \(subcommand) failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))", bundle: #bundle)
            }
        }
    }

    public var description: String { String(localized: message) }
}

/// The failure a Stateless OpenPGP program reports by its exit code
/// (draft-dkg-openpgp-stateless-cli-16 §8).
public enum SOPFailure: Equatable, Sendable {
    case noSignature
    case unsupportedAlgorithm
    case badData
    case keyIsProtected
    case keyCannotSign
    case noHardwareKey
    case hardwareKeyFailure
    case primaryKeyBad
    case other(Int32)

    public init(exitCode: Int32) {
        self =
            switch exitCode {
            case 3: .noSignature
            case 13: .unsupportedAlgorithm
            case 41: .badData
            case 67: .keyIsProtected
            case 79: .keyCannotSign
            case 97: .noHardwareKey
            case 101: .hardwareKeyFailure
            case 103: .primaryKeyBad
            default: .other(exitCode)
            }
    }
}

/// `ferrohealth-sop`, the family's RFC 9980 ID 30 signer: a Stateless
/// OpenPGP command line. KEYS, CERTS and SIGNATURES are file paths, and a
/// secret key goes from its file to the program, never through this process.
public struct SOP: Sendable {
    /// The `ferrohealth-sop` binary.
    public let executable: URL

    public init(executable: URL) { self.executable = executable }

    /// The installed program, looked for where Homebrew and Cargo put it.
    public static func find() -> SOP? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path()
        let candidates = ["/opt/homebrew/bin", "/usr/local/bin", "\(home).cargo/bin"].map { "\($0)/ferrohealth-sop" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { SOP(executable: URL(filePath: $0)) }
    }

    /// A detached text signature over `text` (`sign --as=text`), armored.
    public func sign(_ text: String, keys: URL) async throws(SOPError) -> String {
        try await run(["sign", "--as=text", "--", keys.path()], input: .string(text))
    }

    /// The lines `verify` prints for each valid signature over `text`, read
    /// as a text document. No valid signature is `.noSignature`.
    public func verify(_ text: String, signatures: URL, certificates: [URL]) async throws(SOPError) -> [String] {
        let out = try await run(["verify", "--", signatures.path()] + certificates.map { $0.path() }, input: .string(text))
        return out.split(separator: "\n").map(String.init)
    }

    /// The public certificate of the key in `keys` (`extract-cert`).
    public func extractCert(keys: URL) async throws(SOPError) -> String {
        let fd: FileDescriptor
        do { fd = try FileDescriptor.open(FilePath(keys.path()), .readOnly) } catch {
            throw .failed(subcommand: "extract-cert", failure: .other(-1), stderr: String(describing: error))
        }
        return try await run(["extract-cert"], input: .fileDescriptor(fd, closeAfterSpawningProcess: true))
    }

    #if DEBUG
        /// Tests only: a software ID 30 key written straight to `file`, which
        /// debug builds alone compile, so no release makes a software key.
        func generateKey(userID: String, into file: URL) async throws(SOPError) {
            let fd: FileDescriptor
            do {
                fd = try FileDescriptor.open(
                    FilePath(file.path()), .writeOnly, options: [.create, .truncate], permissions: [.ownerReadWrite])
            } catch {
                throw .failed(subcommand: "generate-key", failure: .other(-1), stderr: String(describing: error))
            }
            defer { try? fd.close() }
            let result: ExecutionResult<Void, FileDescriptorOutput, StringOutput<UTF8>>
            do {
                result = try await Subprocess.run(
                    .path(FilePath(executable.path())), arguments: ["generate-key", "--", userID],
                    output: .fileDescriptor(fd, closeAfterSpawningProcess: false), error: .string(limit: Command.limit))
            } catch {
                throw Task.isCancelled
                    ? .cancelled : .failed(subcommand: "generate-key", failure: .other(-1), stderr: String(describing: error))
            }
            try Self.check(result.terminationStatus, "generate-key", result.standardError ?? "")
        }
    #endif

    private func run(_ arguments: [String], input: some InputProtocol) async throws(SOPError) -> String {
        guard FileManager.default.isExecutableFile(atPath: executable.path()) else { throw .notInstalled }
        let result: ExecutionResult<Void, StringOutput<UTF8>, StringOutput<UTF8>>
        do {
            result = try await Subprocess.run(
                .path(FilePath(executable.path())), arguments: Arguments(arguments), input: input,
                output: .string(limit: Command.limit), error: .string(limit: Command.limit))
        } catch {
            throw Task.isCancelled ? .cancelled : .failed(subcommand: arguments[0], failure: .other(-1), stderr: String(describing: error))
        }
        if Task.isCancelled { throw .cancelled }
        try Self.check(result.terminationStatus, arguments[0], result.standardError ?? "")
        return result.standardOutput ?? ""
    }

    private static func check(_ status: TerminationStatus, _ subcommand: String, _ stderr: String) throws(SOPError) {
        switch status {
        case .exited(0): return
        case .exited(let code): throw .failed(subcommand: subcommand, failure: SOPFailure(exitCode: code), stderr: stderr)
        default: throw .failed(subcommand: subcommand, failure: .other(-1), stderr: stderr)
        }
    }
}

/// A master key that makes RFC 9980 algorithm ID 30 signatures. The
/// hardware key is the conformance the key ceremony adds (#12); until then
/// only the software key of the tests conforms.
public protocol ID30Signer: Sendable {
    /// The key's public certificate, as `keys/` holds it.
    var certificate: String { get }

    /// A detached ID 30 text signature over `text`, armored.
    func textSignature(_ text: String) async throws(SOPError) -> String
}

extension ID30Signer {
    /// The key's fingerprint, when its certificate reads.
    public var fingerprint: String? { (try? Certificate(armored: certificate))?.primary.fingerprintHex }

    /// The licence file for `document`, the canonical licence JSON: a text
    /// signature over it without its final line break, framed as a cleartext
    /// signature with the certificate.
    public func token(for document: String) async throws(SOPError) -> String {
        let text = document.hasSuffix("\n") ? String(document.dropLast()) : document
        return Token.cleartext(text, signature: try await textSignature(text), certificate: certificate)
    }
}

#if DEBUG
    /// Tests only: a software ID 30 key in a throwaway file, signed with by
    /// `ferrohealth-sop`. Debug builds alone compile it.
    struct SoftwareID30Key: ID30Signer {
        let sop: SOP
        let keys: URL
        let certificate: String

        func textSignature(_ text: String) async throws(SOPError) -> String { try await sop.sign(text, keys: keys) }
    }
#endif
