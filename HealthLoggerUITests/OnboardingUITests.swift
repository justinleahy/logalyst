import XCTest

/// Onboarding (optional 1.1 addition): shown once on a new iPhone, skippable, and not shown to people upgrading.
@MainActor
final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Every step, with an accessibility audit of each, then the app; and it doesn't come back.
    func testWalkThroughOnboarding() throws {
        app.launchArguments = ["-ShowOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to Logalyst"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Step 1 of 4"].exists)
        try audit("Onboarding: welcome")
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Your Favorites"].waitForExistence(timeout: 5))
        let temperature = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Body Temperature'")).firstMatch
        let wasFavorite = temperature.isSelected
        temperature.tap()
        XCTAssertNotEqual(temperature.isSelected, wasFavorite)
        try audit("Onboarding: favorites")
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Daily Goals"].waitForExistence(timeout: 3))
        try audit("Onboarding: goals")
        app.buttons["Review Goals"].tap()
        XCTAssertTrue(app.navigationBars["Daily Goals"].waitForExistence(timeout: 3))
        app.navigationBars["Daily Goals"].buttons["Done"].tap()
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Reminders to Log"].waitForExistence(timeout: 3))
        try audit("Onboarding: reminders")
        app.buttons["Set Up Reminders"].tap()
        XCTAssertTrue(app.navigationBars["Log Reminders"].waitForExistence(timeout: 3))
        app.navigationBars["Log Reminders"].buttons["Done"].tap()
        app.buttons["Done"].tap()

        // The app, with the favorite changed.
        XCTAssertTrue(app.navigationBars["Log Health Data"].waitForExistence(timeout: 5))
        let favorites = app.buttons.matching(identifier: "Body Temperature").count
        XCTAssertEqual(favorites, wasFavorite ? 1 : 2, "Body Temperature should be listed under Favorites as well")

        // Put the favorite back, from the Log list.
        let row = app.buttons["Body Temperature"].firstMatch
        row.swipeRight()
        app.buttons[wasFavorite ? "Favorite" : "Unfavorite"].tap()

        // Finished, so it doesn't come back.
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.navigationBars["Log Health Data"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Welcome to Logalyst"].exists)
    }

    func testSkipOnboarding() throws {
        app.launchArguments = ["-ShowOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to Logalyst"].waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.navigationBars["Log Health Data"].waitForExistence(timeout: 5))
    }

    /// On a simulator where Logalyst is new: no favorites, goals or foods, and Health not asked yet. (Elsewhere it's
    /// skipped.) Health isn't asked for here either, since a test can't answer its sheet on every simulator.
    func testANewUserSeesOnboarding() throws {
        app.launchArguments = ["-SkipHealthAuthorization", "YES", "-onboardingFinished", "NO"]
        app.launch()
        let welcome = app.staticTexts["Welcome to Logalyst"]
        if !welcome.waitForExistence(timeout: 5) {
            throw XCTSkip("Logalyst has been used on this simulator already, so it's treated as someone upgrading.")
        }
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.navigationBars["Log Health Data"].waitForExistence(timeout: 5))
    }

    /// Fails on missing descriptions, small hit areas, undetectable elements or wrong traits. Contrast, Dynamic Type
    /// and clipping findings are attached for review against the screenshot.
    private func audit(_ screen: String) throws {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = screen
        shot.lifetime = .keepAlways
        add(shot)
        var forReview: [String] = []
        let failing: XCUIAccessibilityAuditType = [.sufficientElementDescription, .hitRegion, .elementDetection, .trait]
        try app.performAccessibilityAudit { issue in
            let label = issue.element?.label ?? "no element"
            if failing.contains(issue.auditType) {
                XCTFail("\(screen): \(issue.compactDescription) — \(label)")
            } else {
                forReview.append("\(issue.compactDescription): \(label)")
            }
            return true
        }
        let review = XCTAttachment(string: forReview.joined(separator: "\n"))
        review.name = "\(screen): findings to review"
        review.lifetime = .keepAlways
        add(review)
    }
}
