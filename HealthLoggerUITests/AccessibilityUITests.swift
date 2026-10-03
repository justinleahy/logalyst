import XCTest

/// Accessibility audits (VoiceOver descriptions, hit areas, contrast, Dynamic Type and clipped text) of the screens
/// 1.1 adds or changes, at the default text size and the largest accessibility size.
@MainActor
final class AccessibilityUITests: XCTestCase {
    private var app: XCUIApplication!
    private let tag = String(UUID().uuidString.prefix(4))

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
    }

    func testNewScreensAtTheDefaultTextSize() throws {
        app.launch()
        try auditFoodScreens()
    }

    /// At the largest size, without typing (text fields at that size are covered by the default-size run): an empty
    /// food editor, a saved food's editor offering its stated weight, a weighed food, and the meal screen.
    func testNewScreensAtTheLargestTextSize() throws {
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.tabBars.buttons["Nutrition"].tap()
        let addFood = app.buttons["Add Food"].firstMatch
        scrollUntilHittable(addFood)
        addFood.tap()

        let menu = app.navigationBars["Add Food"].buttons["New Food"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let menuFrame = menu.frame
        menu.tap()
        app.buttons.matching(identifier: "New Food").allElementsBoundByIndex
            .last { $0.isHittable && $0.frame != menuFrame }!.tap()
        try audit("Food editor, largest text")
        app.navigationBars.buttons["Cancel"].tap()

        // A food saved with a serving size in grams but no weight, as before 1.1, offers it.
        let unweighed = app.buttons.matching(NSPredicate(format: "label CONTAINS ' g)' AND NOT (label CONTAINS ' · 0')"))
        scrollUntilHittable(unweighed.firstMatch)
        if unweighed.firstMatch.exists {
            unweighed.firstMatch.swipeLeft()
            app.buttons["Edit"].tap()
            try audit("Food editor with a stated weight, largest text")
            app.navigationBars.buttons["Cancel"].tap()
        }

        // A food with a serving weight, entered in grams. (Made by the other tests.)
        let search = app.searchFields["Search Foods and Recipes"]
        var tries = 0
        while !search.exists && tries < 40 {
            app.swipeDown(velocity: .fast)
            tries += 1
        }
        search.tap()
        app.typeText("Granola")
        let weighed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Granola'")).firstMatch
        XCTAssertTrue(weighed.waitForExistence(timeout: 3))
        weighed.tap()
        let grams = app.segmentedControls.buttons["Grams"]
        if grams.waitForExistence(timeout: 3) { grams.tap() }
        try audit("Log food by weight, largest text")
        // Tapping the current tab again goes back to its first screen.
        app.tabBars.buttons["Nutrition"].tap()
        app.tabBars.buttons["Nutrition"].tap()

        let newMeal = app.buttons["New Meal"].firstMatch
        scrollUntilHittable(newMeal)
        newMeal.tap()
        try audit("Pick foods for a meal, largest text")
        app.buttons.matching(NSPredicate(format: "label CONTAINS ' kcal'")).firstMatch.tap()
        app.buttons["Next (1)"].tap()
        try audit("Meal screen, largest text")
    }

    /// C5's screens, with the Debug stubs for the photo and the lookup: the photo with a brand, the branded meal
    /// screen with its prompts and sources, and the brand's foods to pick from.
    func testRestaurantLookupScreens() throws {
        try auditLookupScreens(arguments: [])
    }

    func testRestaurantLookupScreensAtTheLargestTextSize() throws {
        try auditLookupScreens(arguments: ["-UIPreferredContentSizeCategoryName",
                                           "UICTContentSizeCategoryAccessibilityXXXL"],
                               suffix: ", largest text")
    }

    func testFailedRestaurantLookup() throws {
        app.launchArguments = ["-StubMealPhoto", "YES", "-StubNutritionLookup", "rateLimited"]
        app.launch()
        openPhotoOfMeal()
        type("Chipotle", into: app.textFields["Restaurant or Brand"])
        app.buttons["Look Up Nutrition"].tap()
        XCTAssertTrue(app.navigationBars["Chipotle Meal"].waitForExistence(timeout: 10))
        try audit("Failed restaurant lookup")
    }

    private func auditLookupScreens(arguments: [String], suffix: String = "") throws {
        app.launchArguments = ["-StubMealPhoto", "YES", "-StubNutritionLookup", "ok"] + arguments
        app.launch()
        openPhotoOfMeal()
        try audit("Photo of meal" + suffix)
        type("Chipotle", into: app.textFields["Restaurant or Brand"])
        try audit("Photo of meal with a brand" + suffix)
        let lookUp = app.buttons["Look Up Nutrition"]
        scrollUntilHittable(lookUp)
        lookUp.tap()
        XCTAssertTrue(app.navigationBars["Chipotle Meal"].waitForExistence(timeout: 10))
        try audit("Branded meal" + suffix)
        let sources = app.staticTexts["Sources"]
        scrollUntilHittable(sources)
        try audit("Branded meal sources" + suffix)

        let replace = app.staticTexts["Lime Wedge"]
        var tries = 0
        while !replace.isHittable && tries < 20 {
            app.swipeDown(velocity: .slow)
            tries += 1
        }
        replace.swipeLeft()
        app.buttons["Replace"].tap()
        XCTAssertTrue(app.navigationBars["Replace Lime Wedge"].waitForExistence(timeout: 3))
        try audit("Brand's foods to pick from" + suffix)
    }

    private func openPhotoOfMeal() {
        app.tabBars.buttons["Nutrition"].tap()
        let photo = app.buttons["Photo of Meal"].firstMatch
        scrollUntilHittable(photo)
        photo.tap()
        let test = app.buttons["Use Test Photo"]
        XCTAssertTrue(test.waitForExistence(timeout: 3))
        scrollUntilHittable(test)
        test.tap()
    }

    private func auditFoodScreens() throws {
        let name = "Oats \(tag)"
        app.tabBars.buttons["Nutrition"].tap()
        let addFood = app.buttons["Add Food"].firstMatch
        scrollUntilHittable(addFood)
        addFood.tap()

        // The food editor, with its serving weight.
        let menu = app.navigationBars["Add Food"].buttons["New Food"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let menuFrame = menu.frame
        menu.tap()
        app.buttons.matching(identifier: "New Food").allElementsBoundByIndex
            .last { $0.isHittable && $0.frame != menuFrame }!.tap()
        type(name, into: app.textFields["Name"])
        type("1/2 cup (40 g)", into: app.textFields["Serving Size"])
        let use = app.buttons["Use 40 g from Serving Size"]
        scrollUntilHittable(use)
        try audit("Food editor")
        use.tap()
        type("150", into: app.textFields["Calories in kcal"])
        app.navigationBars.buttons["Save"].tap()

        // Logging it by weight.
        let rows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name))
        var tries = 0
        while !(rows.count > 0 && rows.element(boundBy: rows.count - 1).isHittable) && tries < 20 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        rows.element(boundBy: rows.count - 1).tap()
        app.segmentedControls.buttons["Grams"].tap()
        try audit("Log food by weight")
        // Tapping the current tab again goes back to its first screen.
        app.tabBars.buttons["Nutrition"].tap()
        app.tabBars.buttons["Nutrition"].tap()

        // Starting a meal, and the meal screen.
        let newMeal = app.buttons["New Meal"].firstMatch
        scrollUntilHittable(newMeal)
        newMeal.tap()
        try audit("Pick foods for a meal")
        let search = app.searchFields["Search My Foods"]
        type(name, into: search)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch.tap()
        let close = app.buttons.allElementsBoundByIndex.first {
            ["close", "cancel"].contains($0.label.lowercased()) && abs($0.frame.midY - search.frame.midY) < 30
        }
        close?.tap()
        app.buttons["Next (1)"].tap()
        try audit("Meal screen")
    }

    /// Labels of the elements 1.1 adds. Issues elsewhere (system bars and footers, and screens 1.1 didn't change)
    /// are outside this check.
    private static let newElements = [
        "from Serving Size", "Serving Weight in grams", "With a serving weight", "One serving weighs", "Servings",
        "Grams", "Ounces", "Weight", "Grams of", "Servings of", "Ounces of", "Unit for", "Add Food", "Replace",
        "New Meal", "Next", "Add (", "Set a food to 0",
        // C5
        "Your photo", "Restaurant or Brand", "Meal Details", "Look Up Nutrition", "Estimate Nutrition",
        "Choose Another", "Retake", "Stop", "Logalyst finds", "Add a restaurant", "Choose which", "Include ",
        "Published", "Estimate", "Which is it", "Was it there", "From your details", "Not in ", "Usually under",
        "Not counted", "Couldn't Look Up", "The website is busy", "Try Again", "Until then", "Sources",
        "test data", "Search Chipotle", "Chipotle", "Foods marked",
    ]

    /// Audits a screen. Fails on missing descriptions, small hit areas, undetectable elements or wrong traits in an
    /// element 1.1 adds. Contrast, Dynamic Type and clipping findings are attached for review against the screenshot
    /// instead: the audit reports them for system styles too (secondary footers, the tint, disabled bar buttons) and
    /// for text a screenshot shows whole.
    private func audit(_ screen: String) throws {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = screen
        shot.lifetime = .keepAlways
        add(shot)
        var forReview: [String] = []
        let failing: XCUIAccessibilityAuditType = [.sufficientElementDescription, .hitRegion, .elementDetection, .trait]
        try app.performAccessibilityAudit { issue in
            guard let element = issue.element,
                  Self.newElements.contains(where: { element.label.contains($0) }) else { return true }
            if failing.contains(issue.auditType) {
                XCTFail("\(screen): \(issue.compactDescription) — \(element.debugDescription)")
            } else {
                forReview.append("\(issue.compactDescription): \(element.label)")
            }
            return true
        }
        let review = XCTAttachment(string: forReview.joined(separator: "\n"))
        review.name = "\(screen): findings to review"
        review.lifetime = .keepAlways
        add(review)
    }

    private func type(_ text: String, into field: XCUIElement) {
        scrollUntilHittable(field)
        field.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { field.tap() }
        app.typeText(text)
    }

    private func scrollUntilHittable(_ element: XCUIElement) {
        var tries = 0
        while !(element.exists && element.isHittable) && tries < 60 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
    }
}
