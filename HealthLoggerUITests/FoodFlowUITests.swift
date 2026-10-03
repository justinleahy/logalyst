import XCTest

/// Drives the 1.1 food flows end to end in a simulator: weighed foods (C2), editing logged foods with injected
/// failures (C3), and composing and correcting meals (C4). Each test makes foods with its own names, so it doesn't
/// depend on what's already saved, and logs to the simulator's Health store.
@MainActor
final class FoodFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    /// Keeps this run's foods apart from earlier runs'.
    private let tag = String(UUID().uuidString.prefix(4))

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: C2: weighed foods

    /// Ready when: a 35 g portion of a food defined per 100 g logs 0.35 times each nutrient, and a weighed entry
    /// reads as "35 g".
    func testLogAFoodByWeight() throws {
        launch()
        let name = "Granola \(tag)"
        openAddFood()
        createFood(name, serving: "100 g", calories: "400", useStatedWeight: true)

        open(name)
        // A serving that's just a weight starts out in grams.
        XCTAssertTrue(app.segmentedControls.buttons["Grams"].isSelected)
        replaceText(in: app.textFields["Grams of \(name)"], with: "35")
        XCTAssertTrue(app.staticTexts["140 kcal"].waitForExistence(timeout: 3))
        attachScreenshot("Log by weight")
        app.navigationBars.buttons["Log"].tap()

        // Back in Add Food, the recent food reads as a weight.
        scrollToTop()
        XCTAssertTrue(app.staticTexts["35 g · 140 kcal"].waitForExistence(timeout: 5))
        attachScreenshot("Recent weighed food")

        // The same amount in ounces logs the same.
        open(name, inRecents: true)
        XCTAssertTrue(app.segmentedControls.buttons["Grams"].isSelected)
        app.segmentedControls.buttons["Ounces"].tap()
        XCTAssertEqual(app.textFields["Ounces of \(name)"].value as? String, "1.23")
        XCTAssertTrue(app.staticTexts["140 kcal"].exists)
    }

    /// A food with no serving weight is entered by the serving only.
    func testAFoodWithoutAWeightIsByTheServing() throws {
        launch()
        let name = "Soup \(tag)"
        openAddFood()
        createFood(name, serving: "1 cup (240 mL)", calories: "90", useStatedWeight: false)
        open(name)
        XCTAssertFalse(app.segmentedControls.buttons["Grams"].exists)
        XCTAssertTrue(app.textFields["Servings of \(name)"].exists)
    }

    // MARK: C3: editing logged foods

    /// Ready when: an edit leaves one corrected entry with the expected totals, and changing the weight recalculates.
    func testEditAFoodFromHistory() throws {
        launch()
        let name = "Muesli \(tag)"
        logWeighedFood(name, grams: "35")

        tab("History")
        entry(name).tap()
        XCTAssertTrue(app.navigationBars.buttons["Save"].waitForExistence(timeout: 3))
        replaceText(in: app.textFields["Grams of \(name)"], with: "50")
        XCTAssertTrue(app.staticTexts["200 kcal"].exists)
        attachScreenshot("Edit a logged food")
        app.navigationBars.buttons["Save"].tap()

        XCTAssertTrue(entry(name).waitForExistence(timeout: 5))
        XCTAssertEqual(entries(name).count, 1)
        XCTAssertTrue(entry(name).label.contains("200 kcal"), entry(name).label)
    }

    /// Ready when: an injected delete failure shows the incomplete state, and a retry removes only the original.
    func testAFailedDeleteCanBeRetriedFromTheAlert() throws {
        let name = "Oats \(tag)"
        launch()
        logWeighedFood(name, grams: "35")
        launch(["-InjectEditFault", "delete"])
        editWeight(of: name, to: "60")

        XCTAssertTrue(app.alerts["Couldn't Remove Original"].waitForExistence(timeout: 5))
        attachScreenshot("Original remains")
        app.alerts.buttons["Try Again"].tap()

        XCTAssertTrue(entry(name).waitForExistence(timeout: 5))
        waitForCount(name, 1)
        XCTAssertTrue(entry(name).label.contains("240 kcal"), entry(name).label)
    }

    /// Left for later, the unfinished edit is offered in History until its original is removed.
    func testAFailedDeleteCanBeFinishedFromHistory() throws {
        let name = "Rye \(tag)"
        launch()
        logWeighedFood(name, grams: "35")
        launch(["-InjectEditFault", "delete"])
        editWeight(of: name, to: "70")

        XCTAssertTrue(app.alerts["Couldn't Remove Original"].waitForExistence(timeout: 5))
        app.alerts.buttons["Later"].tap()
        let banner = app.staticTexts["Your edit of \(name) didn't finish"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        waitForCount(name, 2)
        attachScreenshot("Unfinished edit in History")

        app.buttons["Remove Original"].tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5))
        waitForCount(name, 1)
        XCTAssertTrue(entry(name).label.contains("280 kcal"), entry(name).label)
    }

    /// Ready when: an injected save failure leaves the original entry unchanged.
    func testAFailedSaveLeavesTheOriginal() throws {
        let name = "Bran \(tag)"
        launch()
        logWeighedFood(name, grams: "35")
        launch(["-InjectEditFault", "save"])
        editWeight(of: name, to: "80")

        XCTAssertTrue(app.alerts["Couldn't Save"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        waitForCount(name, 1)
        XCTAssertTrue(entry(name).label.contains("140 kcal"), entry(name).label)
    }

    /// Ready when: an edit interrupted by the app closing is reconciled after relaunch.
    func testAnEditInterruptedByTheAppClosingFinishesOnRelaunch() throws {
        let name = "Spelt \(tag)"
        launch()
        logWeighedFood(name, grams: "35")
        launch(["-InjectEditFault", "stop"])
        editWeight(of: name, to: "90")
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "The app should have closed after saving the correction.")

        launch()
        tab("History")
        XCTAssertTrue(entry(name).waitForExistence(timeout: 5))
        waitForCount(name, 1)
        XCTAssertTrue(entry(name).label.contains("360 kcal"), entry(name).label)
        XCTAssertFalse(app.staticTexts["Your edit of \(name) didn't finish"].exists)
    }

    // MARK: C4: composing and correcting meals

    /// Ready when: the manual start supports adding, replacing, adjusting and excluding foods, by weight where known;
    /// preview totals match the logged result; and saving as a recipe keeps the ingredients and amounts.
    func testComposeAndCorrectAMeal() throws {
        launch()
        let meal = composeMeal()

        app.navigationBars.buttons["Log"].tap()
        tab("History")
        XCTAssertTrue(entry(meal.rice).waitForExistence(timeout: 5))
        XCTAssertTrue(entry(meal.rice).label.contains("147 kcal"), entry(meal.rice).label)
        XCTAssertTrue(entry(meal.salad).label.contains("300 kcal"), entry(meal.salad).label)
        XCTAssertFalse(entry(meal.soup).exists)
        XCTAssertFalse(entry(meal.bread).exists)
        checkRecipe(meal.recipe)
    }

    /// Ready when: manual meal composition works where meal-photo analysis is unavailable. Run on an iOS 18–26
    /// simulator, where Photo of Meal is hidden. Health isn't asked for, since a test can't answer that sheet there,
    /// so this stops short of logging, which `testComposeAndCorrectAMeal` covers.
    func testComposeAMealWherePhotoOfMealIsUnavailable() throws {
        if #available(iOS 27, *) { throw XCTSkip("Photo of Meal can be available on iOS 27; run this on iOS 18–26.") }
        launch(["-SkipHealthAuthorization", "YES"])
        let meal = composeMeal()
        app.navigationBars["New Meal"].buttons.element(boundBy: 0).tap()
        app.buttons["Cancel"].tap()
        checkRecipe(meal.recipe)
    }

    private struct ComposedMeal {
        let rice, bread, salad, soup, recipe: String
    }

    /// Makes four foods, starts a meal from two, adds one, replaces one, weighs one in ounces, leaves one out, and
    /// saves what's left as a recipe, ending on the meal screen ready to log.
    private func composeMeal() -> ComposedMeal {
        let meal = ComposedMeal(rice: "Rice \(tag)", bread: "Bread \(tag)", salad: "Salad \(tag)", soup: "Soup \(tag)",
                                recipe: "Bowl \(tag)")
        openAddFood()
        createFood(meal.rice, serving: "100 g", calories: "130", useStatedWeight: true)
        createFood(meal.bread, serving: "1 slice", calories: "80", useStatedWeight: false)
        createFood(meal.salad, serving: "1 bowl", calories: "300", useStatedWeight: false)
        createFood(meal.soup, serving: "1 cup", calories: "90", useStatedWeight: false)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Start a meal from saved foods. This doesn't need Photo of Meal, which is hidden before iOS 27.
        let newMeal = app.buttons["New Meal"].firstMatch
        scrollUntilHittable(newMeal)
        if #unavailable(iOS 27) {
            XCTAssertFalse(app.buttons["Photo of Meal"].exists, "Photo of Meal needs iOS 27 and Apple Intelligence.")
        }
        newMeal.tap()
        tapFood(meal.rice)
        tapFood(meal.bread)
        endSearch()
        app.buttons["Next (2)"].tap()
        XCTAssertTrue(app.navigationBars["New Meal"].waitForExistence(timeout: 3))

        // Add a missing food. (The Nutrition tab behind the sheet has an Add Food button too.)
        hittableButton("Add Food").tap()
        tapFood(meal.soup)
        endSearch()
        app.buttons["Add (1)"].tap()
        XCTAssertTrue(portion(meal.soup).waitForExistence(timeout: 3))

        // Replace the wrong one.
        portion(meal.bread).swipeLeft()
        app.buttons["Replace"].tap()
        tapFood(meal.salad)
        XCTAssertTrue(portion(meal.salad).waitForExistence(timeout: 3))
        XCTAssertFalse(portion(meal.bread).exists)

        // Weigh the rice in ounces, and leave the soup out.
        app.buttons["Unit for \(meal.rice)"].tap()
        app.buttons["Ounces"].tap()
        replaceText(in: app.textFields["Ounces of \(meal.rice)"], with: "4")
        replaceText(in: app.textFields["Servings of \(meal.soup)"], with: "0")
        // 4 oz of rice is 113.4 g: 147.4 kcal, plus 300 for the salad.
        XCTAssertTrue(app.staticTexts["447 kcal"].waitForExistence(timeout: 3))
        attachScreenshot("Composed meal")

        // Save as a recipe keeps the chosen ingredients and amounts.
        app.buttons["Save as Recipe"].tap()
        XCTAssertTrue(app.navigationBars["New Recipe"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["4 oz · 147 kcal"].exists)
        XCTAssertTrue(app.staticTexts["1 bowl · 300 kcal"].exists)
        app.textFields["Name"].tap()
        app.typeText(meal.recipe)
        attachScreenshot("Meal saved as recipe")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["New Meal"].waitForExistence(timeout: 3))
        return meal
    }

    /// The recipe has the two foods that were eaten, in the amounts eaten.
    private func checkRecipe(_ name: String) {
        openAddFood()
        let recipe = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        scrollUntilExists(recipe)
        XCTAssertTrue(recipe.label.contains("2 ingredients · 447 kcal per serving"), recipe.label)
    }

    // MARK: Helpers

    private func launch(_ arguments: [String] = []) {
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        // A simulator new to the app starts with onboarding.
        if app.staticTexts["Welcome to Logalyst"].waitForExistence(timeout: 2) { app.buttons["Skip"].tap() }
        allowHealthAccessIfAsked()
    }

    /// Approves the Health permission sheet if this simulator hasn't yet.
    private func allowHealthAccessIfAsked() {
        let selectAll = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Select All' OR label == 'Turn On All'")).firstMatch
        guard selectAll.waitForExistence(timeout: 3) else { return }
        selectAll.tap()
        for label in ["Continue", "All Recorded Data and Future Data", "Allow"] {
            let button = app.buttons[label].firstMatch
            if button.waitForExistence(timeout: 3) {
                scrollUntilHittable(button)
                button.tap()
            }
        }
    }

    private func tab(_ name: String) {
        let tab = app.tabBars.buttons[name].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
        // Without Health access, screens that read it say so.
        if app.launchArguments.contains("-SkipHealthAuthorization"), app.alerts.buttons["OK"].waitForExistence(timeout: 2) {
            app.alerts.buttons["OK"].tap()
        }
    }

    private func openAddFood() {
        tab("Nutrition")
        let addFood = app.buttons["Add Food"].firstMatch
        scrollUntilHittable(addFood)
        addFood.tap()
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 3))
    }

    /// From Add Food: makes a food with one nutrient, optionally taking the weight its serving size states.
    private func createFood(_ name: String, serving: String, calories: String, useStatedWeight: Bool) {
        let menu = app.navigationBars["Add Food"].buttons["New Food"]
        let menuFrame = menu.frame
        menu.tap()
        // The menu's own New Food item, which has the same name as the menu.
        let item = app.buttons.matching(identifier: "New Food").allElementsBoundByIndex
            .last { $0.isHittable && $0.frame != menuFrame }
        XCTAssertNotNil(item, "No New Food menu item in:\n\(app.debugDescription)")
        item?.tap()
        XCTAssertTrue(app.navigationBars["New Food"].waitForExistence(timeout: 3))
        app.textFields["Name"].tap()
        app.typeText(name)
        app.textFields["Serving Size"].tap()
        app.typeText(serving)
        if useStatedWeight {
            let use = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Use ' AND label ENDSWITH 'from Serving Size'")).firstMatch
            XCTAssertTrue(use.waitForExistence(timeout: 2), "Expected the editor to offer the serving size's weight.")
            use.tap()
        } else {
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label ENDSWITH 'from Serving Size'")).firstMatch.exists)
        }
        let field = app.textFields["Calories in kcal"]
        scrollUntilHittable(field)
        field.tap()
        app.typeText(calories)
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 3))
    }

    /// Opens a saved food (or a recent one) from Add Food to log it.
    private func open(_ name: String, inRecents: Bool = false) {
        let rows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name))
        // My Foods comes after Recents, so the saved food is the last match; lists load rows as they scroll in.
        scrollUntilExists(inRecents ? rows.firstMatch : rows.element(boundBy: max(rows.count - 1, 0)))
        if !inRecents {
            while !rows.element(boundBy: rows.count - 1).isHittable { app.swipeUp(velocity: .slow) }
        }
        let row = rows.element(boundBy: inRecents ? 0 : rows.count - 1)
        scrollUntilHittable(row)
        row.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 3))
    }

    /// Makes a food of 400 kcal per 100 g and logs a weight of it, returning to the Nutrition tab.
    private func logWeighedFood(_ name: String, grams: String) {
        openAddFood()
        createFood(name, serving: "100 g", calories: "400", useStatedWeight: true)
        open(name)
        replaceText(in: app.textFields["Grams of \(name)"], with: grams)
        app.navigationBars.buttons["Log"].tap()
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 3))
    }

    private func editWeight(of name: String, to grams: String) {
        tab("History")
        XCTAssertTrue(entry(name).waitForExistence(timeout: 5))
        entry(name).tap()
        replaceText(in: app.textFields["Grams of \(name)"], with: grams)
        app.navigationBars.buttons["Save"].tap()
    }

    /// A food's rows in History or Nutrition.
    private func entries(_ name: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name))
    }

    private func entry(_ name: String) -> XCUIElement {
        entries(name).firstMatch
    }

    private func waitForCount(_ name: String, _ count: Int) {
        let predicate = NSPredicate { _, _ in self.entries(name).count == count }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed,
                       "Expected \(count) entries of \(name), found \(entries(name).count).")
    }

    /// A food in the meal screen's list.
    private func portion(_ name: String) -> XCUIElement {
        app.staticTexts[name].firstMatch
    }

    /// Picks a food in the food picker, finding it by searching My Foods.
    private func tapFood(_ name: String) {
        let search = app.searchFields["Search My Foods"]
        XCTAssertTrue(search.waitForExistence(timeout: 3), "Missing the picker's search field in:\n\(app.debugDescription)")
        search.tap()
        if let current = search.value as? String, !current.isEmpty, current != "Search My Foods" {
            search.buttons["Clear text"].firstMatch.tap()
        }
        app.typeText(name)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
    }

    /// Closes the picker's search, which hides the navigation bar and its buttons while it's open.
    private func endSearch() {
        let field = app.searchFields.firstMatch
        guard field.exists else { return }
        let close = app.buttons.allElementsBoundByIndex.first {
            ["close", "cancel"].contains($0.label.lowercased()) && abs($0.frame.midY - field.frame.midY) < 30
        }
        XCTAssertNotNil(close, "No way to close the search in:\n\(app.debugDescription)")
        close?.tap()
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Missing \(field)")
        scrollUntilHittable(field)
        // At the trailing edge, so the cursor lands after the text to delete it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let current = field.value as? String ?? ""
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2) + text)
    }

    /// The button with this name that can be tapped, when another screen behind a sheet has one too.
    private func hittableButton(_ name: String) -> XCUIElement {
        let match = app.buttons.matching(identifier: name).allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(match, "No tappable \(name) button in:\n\(app.debugDescription)")
        return match ?? app.buttons[name]
    }

    private func scrollToTop() {
        for _ in 0..<6 { app.swipeDown(velocity: .fast) }
    }

    private func scrollUntilExists(_ element: XCUIElement) {
        var tries = 0
        while !element.exists && tries < 15 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        XCTAssertTrue(element.exists, "Couldn't find \(element)")
    }

    private func scrollUntilHittable(_ element: XCUIElement) {
        var tries = 0
        while !(element.exists && element.isHittable) && tries < 10 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
