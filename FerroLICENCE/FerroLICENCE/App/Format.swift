import Foundation
import GitHubKit
import LicenceCore
import Register
import Signing
import SwiftUI

extension CivilDate {
    /// `December 2024`, in the reader's language.
    var monthAndYear: String {
        start.formatted(Date.FormatStyle(timeZone: .gmt).month(.wide).year())
    }
}

/// `1 Dec 2025 – 30 Nov 2026`, in the reader's language.
func span(_ licence: Licence) -> LocalizedStringResource {
    "\(licence.notBefore) – \(licence.notAfter)"
}

/// A licence's standing as one filled symbol, its colour and a short line.
struct StandingLook {
    let symbol: String
    let color: Color
    let line: LocalizedStringResource

    init(_ standing: Standing, use: Use, brief: Bool = false) {
        switch standing {
        case .inForce(let until, let left) where left <= LicenceRegister.endingSoonDays:
            self.init(
                "exclamationmark.triangle.fill", .orange,
                left == 0 ? "Ends today" : brief ? "Ends in \(left) days" : "Ends in \(left) days · \(until)")
        case .inForce(let until, _):
            self.init(
                "checkmark.circle.fill", .green,
                use == .commercial ? "Valid until \(until)" : "Free licence until \(String(until.year))")
        case .upcoming(let starts): self.init("clock.fill", .secondary, "Starts \(starts)")
        case .ended(let on, _): self.init("minus.circle.fill", .secondary, "Ended \(on)")
        case .revoked(let from): self.init("xmark.octagon.fill", .red, "Revoked \(from)")
        }
    }

    init(_ symbol: String, _ color: Color, _ line: LocalizedStringResource) {
        self.symbol = symbol
        self.color = color
        self.line = line
    }
}

extension Use {
    /// The use inside a sentence: "commercial" or "free".
    var inSentence: LocalizedStringResource {
        switch self {
        case .commercial: "commercial"
        case .nonCommercial: "free"
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .commercial: "Commercial"
        case .nonCommercial: "Free"
        }
    }
}

/// The licensee as a short name for lists: the free licence reads as `Everyone (BUSL 1.1)`.
func shortName(_ licensee: String) -> String {
    licensee == "Everyone, under the Business Source License 1.1" ? "Everyone (BUSL 1.1)" : licensee
}

/// `2026-10-23` in a sentence written by GitHub, as the screens print a day,
/// joined by no-break spaces so a date never wraps.
func humanDates(_ text: String) -> String {
    text.replacing(/\d{4}-\d{2}-\d{2}/) { match in
        CivilDate(match.output).map {
            $0.start.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
                .replacingOccurrences(of: " ", with: "\u{00A0}")
        } ?? String(match.output)
    }
}

/// Where a key lives, as `signers.json` records it: a YubiKey and its serial
/// reads the same in every language; the retired key's `software key` is
/// translated.
func medium(_ medium: String) -> LocalizedStringResource {
    medium == "software key" ? "software key" : "\(medium)"
}

/// A merged pull request's title (written in English by the app, for the
/// audit record) as a sentence of the register's history.
func activitySentence(_ title: String) -> LocalizedStringResource {
    if let m = title.wholeMatch(of: /Licence for (.+) until (\d{4}-\d{2}-\d{2})/), let day = CivilDate(m.2) {
        return "\(shortName(String(m.1))) licensed until \(day)"
    }
    if let m = title.wholeMatch(of: /Renew (.+) until (\d{4}-\d{2}-\d{2})/), let day = CivilDate(m.2) {
        return "\(shortName(String(m.1))) renewed until \(day)"
    }
    if let m = title.wholeMatch(of: /Revoke (.+) from (\d{4}-\d{2}-\d{2})/), let day = CivilDate(m.2) {
        return "\(shortName(String(m.1))) revoked from \(day)"
    }
    if let m = title.wholeMatch(of: /Trust the master keys of (.+) and (.+)/) {
        return "The keys of \(String(m.1)) and \(String(m.2)) trusted"
    }
    if let m = title.wholeMatch(of: /Trust the master key of (.+)/) {
        return "The key of \(String(m.1)) trusted"
    }
    if let m = title.wholeMatch(of: /Retire the key of (.+)/) {
        return "The key of \(String(m.1)) retired"
    }
    if let m = title.wholeMatch(of: /Mark the key of (.+) as lost/) {
        return "The key of \(String(m.1)) marked as lost"
    }
    if let m = title.wholeMatch(of: /Mark the key of (.+) as handed over/) {
        return "The key of \(String(m.1)) handed over"
    }
    return "\(humanDates(title))"
}

/// What a person reads for an error: the kit's own message where it has
/// one, otherwise the error's description.
func message(_ error: any Error) -> LocalizedStringResource {
    switch error {
    case let e as GnuPGError: e.message
    case let e as NoSigningKey: e.message
    case let e as GitHubError: e.message
    case let e as AuthError: e.message
    case let e as RegisterError: e.message
    case let e as RecordingError: e.message
    case let e as PreparationError: e.message
    case let e as RegisterCheck.Refused: e.message
    default: "\(String(describing: error))"
    }
}
