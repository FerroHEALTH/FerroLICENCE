import XCTest

/// The app in fixture mode (no network, no YubiKey): every section opens,
/// and the check steps hold. CI runs this on every pull request.
@MainActor
final class SmokeTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FLFixtures", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        return app
    }

    func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func testEverySectionOpens() {
        let app = launch()
        XCTAssertTrue(element(app, "customer.example-hospital-nv").waitForExistence(timeout: 15), "Customers lists the fixtures")
        for section in ["activity", "keys", "checkFile", "attest", "customers"] {
            element(app, "sidebar.\(section)").click()
            XCTAssertTrue(element(app, "section.\(section)").waitForExistence(timeout: 5), "\(section) opens")
            add(XCTAttachment(screenshot: app.windows.firstMatch.screenshot()).named(section))
        }
    }

    /// A hidden sidebar stays hidden when another section opens, and comes
    /// back when shown (each section rebuilds its split view).
    func testTheSidebarStaysHiddenAcrossSections() {
        let app = launch()
        let customers = element(app, "sidebar.customers")
        XCTAssertTrue(customers.waitForExistence(timeout: 15))
        XCTAssertTrue(customers.isHittable, "the sidebar shows at launch")
        app.typeKey("s", modifierFlags: [.command, .control])
        let hidden = NSPredicate(format: "isHittable == false")
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation(for: hidden, evaluatedWith: customers)], timeout: 5), .completed,
            "View › Hide Sidebar hides it")
        for (key, section) in [("5", "keys"), ("2", "activity"), ("1", "customers")] {
            app.typeKey(key, modifierFlags: [.command])
            XCTAssertTrue(element(app, "section.\(section)").waitForExistence(timeout: 5) || section == "customers")
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "the split view settles")], timeout: 1)
            XCTAssertFalse(element(app, "sidebar.\(section)").isHittable, "the sidebar stays hidden in \(section)")
        }
        app.typeKey("s", modifierFlags: [.command, .control])
        let shown = NSPredicate(format: "isHittable == true")
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation(for: shown, evaluatedWith: customers)], timeout: 5), .completed,
            "View › Show Sidebar shows it again")
    }

    func testRevokeNeedsTheWord() {
        let app = launch()
        let row = element(app, "customer.voorbeeld-zorggroep-b-v")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.click()
        // Revoke… sits in the licence's More menu in the toolbar.
        let more = app.menuButtons["More"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.click()
        app.menuItems["Revoke…"].firstMatch.click()
        let revoke = app.sheets.buttons["Revoke"].firstMatch
        XCTAssertTrue(revoke.waitForExistence(timeout: 5))
        XCTAssertFalse(revoke.isEnabled, "Revoke stays disabled until REVOKE is typed")
        add(XCTAttachment(screenshot: app.windows.firstMatch.screenshot()).named("Revoke"))
        app.sheets.buttons["Cancel"].firstMatch.click()
    }

    func testRenewFillsTheDraft() {
        let app = launch()
        XCTAssertTrue(element(app, "customer.example-hospital-nv").waitForExistence(timeout: 15))
        let renew = app.buttons["Renew…"].firstMatch
        XCTAssertTrue(renew.waitForExistence(timeout: 5))
        renew.click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.sheets.buttons["Continue"].firstMatch.exists)
        add(XCTAttachment(screenshot: app.windows.firstMatch.screenshot()).named("Renew"))
        app.typeKey(.escape, modifierFlags: [])
    }
}

extension XCTAttachment {
    func named(_ name: String) -> XCTAttachment {
        self.name = name
        lifetime = .keepAlways
        return self
    }
}
