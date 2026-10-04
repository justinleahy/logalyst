import XCTest

/// C6/C7 checks through the food editor, meal review, recipe editor and Health re-logging.
@MainActor
final class FoodVolumeCoverageUITests: XCTestCase {
    private var app: XCUIApplication!
    private let tag = String(UUID().uuidString.prefix(5))

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch() {
        app.launch()
        if app.staticTexts["Welcome to Logalyst"].waitForExistence(timeout: 2) {
            app.buttons["Skip"].tap()
        }
        let selectAll = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Select All' OR label == 'Turn On All'")).firstMatch
        if selectAll.waitForExistence(timeout: 3) {
            selectAll.tap()
            for title in ["Continue", "All Recorded Data and Future Data", "Allow"] {
                let button = app.buttons[title].firstMatch
                if button.waitForExistence(timeout: 3) { scrollTo(button); button.tap() }
            }
        }
    }

    func testVolumeUnitsPreserveAmountAndZeroSurvivesSavingAndRelogging() {
        launch()
        let name = "Milk \(tag)"
        openLibrary()
        createFood(name, serving: "100 mL", nutrients: [("Calories in kcal", "60"), ("Protein in g", "0")],
                   confirmVolume: true)
        openFood(name)
        replace(app.textFields["Milliliters of \(name)"], with: "180")
        assertValue("dietaryEnergyConsumed", "108 kcal")
        assertValue("dietaryProtein", "0 g")
        assertValue("dietaryCarbohydrates", "Unavailable")

        selectVolumeUnit("U.S. fluid ounces")
        XCTAssertEqual(app.textFields["U.S. fluid ounces of \(name)"].value as? String, "6.09")
        assertValue("dietaryEnergyConsumed", "108 kcal")
        selectVolumeUnit("Imperial fluid ounces")
        XCTAssertEqual(app.textFields["Imperial fluid ounces of \(name)"].value as? String, "6.34")
        assertValue("dietaryEnergyConsumed", "108 kcal")
        selectVolumeUnit("Milliliters")
        XCTAssertEqual(app.textFields["Milliliters of \(name)"].value as? String, "180")
        app.navigationBars[name].buttons["Log"].tap()
        XCTAssertTrue(app.navigationBars[name].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 5))
        clearLibrarySearch()
        for _ in 0..<6 { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(app.staticTexts["180 mL · 108 kcal"].waitForExistence(timeout: 5))

        // Recents use the Health snapshot, including its volume and known zero.
        let recent = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        recent.tap()
        XCTAssertTrue(app.textFields["Milliliters of \(name)"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["Milliliters of \(name)"].value as? String, "180")
        assertValue("dietaryProtein", "0 g")
        assertValue("dietaryCarbohydrates", "Unavailable")
    }

    func testPartialSodiumCountsOnlyIncludedFoodsAndSurvivesRecipeSaving() {
        launch()
        let known = "Broth \(tag)"
        let firstMissing = "Rice \(tag)"
        let secondMissing = "Oil \(tag)"
        openLibrary()
        createFood(known, nutrients: [("Calories in kcal", "40"), ("Sodium in mg", "100")])
        createFood(firstMissing, nutrients: [("Calories in kcal", "20")])
        createFood(secondMissing, nutrients: [("Calories in kcal", "30")])
        startMeal([known, firstMissing, secondMissing])
        assertValue("dietarySodium", "100 mg")
        XCTAssertTrue(app.staticTexts["nutritionCoverage-dietarySodium"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Sodium unavailable for 2 ingredients'")).firstMatch.exists)
        assertValue("dietaryFiber", "Unavailable")

        let saveRecipe = app.buttons["Save as Recipe"]
        scrollTo(saveRecipe)
        saveRecipe.tap()
        XCTAssertTrue(app.navigationBars["New Recipe"].waitForExistence(timeout: 3))
        let recipeName = "Soup \(tag)"
        replace(app.textFields["Name"], with: recipeName)
        assertValue("dietarySodium", "100 mg")
        XCTAssertTrue(app.staticTexts["nutritionCoverage-dietarySodium"].exists)
        app.navigationBars["New Recipe"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["New Recipe"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["New Meal"].waitForExistence(timeout: 3))

        // A zero amount is left out; it cannot inflate missing ingredient counts.
        scrollBackTo(app.textFields["Servings of \(firstMissing)"])
        replace(app.textFields["Servings of \(firstMissing)"], with: "0")
        assertValue("dietarySodium", "100 mg")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Sodium unavailable for 1 ingredient'")).firstMatch.exists)
        scrollBackTo(app.textFields["Servings of \(secondMissing)"])
        replace(app.textFields["Servings of \(secondMissing)"], with: "0")
        assertValue("dietarySodium", "100 mg")
        XCTAssertFalse(app.staticTexts["nutritionCoverage-dietarySodium"].exists)

        // Cancel this meal, open the saved recipe, and check its persisted ingredient coverage.
        app.navigationBars["New Meal"].buttons.element(boundBy: 0).tap()
        waitUntilHittable(app.navigationBars["New Meal"].buttons["Cancel"])
        app.navigationBars["New Meal"].buttons["Cancel"].tap()
        openFood(recipeName)
        assertValue("dietarySodium", "100 mg")
        XCTAssertTrue(app.staticTexts["nutritionCoverage-dietarySodium"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Sodium unavailable for 2 ingredients'")).firstMatch.exists)
    }

    func testReplacingVolumeWithCountRequiresServingConfirmation() {
        launch()
        let drink = "Drink \(tag)"
        let replacement = "Bar \(tag)"
        openLibrary()
        createFood(drink, serving: "100 mL", nutrients: [("Calories in kcal", "30")], confirmVolume: true)
        createFood(replacement, serving: "1 bar", nutrients: [("Calories in kcal", "100")])
        startMeal([drink])
        replace(app.textFields["Milliliters of \(drink)"], with: "180")
        app.staticTexts[drink].firstMatch.swipeLeft()
        app.buttons["Replace"].tap()
        pickFood(replacement)
        XCTAssertTrue(app.navigationBars["Replace \(drink)"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["New Meal"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["New Meal"].buttons["Log"].isEnabled)
        let confirm = app.buttons["Confirm amount of \(replacement)"]
        XCTAssertTrue(confirm.exists)
        XCTAssertEqual(app.textFields["Servings of \(replacement)"].value as? String, "1")
        replace(app.textFields["Servings of \(replacement)"], with: "2")
        scrollTo(confirm)
        confirm.tap()
        XCTAssertTrue(app.navigationBars["New Meal"].buttons["Log"].isEnabled)
        assertValue("dietaryEnergyConsumed", "200 kcal")
    }

    /// Seeds once at the normal size, then reopens the same saved food and recipe at the largest size.
    /// No dependency on foods or recipes created by another test.
    func testVolumeAndCoverageAccessibilityAtDefaultAndLargestTextSizes() throws {
        launch()
        let drink = "Measured milk \(tag)"
        let ingredient = "Cereal \(tag)"
        let recipe = "Breakfast \(tag)"
        openLibrary()
        createFood(drink, serving: "100 mL", nutrients: [("Calories in kcal", "60"), ("Sodium in mg", "100")],
                   confirmVolume: true)
        createFood(ingredient, nutrients: [("Calories in kcal", "40")])

        openFood(drink)
        try auditVolumePicker("default text")
        app.navigationBars[drink].buttons.element(boundBy: 0).tap()
        startMeal([drink, ingredient])
        try auditC6C7("Meal volume controls, default text")
        assertValue("dietarySodium", "100 mg")
        XCTAssertTrue(app.staticTexts["nutritionCoverage-dietarySodium"].exists)
        try auditC6C7("Partial sodium, default text")

        let saveRecipe = app.buttons["Save as Recipe"]
        scrollTo(saveRecipe)
        saveRecipe.tap()
        XCTAssertTrue(app.navigationBars["New Recipe"].waitForExistence(timeout: 3))
        replace(app.textFields["Name"], with: recipe)
        app.navigationBars["New Recipe"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["New Recipe"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["New Meal"].waitForExistence(timeout: 3))

        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launch()
        openLibrary()
        openFood(drink)
        try auditVolumePicker("largest text")
        app.navigationBars[drink].buttons.element(boundBy: 0).tap()
        openFood(recipe)
        assertValue("dietarySodium", "100 mg")
        let partial = app.staticTexts["nutritionCoverage-dietarySodium"]
        scrollTo(partial)
        XCTAssertTrue(partial.exists)
        try auditC6C7("Saved recipe partial sodium, largest text")
    }

    private func auditVolumePicker(_ size: String) throws {
        let picker = app.buttons["portionUnitPicker"]
        scrollBackTo(picker)
        picker.tap()
        XCTAssertTrue(app.buttons["U.S. fluid ounces"].exists)
        XCTAssertTrue(app.buttons["Imperial fluid ounces"].exists)
        try auditC6C7("Distinct fluid ounce choices, \(size)")
        app.buttons["Imperial fluid ounces"].tap()
        try auditC6C7("Volume entry, \(size)")
    }

    /// Fails interaction/description defects in the changed controls. System-style visual findings remain
    /// attached beside the screenshot for inspection, matching the existing accessibility suite.
    private func auditC6C7(_ screen: String) throws {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = screen
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let labels = ["Volume", "volume", "Milliliters", "mL", "fluid ounces", "fl oz", "Unit for",
                      "Partial", "Unavailable", "unavailable", "coverage", "Sodium", "Confirm amount"]
        let identifiers = ["portionUnitPicker", "servingVolumeUnit", "nutritionValue-", "nutritionCoverage-",
                           "nutritionTotal-"]
        let failing: XCUIAccessibilityAuditType = [.sufficientElementDescription, .hitRegion, .elementDetection, .trait]
        var forReview: [String] = []
        try app.performAccessibilityAudit { issue in
            guard let element = issue.element,
                  labels.contains(where: { element.label.contains($0) })
                    || identifiers.contains(where: { element.identifier.hasPrefix($0) }) else { return true }
            if failing.contains(issue.auditType) {
                XCTFail("\(screen): \(issue.compactDescription) — \(element.debugDescription)")
            } else {
                forReview.append("\(issue.compactDescription): \(element.label)")
            }
            return true
        }
        let review = XCTAttachment(string: forReview.isEmpty ? "No visual findings reported." : forReview.joined(separator: "\n"))
        review.name = "\(screen): contrast, Dynamic Type and clipping findings to review"
        review.lifetime = .keepAlways
        add(review)
    }

    private func openLibrary() {
        app.tabBars.buttons["Nutrition"].tap()
        let add = app.buttons["Add Food"].firstMatch
        scrollThroughLongList(to: add)
        add.tap()
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 3))
    }

    private func createFood(_ name: String, serving: String = "1 serving", nutrients: [(String, String)],
                            confirmVolume: Bool = false) {
        let menu = app.navigationBars["Add Food"].buttons["New Food"]
        waitUntilHittable(menu)
        let frame = menu.frame
        menu.tap()
        waitUntilHittable(app.buttons["New Recipe"])
        let item = app.buttons.matching(identifier: "New Food").allElementsBoundByIndex
            .last { $0.isHittable && $0.frame != frame }
        XCTAssertNotNil(item)
        item?.tap()
        XCTAssertTrue(app.navigationBars["New Food"].waitForExistence(timeout: 3))
        replace(app.textFields["Name"], with: name)
        replace(app.textFields["Serving Size"], with: serving)
        if confirmVolume {
            let suggestion = app.buttons["Use 100 mL from Serving Size"]
            scrollTo(suggestion)
            suggestion.tap()
        }
        for (field, value) in nutrients { replace(app.textFields[field], with: value) }
        let save = app.navigationBars["New Food"].buttons["Save"]
        XCTAssertTrue(save.isEnabled, "A valid nutrient must enable Save while the input is focused.\n\(app.debugDescription)")
        save.tap()
        XCTAssertTrue(app.navigationBars["New Food"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 3))
        waitUntilHittable(menu)
    }

    private func openFood(_ name: String) {
        let search = app.searchFields["Search Foods and Recipes"]
        for _ in 0..<40 {
            if search.exists && search.isHittable { break }
            app.swipeDown(velocity: .fast)
        }
        waitUntilHittable(search)
        search.tap()
        if search.buttons["Clear text"].exists { search.buttons["Clear text"].tap() }
        search.typeText(name)
        XCTAssertEqual(search.value as? String, name)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        waitUntilHittable(row)
        row.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 3))
    }

    private func startMeal(_ names: [String]) {
        clearLibrarySearch()
        app.navigationBars["Add Food"].buttons["New Food"].tap()
        app.buttons["New Meal"].tap()
        XCTAssertTrue(app.navigationBars["New Meal"].waitForExistence(timeout: 3))
        for name in names { pickFood(name) }
        endSearch(in: app.searchFields["Search My Foods"])
        app.buttons["Next (\(names.count))"].tap()
        XCTAssertTrue(app.navigationBars["New Meal"].buttons["Log"].waitForExistence(timeout: 3))
    }

    private func clearLibrarySearch() {
        let search = app.searchFields["Search Foods and Recipes"]
        guard search.exists, let value = search.value as? String,
              !value.isEmpty, value != "Search Foods and Recipes" else { return }
        search.tap()
        if search.buttons["Clear text"].exists { search.buttons["Clear text"].tap() }
        endSearch(in: search)
    }

    private func pickFood(_ name: String) {
        let field = app.searchFields["Search My Foods"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        if field.buttons["Clear text"].exists { field.buttons["Clear text"].tap() }
        app.typeText(name)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
    }

    private func endSearch(in field: XCUIElement) {
        let close = app.buttons.allElementsBoundByIndex.first {
            $0.isHittable && ["close", "cancel"].contains($0.label.lowercased())
                && abs($0.frame.midY - field.frame.midY) < 30
        }
        XCTAssertNotNil(close)
        close?.tap()
    }

    private func selectVolumeUnit(_ title: String) {
        let picker = app.buttons["portionUnitPicker"]
        scrollBackTo(picker)
        picker.tap()
        waitUntilHittable(app.buttons[title])
        app.buttons[title].tap()
    }

    private func assertValue(_ metric: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        // A presented recipe retains the meal's matching IDs behind it. Only its foreground form may
        // guide scrolling while the recipe's own nutrient row is still outside the lazy viewport.
        // Re-query each time: XCTest enumerates frontmost forms first, unlike its printed hierarchy.
        if let value = reveal({
            let forms = self.app.collectionViews.allElementsBoundByIndex
            let navigation = self.app.navigationBars.allElementsBoundByIndex.first(where: \.isHittable)
            let aligned = forms.filter { form in
                guard let navigation else { return true }
                return abs(form.frame.width - navigation.frame.width) < 2
                    && form.frame.minY < navigation.frame.maxY
            }
            let candidates = aligned.isEmpty ? forms : aligned
            var foreground = candidates.first
            for form in candidates.dropFirst() {
                if let current = foreground, form.frame.minY > current.frame.minY + 1 { foreground = form }
            }
            return foreground?.staticTexts.matching(identifier: "nutritionValue-\(metric)").allElementsBoundByIndex ?? []
        }) {
            XCTAssertEqual(value.label, expected, file: file, line: line)
            return
        }
        let hierarchy = app.debugDescription
        print(hierarchy)
        let diagnostic = XCTAttachment(string: hierarchy)
        diagnostic.name = "Missing \(metric) value accessibility hierarchy"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Missing \(metric) value"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTFail("Couldn't reach the value of \(metric)", file: file, line: line)
    }

    private func replace(_ field: XCUIElement, with value: String) {
        revealInput(field)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let current = field.value as? String ?? ""
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2) + value)
        XCTAssertEqual(field.value as? String, value, "Typing must reach the intended field.\n\(app.debugDescription)")
    }

    /// `isHittable` can be true for a clipped field whose center is behind the keyboard or navigation bar.
    /// Keep the whole field in the clear band and use short drags, so a one-line input cannot be skipped.
    private func revealInput(_ field: XCUIElement) {
        XCTAssertNotNil(reveal { field.exists ? [field] : [] }, "Couldn't fully reveal \(field)\n\(app.debugDescription)")
    }

    /// Re-evaluates candidates as lazy rows load, preferring a presented sheet over matching IDs behind it.
    private func reveal(_ elements: () -> [XCUIElement], initiallyUpward: Bool = true) -> XCUIElement? {
        var upward = initiallyUpward
        for _ in 0..<24 {
            let screen = app.windows.firstMatch.frame
            let top = (app.navigationBars.allElementsBoundByIndex.filter(\.isHittable)
                .map { $0.frame.maxY }.max() ?? screen.minY + 110) + 8
            let keyboard = app.keyboards.firstMatch
            let tabBarTop = app.tabBars.allElementsBoundByIndex.filter(\.isHittable).map { $0.frame.minY }.min()
            let bottom = keyboard.exists ? keyboard.frame.minY - 20 : (tabBarTop ?? screen.maxY - 34) - 8
            let candidates = elements()
            if let visible = candidates.last(where: { $0.isHittable && $0.frame.minY >= top && $0.frame.maxY <= bottom }) {
                return visible
            }
            if let target = candidates.last, !target.frame.isEmpty {
                upward = target.frame.midY > (top + bottom) / 2
            }
            let center = (top + bottom) / 2
            let distance = min(60, (bottom - top) / 4)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: screen.midX, dy: center + (upward ? distance : -distance)))
            let end = origin.withOffset(CGVector(dx: screen.midX, dy: center + (upward ? -distance : distance)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        return nil
    }

    private func scrollTo(_ element: XCUIElement) {
        XCTAssertNotNil(reveal { element.exists ? [element] : [] }, "Couldn't reach \(element)\n\(app.debugDescription)")
    }

    /// Today's Health entries and the saved library can span many screens at accessibility text sizes.
    /// Search by half a visible page, then position a found row precisely before tapping it.
    private func scrollThroughLongList(to element: XCUIElement) {
        var upward = true
        for _ in 0..<80 {
            let screen = app.windows.firstMatch.frame
            let top = (app.navigationBars.allElementsBoundByIndex.filter(\.isHittable)
                .map { $0.frame.maxY }.max() ?? screen.minY + 110) + 8
            let keyboard = app.keyboards.firstMatch
            let tabBarTop = app.tabBars.allElementsBoundByIndex.filter(\.isHittable).map { $0.frame.minY }.min()
            let bottom = keyboard.exists ? keyboard.frame.minY - 20 : (tabBarTop ?? screen.maxY - 34) - 8
            if element.exists && !element.frame.isEmpty {
                let frame = element.frame
                if frame.maxY >= top && frame.minY <= bottom {
                    scrollTo(element)
                    return
                }
                upward = frame.midY > (top + bottom) / 2
            }
            let center = (top + bottom) / 2
            let distance = (bottom - top) / 4
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: screen.midX, dy: center + (upward ? distance : -distance)))
            let end = origin.withOffset(CGVector(dx: screen.midX, dy: center + (upward ? -distance : distance)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Couldn't find \(element) in the list.\n\(app.debugDescription)")
    }

    private func waitUntilHittable(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed,
                       "Element didn't become hittable: \(element)")
    }

    private func scrollBackTo(_ element: XCUIElement) {
        XCTAssertNotNil(reveal({ element.exists ? [element] : [] }, initiallyUpward: false),
                        "Couldn't reach \(element)\n\(app.debugDescription)")
    }
}
