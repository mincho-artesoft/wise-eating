import XCTest

final class VAL1DeviceDriverUITests: XCTestCase {
    private let ayurvedaasanayogaBundleID = "AyurvedaAsanaYoga.Arte-Soft"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureAyurvedaAsanaYogaHierarchy() throws {
        let app = XCUIApplication(bundleIdentifier: ayurvedaasanayogaBundleID)
        app.launchArguments = ["-ayurvedaasanayogaPlannerTelemetry", "-uiTestNoAds"]
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 30),
            "AyurvedaAsanaYoga did not reach the foreground"
        )
        let preparing = app.staticTexts["Preparing database…"]
        if preparing.waitForExistence(timeout: 5) {
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: preparing
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [ready], timeout: 90),
                .completed,
                "AyurvedaAsanaYoga did not finish preparing its database"
            )
        }
        print("VAL1-HIERARCHY-BEGIN")
        print(app.debugDescription)
        print("VAL1-HIERARCHY-END")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "VAL1-AyurvedaAsanaYoga-root"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testScheduleMeasuredPlan() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let prompt = environment["VAL1_PROMPT"], !prompt.isEmpty else {
            XCTFail("VAL1_PROMPT is required")
            return
        }
        guard
            let daysText = environment["VAL1_DAYS"],
            let days = Int(daysText),
            (1...7).contains(days)
        else {
            XCTFail("VAL1_DAYS must be an integer from 1 through 7")
            return
        }

        let app = XCUIApplication(bundleIdentifier: ayurvedaasanayogaBundleID)
        app.activate()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 30),
            "AyurvedaAsanaYoga did not reach the foreground"
        )

        let mealPlansFilter = app.buttons["Meal Plans"]
        XCTAssertTrue(
            mealPlansFilter.waitForExistence(timeout: 30),
            "Meal Plans filter was not present"
        )
        mealPlansFilter.tap()
        XCTAssertTrue(
            app.staticTexts["Meal Plans"].waitForExistence(timeout: 10),
            "Meal Plans list did not become active"
        )

        tapFloatingButton(in: app)
        XCTAssertTrue(
            app.staticTexts["New Meal Plan"].waitForExistence(timeout: 10),
            "New Meal Plan editor did not open"
        )

        let newPrompt = app.buttons["New Prompt"]
        scrollToElement(newPrompt, in: app)
        newPrompt.tap()
        XCTAssertTrue(
            app.staticTexts["New Prompt"].waitForExistence(timeout: 10),
            "Prompt editor did not open"
        )

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Prompt editor is missing")
        editor.tap()
        editor.typeText(prompt)
        app.buttons["Save"].tap()
        XCTAssertTrue(
            app.staticTexts["New Meal Plan"].waitForExistence(timeout: 10),
            "Prompt editor did not return to the meal-plan editor"
        )

        if days > 1 {
            for _ in 2...days {
                let addDay = app.buttons["Add Day"]
                scrollToElement(addDay, in: app)
                addDay.tap()
            }
        }

        tapFloatingButton(in: app)

        let scheduled = app.staticTexts["Generation Scheduled"]
        let unavailableMessages = [
            "This device doesn’t support Apple Intelligence.",
            "Apple Intelligence is turned off. Enable it in Settings to use AI.",
            "The model is downloading or preparing. Please try again shortly.",
            "Apple Intelligence requires iOS 26 or newer.",
            "Apple Intelligence is currently unavailable for an unknown reason."
        ]
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline && !scheduled.exists {
            if let message = unavailableMessages.first(where: {
                app.staticTexts[$0].exists
            }) {
                XCTFail("Generation unavailable: \(message)")
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(scheduled.exists, "Generation was not scheduled")
        print("VAL1-SCHEDULED|days=\(days)|prompt=\(prompt)")
    }

    func testCreateFoodWithNutritionGraph() throws {
        let app = XCUIApplication(bundleIdentifier: ayurvedaasanayogaBundleID)
        app.launchArguments = [
            "-uiTestNoAds",
            "-skipPermissionPrompts",
            "-uiTestNonemptyAyurveda",
            "-lastSelectedTabRoot", "2"
        ]
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 30),
            "AyurvedaAsanaYoga did not reach the foreground"
        )
        let preparing = app.staticTexts["Preparing database…"]
        if preparing.waitForExistence(timeout: 5) {
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: preparing
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [ready], timeout: 90),
                .completed,
                "AyurvedaAsanaYoga did not finish preparing its database"
            )
        }

        let foodList = app.staticTexts["Food list"]
        let defaultList = app.staticTexts["Default list"]
        XCTAssertTrue(
            foodList.waitForExistence(timeout: 15)
                || defaultList.waitForExistence(timeout: 1),
            "The Foods screen did not open. Hierarchy: \(app.debugDescription)"
        )
        if !foodList.exists {
            let foodsFilter = app.buttons["Foods"]
            XCTAssertTrue(
                foodsFilter.waitForExistence(timeout: 10),
                "The Foods filter is missing"
            )
            foodsFilter.tap()
            XCTAssertTrue(foodList.waitForExistence(timeout: 10))
        }

        // A periodic wellness check-in may appear independently of the food
        // workflow and cover the floating add button.
        let dismissCheckIn = app.buttons["Not now"]
        if dismissCheckIn.waitForExistence(timeout: 2) {
            // The custom check-in overlay exposes an incorrect accessibility
            // frame on iOS 26, so tap the visible left action directly.
            app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.20, dy: 0.56)
            ).tap()
            let dismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: dismissCheckIn
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [dismissed], timeout: 5),
                .completed,
                "The wellness check-in still covers the Add Food button"
            )
        }

        let add = app.images["widget.large.badge.plus"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "The Add Food button is missing")
        tapFloatingButton(in: app)
        let editorTitle = app.staticTexts["Add Food"]
        XCTAssertTrue(editorTitle.waitForExistence(timeout: 10))

        let name = app.textFields["food-editor-name"]
        XCTAssertTrue(
            name.waitForExistence(timeout: 5),
            "The food name field is missing. Hierarchy: \(app.debugDescription)"
        )
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let originalName = "UI Routing Food \(UUID().uuidString.prefix(8))"
        name.typeText(originalName)

        // The keyboard covers the serving field on the compact simulator.
        // Commit the single-line name first so the next visible tap can reach it.
        let returnKey = app.keyboards.buttons["Return"]
        XCTAssertTrue(returnKey.waitForExistence(timeout: 5), "Return key is missing")
        returnKey.tap()
        let keyboardDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.keyboards.firstMatch
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [keyboardDismissed], timeout: 5),
            .completed,
            "Name keyboard did not dismiss"
        )

        // Filling the serving weight activates Save and causes the editor to
        // materialize the full eight-model nutrition relationship graph.
        let servingWeight = app.textFields["food-editor-serving-weight"]
        XCTAssertTrue(servingWeight.waitForExistence(timeout: 5))
        // SwiftUI exposes this field as non-hittable while the name keyboard
        // is open, although its visible frame still accepts a real tap.
        tapVisibleCenter(of: servingWeight, in: app)
        let weightFocused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: servingWeight
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [weightFocused], timeout: 5),
            .completed,
            "Serving weight did not receive keyboard focus. Hierarchy: \(app.debugDescription)"
        )
        servingWeight.typeText("100")

        let save = app.buttons["food-editor-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: save
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        save.tap()

        let editorClosed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: editorTitle
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [editorClosed], timeout: 20),
            .completed,
            "Food save did not close the editor. Hierarchy: \(app.debugDescription)"
        )
        XCTAssertFalse(app.alerts["Error"].exists, "Food save displayed an error")
        XCTAssertTrue(foodList.exists, "Food list did not return after save")

        // Reopen the same persisted item and save it again. This exercises
        // in-place updates of all eight nutrient children plus the existing
        // Ayurveda override, rather than only testing first insertion.
        let savedRow = app.staticTexts[originalName]
        scrollToElement(savedRow, in: app, maximumSwipes: 30)
        revealTrailingActions(for: savedRow, in: app)
        let edit = app.buttons["Edit \(originalName)"]
        XCTAssertTrue(
            edit.waitForExistence(timeout: 5),
            "The edit action was not revealed"
        )
        edit.tap()
        let editTitle = app.staticTexts["Edit Food"]
        XCTAssertTrue(editTitle.waitForExistence(timeout: 10))

        let editedName = originalName + " Edited"
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()
        name.typeText(" Edited")
        XCTAssertTrue(returnKey.waitForExistence(timeout: 5))
        returnKey.tap()
        let editKeyboardDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.keyboards.firstMatch
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [editKeyboardDismissed], timeout: 5),
            .completed,
            "Edit keyboard did not dismiss"
        )
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let editClosed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: editTitle
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [editClosed], timeout: 20),
            .completed,
            "Second food save did not close the editor. Hierarchy: \(app.debugDescription)"
        )
        XCTAssertFalse(app.alerts["Error"].exists, "Second food save displayed an error")
        scrollToElement(app.staticTexts[editedName], in: app, maximumSwipes: 30)
        print("VAL1-FOOD-EDITOR-SAVE|PASS|first-and-edit")
    }

    func testDuplicateCatalogFoodPreservesDisplayedServingWeight() throws {
        let app = XCUIApplication(bundleIdentifier: ayurvedaasanayogaBundleID)
        app.launchArguments = [
            "-uiTestNoAds",
            "-skipPermissionPrompts",
            "-lastSelectedTabRoot", "2"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let preparing = app.staticTexts["Preparing database…"]
        if preparing.waitForExistence(timeout: 5) {
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: preparing
            )
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 90), .completed)
        }

        let defaultFilter = app.buttons["Default"]
        XCTAssertTrue(defaultFilter.waitForExistence(timeout: 15))
        tapVisibleCenter(of: defaultFilter, in: app)
        XCTAssertTrue(app.staticTexts["Default list"].waitForExistence(timeout: 10))

        let source = app.staticTexts["Aam panna"]
        scrollToElement(source, in: app, maximumSwipes: 20)
        revealTrailingActions(for: source, in: app)

        let editorTitle = app.staticTexts["Add Food"]
        let duplicate = app.buttons["Duplicate Aam panna"]
        if !editorTitle.waitForExistence(timeout: 2) {
            XCTAssertTrue(
                duplicate.waitForExistence(timeout: 5),
                "Duplicate action was not revealed. Hierarchy: \(app.debugDescription)"
            )
            duplicate.tap()
        }

        XCTAssertTrue(editorTitle.waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["Copy of Aam panna"].waitForExistence(timeout: 5))

        let duplicatedPhoto = app.buttons["food-editor-photo"]
        XCTAssertTrue(duplicatedPhoto.waitForExistence(timeout: 5))
        XCTAssertEqual(
            duplicatedPhoto.value as? String,
            "image",
            "The duplicate must materialize the catalogue image"
        )

        let servingWeight = app.textFields["food-editor-serving-weight"]
        XCTAssertTrue(servingWeight.waitForExistence(timeout: 5))
        XCTAssertEqual(
            servingWeight.value as? String,
            "7.86",
            "The duplicate must preserve the 7.86 g shown by the source row"
        )
        print("VAL1-DUPLICATE-SERVING|PASS|Aam panna=7.86g")
    }

    func testDoshaChipCapsulesScaleAndWrapForFoodAndExercise() throws {
        let app = XCUIApplication(bundleIdentifier: ayurvedaasanayogaBundleID)
        let commonArguments = [
            "-uiTestNoAds",
            "-skipPermissionPrompts",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityLarge"
        ]

        app.launchArguments = commonArguments + ["-lastSelectedTabRoot", "9"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        waitForDatabasePreparation(in: app)

        let exerciseDefault = app.buttons["Default"]
        XCTAssertTrue(exerciseDefault.waitForExistence(timeout: 15))
        tapVisibleCenter(of: exerciseDefault, in: app)
        let exerciseRow = app.staticTexts["Advasana"].firstMatch
        scrollToElement(exerciseRow, in: app, maximumSwipes: 25)
        assertWholeDoshaCapsules(near: exerciseRow, in: app)

        app.terminate()
        app.launchArguments = commonArguments + ["-lastSelectedTabRoot", "2"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        waitForDatabasePreparation(in: app)

        let foodDefault = app.buttons["Default"]
        XCTAssertTrue(foodDefault.waitForExistence(timeout: 15))
        // WrappingSegmentedControl reports a displaced accessibility frame on
        // iOS 26 at large Dynamic Type sizes. Tap the visible final segment.
        app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.94, dy: 0.137)
        ).tap()
        XCTAssertTrue(app.staticTexts["Default list"].waitForExistence(timeout: 10))
        let foodRow = app.staticTexts["Aam panna"].firstMatch
        scrollToElement(foodRow, in: app, maximumSwipes: 25)
        assertWholeDoshaCapsules(near: foodRow, in: app)
        print("VAL1-DOSHA-CHIPS|PASS|food-and-exercise|one-line-capsules,max-two-rows")
    }

    func testCreateTrainingPlanWithoutValidationError() throws {
        let app = XCUIApplication(bundleIdentifier: ayurvedaasanayogaBundleID)
        app.launchArguments = [
            "-uiTestNoAds",
            "-skipPermissionPrompts",
            "-lastSelectedTabRoot", "9"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let preparing = app.staticTexts["Preparing database…"]
        if preparing.waitForExistence(timeout: 5) {
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: preparing
            )
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 90), .completed)
        }

        let plansFilter = app.buttons["Training Plans"]
        XCTAssertTrue(plansFilter.waitForExistence(timeout: 15))
        tapVisibleCenter(of: plansFilter, in: app)
        XCTAssertTrue(app.staticTexts["Training Plans"].waitForExistence(timeout: 10))
        tapFloatingButton(in: app)

        let editorTitle = app.staticTexts["New Training Plan"]
        XCTAssertTrue(editorTitle.waitForExistence(timeout: 10))
        let name = app.textFields["training-plan-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        tapVisibleCenter(of: name, in: app)
        let planName = "UI Training Plan \(UUID().uuidString.prefix(8))"
        name.typeText(planName)
        app.keyboards.buttons["Return"].tap()

        let searchToggle = app.descendants(matching: .any)["global-search-toggle"]
        XCTAssertTrue(searchToggle.waitForExistence(timeout: 5))
        tapVisibleCenter(of: searchToggle, in: app)
        let search = app.textFields["global-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        tapVisibleCenter(of: search, in: app)
        search.typeText("Abdominal Lock")
        let catalogExercise = app.staticTexts[
            "Abdominal Lock (Uddiyana Bandha)"
        ]
        XCTAssertTrue(catalogExercise.waitForExistence(timeout: 15))
        tapVisibleCenter(of: catalogExercise, in: app)

        let save = app.buttons["training-plan-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        let editorClosed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: editorTitle
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [editorClosed], timeout: 20),
            .completed,
            "Training-plan save failed. Hierarchy: \(app.debugDescription)"
        )
        XCTAssertFalse(app.alerts["Error"].exists)
        print("VAL1-TRAINING-PLAN-SAVE|PASS|catalog-exercise")
    }

    func testCreateMealPlanWithoutValidationError() throws {
        let app = XCUIApplication(bundleIdentifier: ayurvedaasanayogaBundleID)
        app.launchArguments = [
            "-uiTestNoAds",
            "-skipPermissionPrompts",
            "-lastSelectedTabRoot", "2"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let preparing = app.staticTexts["Preparing database…"]
        if preparing.waitForExistence(timeout: 5) {
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: preparing
            )
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 90), .completed)
        }

        let plansFilter = app.buttons["Meal Plans"]
        XCTAssertTrue(plansFilter.waitForExistence(timeout: 15))
        tapVisibleCenter(of: plansFilter, in: app)
        XCTAssertTrue(app.staticTexts["Meal Plans"].waitForExistence(timeout: 10))
        tapFloatingButton(in: app)

        let editorTitle = app.staticTexts["New Meal Plan"]
        XCTAssertTrue(editorTitle.waitForExistence(timeout: 10))
        let name = app.textFields["meal-plan-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        tapVisibleCenter(of: name, in: app)
        name.typeText("UI Meal Plan \(UUID().uuidString.prefix(8))")
        app.keyboards.buttons["Return"].tap()

        let searchToggle = app.descendants(matching: .any)[
            "global-search-toggle"
        ]
        XCTAssertTrue(searchToggle.waitForExistence(timeout: 5))
        tapVisibleCenter(of: searchToggle, in: app)
        let search = app.textFields["global-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        tapVisibleCenter(of: search, in: app)
        search.typeText("Aam panna")
        let catalogFood = app.staticTexts["Aam panna"]
        XCTAssertTrue(catalogFood.waitForExistence(timeout: 15))
        tapVisibleCenter(of: catalogFood, in: app)

        let save = app.buttons["meal-plan-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let editorClosed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: editorTitle
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [editorClosed], timeout: 20),
            .completed,
            "Meal-plan save failed. Hierarchy: \(app.debugDescription)"
        )
        XCTAssertFalse(app.alerts["Error"].exists)
        print("VAL1-MEAL-PLAN-SAVE|PASS|catalog-food")
    }

    func testCreateShoppingListWithoutCrash() throws {
        let app = XCUIApplication(bundleIdentifier: ayurvedaasanayogaBundleID)
        app.launchArguments = [
            "-uiTestNoAds",
            "-skipPermissionPrompts",
            "-lastSelectedTabRoot", "5"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        waitForDatabasePreparation(in: app)

        let allLists = app.buttons["All Lists"]
        if allLists.waitForExistence(timeout: 8) {
            allLists.tap()
        }
        XCTAssertTrue(
            app.staticTexts["Shopping Lists"].waitForExistence(timeout: 15),
            "Shopping Lists did not open. Hierarchy: \(app.debugDescription)"
        )

        tapFloatingButton(in: app)

        let name = app.textFields["shopping-list-name"]
        XCTAssertTrue(
            name.waitForExistence(timeout: 10),
            "New shopping-list editor did not open"
        )
        let suffix = String(UUID().uuidString.prefix(8))
        let savedName = "New Shopping List UI \(suffix)"
        tapVisibleCenter(of: name, in: app)
        name.typeText(" UI \(suffix)")
        app.keyboards.buttons["Return"].tap()

        let searchToggle = app.descendants(matching: .any)[
            "global-search-toggle"
        ]
        XCTAssertTrue(searchToggle.waitForExistence(timeout: 5))
        tapVisibleCenter(of: searchToggle, in: app)
        let search = app.textFields["global-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        tapVisibleCenter(of: search, in: app)
        search.typeText("Aam panna")
        let catalogFood = app.staticTexts["Aam panna"].firstMatch
        XCTAssertTrue(catalogFood.waitForExistence(timeout: 15))
        tapVisibleCenter(of: catalogFood, in: app)

        let save = app.buttons["shopping-list-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        XCTAssertTrue(
            app.staticTexts["Shopping Lists"].waitForExistence(timeout: 15),
            "Shopping-list save did not return to the list. State: \(app.state.rawValue)"
        )
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(app.alerts["Unable to Save"].exists)

        let savedRow = app.staticTexts[savedName]
        XCTAssertTrue(savedRow.waitForExistence(timeout: 10))
        tapVisibleCenter(of: savedRow, in: app)
        let reopenedName = app.textFields["shopping-list-name"]
        XCTAssertTrue(reopenedName.waitForExistence(timeout: 10))
        tapVisibleCenter(of: reopenedName, in: app)
        reopenedName.typeText(" Edited")
        app.keyboards.buttons["Return"].tap()
        app.buttons["shopping-list-save"].tap()
        XCTAssertTrue(
            app.staticTexts["Shopping Lists"].waitForExistence(timeout: 15)
        )
        let editedRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Edited")
        ).firstMatch
        XCTAssertTrue(editedRow.waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
        print("VAL1-SHOPPING-LIST-SAVE|PASS|catalog-food-and-edit")
    }

    func testAddCatalogFoodToStorageWithoutCrash() throws {
        let app = XCUIApplication(bundleIdentifier: ayurvedaasanayogaBundleID)
        app.launchArguments = [
            "-uiTestNoAds",
            "-skipPermissionPrompts",
            "-lastSelectedTabRoot", "4"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        waitForDatabasePreparation(in: app)
        XCTAssertTrue(
            app.staticTexts["Storage"].waitForExistence(timeout: 15),
            "Storage did not open. Hierarchy: \(app.debugDescription)"
        )

        tapFloatingButton(in: app)
        let editorTitle = app.staticTexts["Add to Storage"]
        XCTAssertTrue(editorTitle.waitForExistence(timeout: 10))

        let search = app.textFields["global-search-field"]
        XCTAssertTrue(
            search.waitForExistence(timeout: 10),
            "Storage food search did not activate"
        )
        tapVisibleCenter(of: search, in: app)
        search.typeText("Aam panna")
        let catalogFood = app.staticTexts["Aam panna"].firstMatch
        XCTAssertTrue(catalogFood.waitForExistence(timeout: 15))
        tapVisibleCenter(of: catalogFood, in: app)

        let save = app.buttons["storage-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let editorClosed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: editorTitle
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [editorClosed], timeout: 15),
            .completed,
            "Storage save did not close. State: \(app.state.rawValue)"
        )
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(app.alerts["Unable to Save"].exists)
        print("VAL1-STORAGE-SAVE|PASS|catalog-food")
    }

    func testSingleColdLaunchMetric() throws {
        let app = XCUIApplication(bundleIdentifier: ayurvedaasanayogaBundleID)
        app.launchArguments = [
            "-uiTestNoAds",
            "-ayurvedaasanayogaLaunchProfile",
            "-ayurvedaasanayogaPlannerTelemetry"
        ]

        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(
            metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)],
            options: options
        ) {
            app.launch()
        }
    }

    private func scrollToElement(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 12
    ) {
        var swipes = 0
        func isVisiblyOnScreen() -> Bool {
            guard element.exists, !element.frame.isEmpty else { return false }
            let frame = element.frame
            return frame.maxY > app.frame.minY + 150
                && frame.minY < app.frame.maxY - 170
        }

        while !isVisiblyOnScreen() && swipes < maximumSwipes {
            if element.exists, !element.frame.isEmpty {
                let delta = (app.frame.midY - element.frame.midY) / app.frame.height
                let endY = min(max(0.5 + delta, 0.25), 0.75)
                app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                ).press(
                    forDuration: 0.05,
                    thenDragTo: app.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: endY)
                    )
                )
            } else {
                app.swipeUp(velocity: .slow)
            }
            swipes += 1
        }
        XCTAssertTrue(
            isVisiblyOnScreen(),
            "Element did not become visible after \(swipes) swipe(s): \(element)"
        )
    }

    private func assertWholeDoshaCapsules(
        near row: XCUIElement,
        in app: XCUIApplication
    ) {
        let identifiers = [
            "ayurveda-dosha-chip-vata",
            "ayurveda-dosha-chip-pitta",
            "ayurveda-dosha-chip-kapha"
        ]
        let chips = identifiers.compactMap { identifier -> XCUIElement? in
            let query = app.descendants(matching: .any).matching(
                identifier: identifier
            )
            guard query.firstMatch.waitForExistence(timeout: 5) else {
                return nil
            }

            return (0..<query.count)
                .map { query.element(boundBy: $0) }
                .filter {
                    $0.exists
                        && !$0.frame.isEmpty
                        && $0.frame.intersects(app.frame)
                }
                .min {
                    abs($0.frame.midY - row.frame.midY)
                        < abs($1.frame.midY - row.frame.midY)
                }
        }

        XCTAssertEqual(chips.count, 3, "Expected all three dosha capsules")
        guard chips.count == 3 else { return }

        let heights = chips.map { $0.frame.height }
        XCTAssertLessThanOrEqual(
            (heights.max() ?? 0) - (heights.min() ?? 0),
            2,
            "A dosha label wrapped inside its capsule"
        )

        var rowCenters: [CGFloat] = []
        for center in chips.map({ $0.frame.midY }).sorted() {
            if rowCenters.allSatisfy({ abs($0 - center) > 3 }) {
                rowCenters.append(center)
            }
        }
        XCTAssertLessThanOrEqual(
            rowCenters.count,
            2,
            "Dosha capsules must use no more than two rows"
        )
    }

    private func waitForDatabasePreparation(in app: XCUIApplication) {
        let preparing = app.staticTexts["Preparing database…"]
        guard preparing.waitForExistence(timeout: 3) else { return }
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: preparing
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [ready], timeout: 90),
            .completed,
            "The database did not finish preparing"
        )
    }

    private func revealTrailingActions(
        for element: XCUIElement,
        in app: XCUIApplication
    ) {
        let normalizedY = min(
            max(element.frame.midY / app.frame.height, 0.25),
            0.72
        )
        app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.82, dy: normalizedY)
        ).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.18, dy: normalizedY)
            )
        )
    }

    private func tapFloatingButton(in app: XCUIApplication) {
        let addImage = app.images["widget.large.badge.plus"]
        if addImage.exists && addImage.isHittable {
            addImage.tap()
            return
        }
        let sparkleImage = app.images["sparkles"]
        if sparkleImage.exists && sparkleImage.isHittable {
            sparkleImage.tap()
            return
        }
        app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.815, dy: 0.84)
        ).tap()
    }

    private func tapVisibleCenter(of element: XCUIElement, in app: XCUIApplication) {
        let appFrame = app.frame
        let elementFrame = element.frame
        XCTAssertFalse(elementFrame.isEmpty, "Element has no visible frame: \(element)")
        app.coordinate(
            withNormalizedOffset: CGVector(
                dx: elementFrame.midX / appFrame.width,
                dy: elementFrame.midY / appFrame.height
            )
        ).tap()
    }
}
