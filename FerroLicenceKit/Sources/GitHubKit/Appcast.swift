import Foundation

/// The two things the app reads from a Sparkle appcast: the build number and
/// the archive.
public enum Appcast {
    /// The highest `sparkle:version` (the build number) in the feed.
    public static func build(_ feed: String) -> Int? {
        let element = feed.matches(of: /<sparkle:version>(\d+)<\/sparkle:version>/).compactMap { Int($0.1) }
        let attribute = feed.matches(of: /sparkle:version="(\d+)"/).compactMap { Int($0.1) }
        return (element + attribute).max()
    }

    /// The first enclosure's address.
    public static func enclosure(_ feed: String) -> String? {
        feed.firstMatch(of: /<enclosure[^>]*\surl="([^"]+)"/).map { String($0.1) }
    }
}
