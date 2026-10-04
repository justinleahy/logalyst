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
        app.buttons["Ounces (weight)"].tap()
        replaceText(in: app.textFields["Ounces of \(meal.rice)"], with: "4")
        replaceText(in: app.textFields["Servings of \(meal.soup)"], with: "0")
        // 4 oz of rice is 113.4 g: 147.4 kcal, plus 300 for the salad.
        XCTAssertTrue(app.staticTexts["447 kcal"].waitForExistence(timeout: 3))
        attachScreenshot("Composed meal")

        // Save as a recipe keeps the chosen ingredients and amounts.
        scrollUntilHittable(app.buttons["Save as Recipe"])
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

    // MARK: C5: restaurant and brand lookup

    // These use Debug stubs: `-StubMealPhoto` finds a Chipotle bowl in any photo (double chicken, rice that may be
    // hidden, black beans, guacamole from the description and a lime wedge), and `-StubNutritionLookup` answers
    // as a brand's website would, with test data.

    /// Ready when: a meal photo with the brand supplied produces editable matches grounded in retrieved nutrition;
    /// a double portion is exactly twice each published value; hidden and ambiguous foods are corrected before
    /// logging; each published result links to its source; and the logged food keeps it.
    func testLookUpABrandedMealPhoto() throws {
        launch(["-StubMealPhoto", "YES", "-StubNutritionLookup", "ok"])
        openPhotoOfMeal()
        enterBrand("Chipotle", details: "double chicken, guac")
        let footer = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Logalyst finds the nutrition Chipotle publishes'"))
        XCTAssertTrue(footer.firstMatch.exists)
        XCTAssertTrue(footer.firstMatch.label.contains("Your photo, details and foods stay on your iPhone."))
        attachScreenshot("Brand and details")
        app.buttons["Look Up Nutrition"].tap()
        XCTAssertTrue(app.navigationBars["Chipotle Meal"].waitForExistence(timeout: 10))

        // Published values, scaled by the portions from the photo and description.
        XCTAssertTrue(app.staticTexts["Chipotle · 2 × 4 oz · 360 kcal"].exists, "Double chicken is 2 × 180 kcal.")
        XCTAssertTrue(app.staticTexts["Chipotle · 4 oz · 130 kcal"].exists)
        XCTAssertTrue(app.staticTexts["Chipotle · 4 oz · 230 kcal"].exists, "Guac matches Guacamole.")
        XCTAssertTrue(app.staticTexts["From your details."].exists)
        XCTAssertTrue(app.staticTexts["Not in Chipotle's published nutrition, so this is an estimate."].exists)
        // Rice could be white or brown, and may be under the toppings: not counted until chosen.
        XCTAssertTrue(app.staticTexts["Not counted yet"].exists)
        XCTAssertTrue(app.staticTexts["Which is it?"].exists)
        attachScreenshot("Branded meal to review")
        scrollUntilExists(app.staticTexts["722 kcal"])  // 360 + 130 + 230 + 2, without the rice.

        let choose = app.buttons["Choose which Rice"]
        scrollBackUntilHittable(choose)
        choose.tap()
        let white = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'White Rice'")).firstMatch
        XCTAssertTrue(white.waitForExistence(timeout: 3))
        white.tap()
        XCTAssertTrue(app.staticTexts["Chipotle · 4 oz · 210 kcal"].waitForExistence(timeout: 3))
        scrollUntilExists(app.staticTexts["932 kcal"])

        // Each published food's source is linked, with its serving and date.
        let source = app.links.matching(NSPredicate(format: "label CONTAINS 'Chipotle nutrition (test data)'")).firstMatch
        scrollUntilExists(source)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'test data · Read'")).firstMatch.exists)
        attachScreenshot("Sources")

        app.navigationBars["Chipotle Meal"].buttons["Log"].tap()
        XCTAssertFalse(app.navigationBars["Chipotle Meal"].waitForExistence(timeout: 2))

        // The logged chicken keeps its published values and source.
        tab("History")
        let chicken = entry("Chicken")
        XCTAssertTrue(chicken.waitForExistence(timeout: 5))
        XCTAssertTrue(chicken.label.contains("360 kcal"), chicken.label)
        chicken.tap()
        XCTAssertTrue(app.navigationBars["Chicken"].waitForExistence(timeout: 3))
        let logged = app.links.matching(NSPredicate(format: "label CONTAINS 'Chipotle nutrition (test data)'")).firstMatch
        scrollUntilExists(logged)
        attachScreenshot("Logged food's source")
    }

    /// Ready when: offline, rate-limit and other lookup failures offer a usable fallback: labeled on-device
    /// estimates, a retry, and correction, never a claim that estimates were verified online.
    func testABrandedLookupThatFailsFallsBackToEstimates() throws {
        launch(["-StubMealPhoto", "YES", "-StubNutritionLookup", "offline"])
        openPhotoOfMeal()
        enterBrand("Chipotle", details: "")
        app.buttons["Look Up Nutrition"].tap()
        XCTAssertTrue(app.navigationBars["Chipotle Meal"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Couldn't Look Up Chipotle"].exists)
        XCTAssertTrue(app.staticTexts["You're offline. Connect to the internet and try again."].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Published'")).firstMatch.exists)
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(identifier: "Estimate").count, 4)
        attachScreenshot("Lookup failed")

        // The rice that may be hidden waits to be confirmed even so.
        XCTAssertTrue(app.staticTexts["Not counted yet"].exists)
        XCTAssertTrue(app.staticTexts["Was it there?"].exists)
        app.buttons["Include Rice"].tap()
        XCTAssertFalse(app.staticTexts["Not counted yet"].exists)

        // Trying again comes back to the meal screen with the same answer.
        app.buttons["Try Again"].tap()
        XCTAssertTrue(app.navigationBars["Chipotle Meal"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Couldn't Look Up Chipotle"].exists)
    }

    /// Ready when: a photo without a brand still works on the device, with nothing sent.
    func testAMealPhotoWithoutABrandStaysOnTheDevice() throws {
        launch(["-StubMealPhoto", "YES", "-StubNutritionLookup", "ok"])
        openPhotoOfMeal()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'nothing is sent anywhere'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Look Up Nutrition"].exists)
        app.buttons["Estimate Nutrition"].tap()
        XCTAssertTrue(app.navigationBars["Meal from Photo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Banana"].exists)
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(identifier: "Estimate").count, 2)
        XCTAssertFalse(app.staticTexts["Sources"].exists)
    }

    /// Ready when: an unmatched food can be replaced with one of the brand's published foods, found by an
    /// explicit search rather than while typing.
    func testReplaceAFoodWithAPublishedOne() throws {
        launch(["-StubMealPhoto", "YES", "-StubNutritionLookup", "ok"])
        openPhotoOfMeal()
        enterBrand("Chipotle", details: "")
        app.buttons["Look Up Nutrition"].tap()
        XCTAssertTrue(app.navigationBars["Chipotle Meal"].waitForExistence(timeout: 10))

        portion("Lime Wedge").swipeLeft()
        app.buttons["Replace"].tap()
        XCTAssertTrue(app.navigationBars["Replace Lime Wedge"].waitForExistence(timeout: 3))
        // The foods the meal's lookup found are offered first, filtered as you type; Sofritas needs a search.
        // Scope to the sheet: Nutrition behind it may already contain a logged Chicken or Sofritas entry.
        let results = app.collectionViews["publishedFoodResults"]
        XCTAssertTrue(results.waitForExistence(timeout: 3))
        let chicken = results.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Chicken'")).firstMatch
        XCTAssertTrue(chicken.exists)
        let search = app.searchFields["Search Chipotle"]
        search.tap()
        search.typeText("sofritas")
        XCTAssertEqual(search.value as? String, "sofritas", app.debugDescription)
        let sofritas = results.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sofritas'")).firstMatch
        XCTAssertFalse(sofritas.exists)
        XCTAssertTrue(chicken.waitForNonExistence(timeout: 3), app.debugDescription)
        app.typeText("\n")
        XCTAssertTrue(sofritas.waitForExistence(timeout: 5))
        attachScreenshot("Published food search")
        sofritas.tap()
        XCTAssertTrue(app.navigationBars["Chipotle Meal"].waitForExistence(timeout: 3))
        XCTAssertTrue(portion("Sofritas").exists)
        XCTAssertFalse(portion("Lime Wedge").exists)
    }

    /// Live: the real lookup, reading chipotle.com (needs the internet), with only the photo stubbed. Skipped unless
    /// run with `TEST_RUNNER_LIVE_LOOKUP=1`, so the usual runs don't depend on a website. `TEST_RUNNER_LIVE_BRAND`
    /// and `TEST_RUNNER_LIVE_SEARCH` also search a second brand's foods through the same path.
    func testLiveBrandLookup() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LIVE_LOOKUP"] == "1" else {
            throw XCTSkip("Reads brands' websites; run with TEST_RUNNER_LIVE_LOOKUP=1.")
        }
        launch(["-StubMealPhoto", "YES"])
        openPhotoOfMeal()
        enterBrand("Chipotle", details: "")
        app.buttons["Look Up Nutrition"].tap()
        XCTAssertTrue(app.navigationBars["Chipotle Meal"].waitForExistence(timeout: 120))
        attachScreenshot("Live Chipotle meal")
        // Chipotle's published chicken is 180 kcal per 4 oz, so double is 360; black beans are 130.
        XCTAssertTrue(app.staticTexts["Chipotle · 2 × 4 oz · 360 kcal"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Chipotle · 4 oz · 130 kcal"].exists)
        let sources = app.staticTexts["Sources"]
        scrollUntilExists(sources)
        attachScreenshot("Live Chipotle sources")

        guard let brand = environment["LIVE_BRAND"], let search = environment["LIVE_SEARCH"] else { return }
        app.navigationBars["Chipotle Meal"].buttons.element(boundBy: 0).tap()
        let field = app.textFields["Restaurant or Brand"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        replaceText(in: field, with: brand)
        app.buttons["Look Up Nutrition"].tap()
        XCTAssertTrue(app.navigationBars["\(brand) Meal"].waitForExistence(timeout: 120))
        attachScreenshot("Live \(brand) meal")
        hittableButton("Add Food").tap()
        let searchField = app.searchFields["Search \(brand)"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        app.typeText(search + "\n")
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ AND label CONTAINS 'kcal'", search)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 120), "Nothing found for \(search) at \(brand)")
        attachScreenshot("Live \(brand) search")
    }

    private func openPhotoOfMeal() {
        tab("Nutrition")
        let button = app.buttons["Photo of Meal"].firstMatch
        scrollUntilHittable(button)
        button.tap()
        XCTAssertTrue(app.navigationBars["Photo of Meal"].waitForExistence(timeout: 3))
        app.buttons["Use Test Photo"].tap()
        XCTAssertTrue(app.images["Your photo"].waitForExistence(timeout: 3))
    }

    private func enterBrand(_ brand: String, details: String) {
        let field = app.textFields["Restaurant or Brand"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        app.typeText(brand)
        if !details.isEmpty {
            let detailsField = app.descendants(matching: .any).matching(identifier: "Meal Details").firstMatch
            XCTAssertTrue(detailsField.waitForExistence(timeout: 3))
            detailsField.tap()
            app.typeText(details)
        }
        XCTAssertTrue(app.buttons["Look Up Nutrition"].waitForExistence(timeout: 3))
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
        waitUntilHittable(menu)
        let menuFrame = menu.frame
        menu.tap()
        waitUntilHittable(app.buttons["New Recipe"])
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
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Use ' AND label CONTAINS ' g from Serving Size'")).firstMatch.exists)
        }
        let field = app.textFields["Calories in kcal"]
        revealInput(field)
        field.tap()
        app.typeText(calories)
        XCTAssertEqual(field.value as? String, calories, "Typing must reach Calories.\n\(app.debugDescription)")
        let save = app.navigationBars["New Food"].buttons["Save"]
        XCTAssertTrue(save.isEnabled, "A valid nutrient must enable Save while the input is focused.\n\(app.debugDescription)")
        save.tap()
        XCTAssertTrue(app.navigationBars["New Food"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 3))
        waitUntilHittable(menu)
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

    /// Scrolls back up only until the element can be tapped, so a sheet isn't pulled down and closed.
    private func scrollBackUntilHittable(_ element: XCUIElement) {
        var tries = 0
        while !(element.exists && element.isHittable) && tries < 10 {
            app.swipeDown(velocity: .slow)
            tries += 1
        }
        XCTAssertTrue(element.isHittable, "Couldn't reach \(element)")
    }

    private func scrollUntilHittable(_ element: XCUIElement) {
        var tries = 0
        var wasPresent = element.exists
        while !(element.exists && element.isHittable) && tries < 10 {
            wasPresent = wasPresent || element.exists
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        // A full-screen swipe can carry a short row above the navigation bar while dismissing the keyboard.
        if wasPresent && !(element.exists && element.isHittable) { scrollBackUntilHittable(element) }
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitUntilHittable(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed,
                       "Element didn't become hittable: \(element)")
    }

    private func revealInput(_ field: XCUIElement) {
        for _ in 0..<20 {
            let screen = app.windows.firstMatch.frame
            let top = (app.navigationBars.allElementsBoundByIndex.filter(\.isHittable)
                .map { $0.frame.maxY }.max() ?? screen.minY + 110) + 8
            let keyboard = app.keyboards.firstMatch
            let bottom = (keyboard.exists ? keyboard.frame.minY : screen.maxY - 80) - 20
            if field.exists && field.isHittable && field.frame.minY >= top && field.frame.maxY <= bottom { return }
            let upward = !field.exists || field.frame.midY > (top + bottom) / 2
            let center = (top + bottom) / 2
            let distance = min(60, (bottom - top) / 4)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: screen.midX, dy: center + (upward ? distance : -distance)))
            let end = origin.withOffset(CGVector(dx: screen.midX, dy: center + (upward ? -distance : distance)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Couldn't fully reveal \(field)\n\(app.debugDescription)")
    }
}
