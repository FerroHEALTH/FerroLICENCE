import Foundation
import Testing

@testable import Signing

@Suite("Reading GnuPG's listings")
struct Listings {
    // `gpg --card-status --with-colons` for a YubiKey 5 after setup.
    let ready = """
        Reader:Yubico YubiKey OTP FIDO CCID 00 00:AID:D2760001240100000006407295020000:openpgp-card
        version:0304:
        vendor:0006:Yubico:
        serial:40729502:
        name:::
        lang::
        sex:u:
        url::
        login::
        forcepin:1:::
        keyattr:1:22:ed25519:
        keyattr:2:18:cv25519:
        keyattr:3:22:ed25519:
        maxpinlen:127:127:127:
        pinretry:3:0:3:
        sigcount:12:::
        kdf:off:
        uif:1:0:0:
        cafpr::::
        fpr:F2D214FC30698BA65A846B2BF2EA48D4C316406D:0000000000000000000000000000000000000000:0000000000000000000000000000000000000000:
        fprtime:1791331200:0:0:
        """

    @Test func readsACardThatIsReady() throws {
        let card = try #require(CardStatus(colons: ready))
        #expect(card.serial == "40729502")
        #expect(card.vendor == "Yubico")
        #expect(card.signatureKey == "F2D214FC30698BA65A846B2BF2EA48D4C316406D")
        #expect(card.pinEverySignature)
        #expect(card.touchToSign == true)
        #expect(card.curve25519)
        #expect(card.pinTriesLeft == 3)
        #expect(card.signaturesMade == 12)
    }

    @Test func readsABlankCard() throws {
        let blank = ready.replacingOccurrences(of: "forcepin:1", with: "forcepin:0")
            .replacingOccurrences(of: "uif:1:", with: "uif:0:")
            .replacingOccurrences(of: "keyattr:1:22:ed25519:", with: "keyattr:1:1:2048:")
            .replacingOccurrences(of: "F2D214FC30698BA65A846B2BF2EA48D4C316406D", with: String(repeating: "0", count: 40))
        let card = try #require(CardStatus(colons: blank))
        #expect(card.signatureKey == nil)
        #expect(!card.pinEverySignature)
        #expect(card.touchToSign == false)
        #expect(!card.curve25519)
    }

    @Test func noSerialIsNoCard() { #expect(CardStatus(colons: "version:0304:\n") == nil) }

    @Test func listsOnlyKeysOnACard() {
        let listing = """
            sec:u:255:22:2BF2EA48D4C316406D:1791331200:::u:::scSC:::D2760001240100000006407295020000::ed25519:::0:
            fpr:::::::::F2D214FC30698BA65A846B2BF2EA48D4C316406D:
            sec:u:255:22:AAAA:1791331200:::u:::scSC:::+::ed25519:::0:
            fpr:::::::::1111111111111111111111111111111111111111:
            sec:u:255:22:BBBB:1791331200:::u:::scSC:::#::ed25519:::0:
            fpr:::::::::2222222222222222222222222222222222222222:
            """
        let keys = CardKey.parse(listing)
        #expect(keys == [CardKey(fingerprint: "F2D214FC30698BA65A846B2BF2EA48D4C316406D", card: "D2760001240100000006407295020000")])
        #expect(keys.first?.serial == "40729502")
    }

    @Test func readsAPrimaryThatMayIssue() throws {
        let listing = """
            pub:u:255:22:F2EA48D4C316406D:1791331200:::u:::scSC:::::ed25519:::0:
            fpr:::::::::F2D214FC30698BA65A846B2BF2EA48D4C316406D:
            """
        let key = try #require(PublicPrimary.parse(listing))
        #expect(key.canIssue)
        #expect(!(PublicPrimary.parse(listing.replacingOccurrences(of: "pub:u:", with: "pub:r:"))?.canIssue ?? true))
    }
}

@Suite("Answering gpg --card-edit")
struct CardEditAnswers {
    func answers(_ lines: [String], commands: [String]) -> [CardEdit.Answer] {
        var remaining = commands
        return lines.map {
            CardEdit.answer("[GNUPG:] \($0)", commands: &remaining, name: "FerroHEALTH Licensing", email: "licensing@FerroHEALTH.eu")
        }
    }

    @Test func generatesAnEd25519KeyWithNoExpiryAndNoBackup() {
        let questions = [
            "GET_LINE cardedit.prompt", "GET_LINE cardedit.prompt", "GET_LINE cardedit.genkeys.algo", "GET_LINE keygen.curve",
            "GET_LINE cardedit.genkeys.backup_enc", "GET_LINE keygen.valid", "GET_LINE keygen.name", "GET_LINE keygen.email",
            "GET_LINE keygen.comment", "GET_LINE cardedit.prompt",
        ]
        #expect(
            answers(questions, commands: ["admin", "generate"]) == [
                .line("admin"), .line("generate"), .line("2"), .line("1"), .line("n"), .line("0"),
                .line("FerroHEALTH Licensing"), .line("licensing@FerroHEALTH.eu"), .line(""), .line("quit"),
            ])
    }

    @Test func ignoresStatusLinesThatAskNothing() {
        #expect(answers(["PINENTRY_LAUNCHED 1234", "KEY_CREATED B F2D2", "CARDCTRL 3 D276"], commands: []) == [.none, .none, .none])
    }

    @Test func stopsAtAnUnknownQuestion() {
        #expect(answers(["GET_LINE cardedit.something_new"], commands: []) == [.stop])
        #expect(answers(["GET_HIDDEN passphrase.enter"], commands: []) == [.stop])
    }
}

@Suite("Setting up a YubiKey")
struct SetupTests {
    @Test func agentConfNeedsAWindowAndNoKeychain() {
        #expect(!AgentConf.isSet(""))
        #expect(!AgentConf.isSet("pinentry-program /opt/homebrew/bin/pinentry-tty\nno-allow-external-cache\n"))
        #expect(AgentConf.isSet("pinentry-program /opt/homebrew/bin/pinentry-mac\nno-allow-external-cache\n"))
    }

    @Test func agentConfKeepsWhatIsThere() {
        let conf = AgentConf.adding(to: "default-cache-ttl 60", pinentry: "/opt/homebrew/bin/pinentry-mac")
        #expect(conf == "default-cache-ttl 60\npinentry-program /opt/homebrew/bin/pinentry-mac\nno-allow-external-cache\n")
        #expect(AgentConf.adding(to: conf, pinentry: "/x") == conf)
    }

    @Test func resumesAtTheFirstStepNotDone() throws {
        let card = try #require(CardStatus(colons: "serial:40729502:\nforcepin:1:::\n"))
        let probe = SetupProbe(card: card, agentConfigured: true, trusted: false, pinsChanged: true)
        #expect(probe.current == .createKey)
        #expect(SetupProbe(card: nil, agentConfigured: true, trusted: false, pinsChanged: false).current == .checkCard)
    }

    @Test func describesStatusLinesInWords() {
        #expect(describeStatus("[GNUPG:] PINENTRY_LAUNCHED 123 curses").map { String(localized: $0) } == "A window asks for a PIN.")
        #expect(describeStatus("[GNUPG:] SC_OP_FAILURE 2").map { String(localized: $0).hasPrefix("Wrong PIN") } == true)
        #expect(describeStatus("gpg: card-edit") == nil)
    }

    @Test func describesAWrongPIN() {
        #expect(GnuPGError.failed(arguments: ["--clearsign"], stderr: "gpg: signing failed: Bad PIN").description.hasPrefix("Wrong PIN"))
    }

    @Test(arguments: [(3, "Wrong PIN. 3 tries left."), (1, "Wrong PIN. 1 try left before the PIN is blocked.")])
    func saysHowManyTriesAreLeft(_ tries: Int, _ sentence: String) { #expect(String(localized: wrongPIN(triesLeft: tries)) == sentence) }

    @Test func aBlockedPINSaysHowToUnblockIt() {
        #expect(String(localized: wrongPIN(triesLeft: 0)).contains("Admin PIN"))
        #expect(GnuPGError.failed(arguments: ["--clearsign"], stderr: "gpg: signing failed: Bad PIN").isBadPIN)
        #expect(!GnuPGError.cancelled.isBadPIN)
    }
}
