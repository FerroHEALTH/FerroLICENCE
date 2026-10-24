import Foundation
import GitHubKit
import Testing

@Suite("Reading the update feed")
struct AppcastTests {
    // As generate_appcast writes it.
    let feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>FerroLICENCE</title>
            <item>
              <title>0.3.0</title>
              <sparkle:version>58</sparkle:version>
              <sparkle:shortVersionString>0.3.0</sparkle:shortVersionString>
              <sparkle:minimumSystemVersion>27.0</sparkle:minimumSystemVersion>
              <enclosure url="https://github.com/FerroHEALTH/FerroLICENCE/releases/download/v0.3.0/FerroLICENCE-0.3.0.zip" length="9123456" type="application/octet-stream" sparkle:edSignature="c2lnbmF0dXJl"/>
            </item>
          </channel>
        </rss>
        """

    @Test func readsTheBuildNumber() { #expect(Appcast.build(feed) == 58) }

    @Test func readsAnOlderAttributeStyleFeed() {
        #expect(Appcast.build(#"<enclosure sparkle:version="41" url="x.zip"/>"#) == 41)
    }

    @Test func findsTheArchive() {
        #expect(Appcast.enclosure(feed) == "https://github.com/FerroHEALTH/FerroLICENCE/releases/download/v0.3.0/FerroLICENCE-0.3.0.zip")
    }

    @Test func aFeedWithoutAnItemHasNoBuild() { #expect(Appcast.build("<rss/>") == nil) }
}
