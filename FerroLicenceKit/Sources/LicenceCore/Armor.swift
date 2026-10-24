public import Foundation

/// ASCII armor (RFC 9580 §6): base64 between BEGIN and END lines, with an
/// optional CRC-24 checksum line.
public enum Armor {
    /// Why an armored block could not be read.
    public enum Failure: Error, Equatable, Sendable {
        /// The BEGIN or END line is missing or names another kind of block.
        case frame
        /// The base64 body does not decode.
        case base64
        /// The checksum line does not match the data.
        case checksum
    }

    /// The bytes inside the armored block `text`, which must be a block of
    /// `kind` (`PGP SIGNATURE`, `PGP PUBLIC KEY BLOCK`).
    public static func decode(_ text: String, kind: String) throws(Failure) -> Data {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let begin = lines.firstIndex(of: "-----BEGIN \(kind)-----"),
            let end = lines[begin...].firstIndex(of: "-----END \(kind)-----")
        else { throw .frame }
        var body = Array(lines[(begin + 1)..<end])
        // Armor headers end at the first empty line, if there are any.
        if let blank = body.firstIndex(of: ""), body[..<blank].allSatisfy({ $0.contains(": ") }) {
            body.removeSubrange(...blank)
        }
        body.removeAll { $0.isEmpty }
        var checksum: String?
        if let last = body.last, last.hasPrefix("="), last.count == 5 {
            checksum = String(last.dropFirst())
            body.removeLast()
        }
        guard let data = Data(base64Encoded: body.joined()) else { throw .base64 }
        if let checksum {
            guard let expected = Data(base64Encoded: checksum), expected.count == 3 else { throw .checksum }
            let crc = crc24(data)
            let got = Data([UInt8(crc >> 16 & 0xFF), UInt8(crc >> 8 & 0xFF), UInt8(crc & 0xFF)])
            guard got == expected else { throw .checksum }
        }
        return data
    }

    /// `data` as an armored block of `kind`, with a checksum line.
    public static func encode(_ data: Data, kind: String) -> String {
        let crc = crc24(data)
        let sum = Data([UInt8(crc >> 16 & 0xFF), UInt8(crc >> 8 & 0xFF), UInt8(crc & 0xFF)]).base64EncodedString()
        let body = data.base64EncodedString(options: .lineLength64Characters)
            .replacingOccurrences(of: "\r\n", with: "\n")
        return "-----BEGIN \(kind)-----\n\n\(body)\n=\(sum)\n-----END \(kind)-----\n"
    }

    /// The CRC-24 of RFC 9580 §6.1.
    public static func crc24(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xB704CE
        for byte in data {
            crc ^= UInt32(byte) << 16
            for _ in 0..<8 {
                crc <<= 1
                if crc & 0x1000000 != 0 { crc ^= 0x1864CFB }
            }
        }
        return crc & 0xFFFFFF
    }
}
