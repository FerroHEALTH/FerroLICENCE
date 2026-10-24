import XCTest

/// The screenshot tour, through XCUITest so Liquid Glass is drawn as people
/// see it. It runs only when asked: scripts/ui/screenshots.sh sets
/// TEST_RUNNER_FL_TOUR=1 and, optionally, the screens, appearances, sizes
/// and extra launch arguments.
@MainActor
final class TourTests: XCTestCase {
    static let allScreens =
        "signIn ready customers draft check sign recording recorded revoke activity checkFile attest keys stopKey trustKey setup sync settings menus"

    func testTour() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["FL_TOUR"] == "1", "The tour runs from scripts/ui/screenshots.sh")
        let screens = (env["FL_TOUR_SCREENS"].flatMap { $0.isEmpty ? nil : $0 } ?? Self.allScreens).split(separator: " ")
        let appearances = (env["FL_TOUR_APPEARANCES"] ?? "light dark").split(separator: " ")
        let sizes = (env["FL_TOUR_SIZES"] ?? "860x560 1280x800").split(separator: " ")
        let extra = (env["FL_TOUR_EXTRA"] ?? "").split(separator: " ").map(String.init)
        for screen in screens {
            if screen == "menus" {
                for appearance in appearances { photographMenus(appearance: String(appearance), extra: extra) }
                continue
            }
            for appearance in appearances {
                for size in sizes {
                    let app = XCUIApplication()
                    app.launchArguments =
                        [
                            "-FLFixtures", "YES", "-FLScreen", String(screen), "-FLAppearance", String(appearance),
                            "-FLWindowSize", String(size), "-ApplePersistenceIgnoreState", "YES",
                        ] + extra
                    app.launch()
                    _ = XCTWaiter.wait(for: [XCTestExpectation(description: "the screen settles")], timeout: 3)
                    // The window the screen is about: setup and Settings open their
                    // own; every other screen is the main window.
                    let window: XCUIElement =
                        switch screen {
                        case "setup": app.windows["setup"].firstMatch
                        case "settings": app.windows.matching(NSPredicate(format: "identifier CONTAINS[c] 'settings'")).firstMatch
                        // With a sheet open, the window cannot be photographed; the
                        // sheet itself can.
                        case "draft", "check", "sign", "recording", "recorded", "revoke", "stopKey", "trustKey": app.sheets.firstMatch
                        default: app.windows["main"].firstMatch
                        }
                    XCTAssertTrue(window.waitForExistence(timeout: 5), "\(screen) shows its window")
                    let sheets: Set = ["draft", "check", "sign", "recording", "recorded", "revoke", "stopKey", "trustKey"]
                    let title = String(
                        screen == "settings" ? "Settings" : screen == "setup" ? "Setup" : sheets.contains(String(screen)) ? "Sheet" : "Main"
                    )
                    let shot = XCTAttachment(screenshot: window.screenshot())
                    shot.name = "\(screen)-\(appearance)-\(size)--\(title)"
                    shot.lifetime = .keepAlways
                    add(shot)
                    app.terminate()
                }
            }
        }
    }

    /// Every menu of the menu bar but Apple's, opened on a customer, so the
    /// commands are read where they sit, enabled or not.
    func photographMenus(appearance: String, extra: [String]) {
        let app = XCUIApplication()
        app.launchArguments =
            [
                "-FLFixtures", "YES", "-FLScreen", "customers", "-FLAppearance", appearance, "-ApplePersistenceIgnoreState", "YES",
            ] + extra
        app.launch()
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 10), "the main window opens")
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "the screen settles")], timeout: 3)
        let items = app.menuBars.firstMatch.menuBarItems
        for index in 1..<items.count {
            let item = items.element(boundBy: index)
            item.click()
            let menu = item.menus.firstMatch
            guard menu.waitForExistence(timeout: 3) else { continue }
            let shot = XCTAttachment(screenshot: menu.screenshot())
            shot.name = "menus-\(appearance)-\(index)--\(item.title)"
            shot.lifetime = .keepAlways
            add(shot)
            app.typeKey(.escape, modifierFlags: [])
        }
        app.terminate()
    }
}
