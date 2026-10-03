import XCTest

/// Sets up presets on the iPhone for checking the Watch's preset buttons (C1) with a paired Watch simulator: six
/// water presets in mL, and none for Inhaler Use. Presets are edited on the iPhone and synced to the Watch.
@MainActor
final class WatchPresetUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testEditPresetsForTheWatch() throws {
        app.tabBars.buttons["Log"].tap()
        open("Water")
        app.segmentedControls.buttons["mL"].tap()
        let amount = app.textFields.firstMatch
        for preset in ["100", "150", "330", "750"] {
            let existing = app.buttons["\(preset) mL"]
            if existing.exists { continue }
            amount.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
            let current = amount.value as? String ?? ""
            app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2) + preset)
            let save = app.buttons["Save \(preset) mL as Preset"]
            XCTAssertTrue(save.waitForExistence(timeout: 3), "Missing \(save) in:\n\(app.debugDescription)")
            save.tap()
        }
        for preset in ["100", "150", "250", "330", "500", "750"] {
            XCTAssertTrue(app.buttons["\(preset) mL"].waitForExistence(timeout: 3), "Missing the \(preset) mL preset")
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Six water presets on iPhone"
        shot.lifetime = .keepAlways
        add(shot)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        open("Inhaler Use")
        let puff = app.buttons["1 puff"]
        if puff.waitForExistence(timeout: 3) {
            puff.press(forDuration: 1.2)
            app.buttons["Remove 1 puff"].tap()
        }
        XCTAssertFalse(app.buttons["1 puff"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Restore Default Presets"].exists)
    }

    private func open(_ metric: String) {
        let row = app.buttons[metric].firstMatch
        var tries = 0
        while !(row.exists && row.isHittable) && tries < 12 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        row.tap()
        XCTAssertTrue(app.navigationBars[metric].waitForExistence(timeout: 3))
    }
}
