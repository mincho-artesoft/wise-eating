import XCTest

/// End-to-end coverage for every primary user record that can be mutated from
/// the production UI. Every test creates its own uniquely named records and
/// removes them again through the same UI so runs are repeatable.
final class VAL1CRUDUITests: XCTestCase {
    private let bundleID = "AyurvedaAsanaYoga.Arte-Soft"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFoodRecipeAndMenuCRUDIncludingDuplication() throws {
        let app = launch(tab: 2)

        try exerciseFoodFamilyCRUD(
            in: app,
            filter: "Foods",
            editorTitle: "Add Food",
            editTitle: "Edit Food",
            nameIdentifier: "food-editor-name",
            saveIdentifier: "food-editor-save",
            needsServingWeight: true
        )
        try exerciseFoodFamilyCRUD(
            in: app,
            filter: "Recipes",
            editorTitle: "Add Recipe",
            editTitle: "Edit Recipe",
            nameIdentifier: "recipe-editor-name",
            saveIdentifier: "recipe-editor-save"
        )
        try exerciseFoodFamilyCRUD(
            in: app,
            filter: "Menus",
            editorTitle: "Add Menu",
            editTitle: "Edit Menu",
            nameIdentifier: "menu-editor-name",
            saveIdentifier: "menu-editor-save"
        )

        print("VAL1-CRUD|PASS|food,recipe,menu|create,edit,duplicate,delete")
    }

    func testExerciseAndWorkoutCRUD() throws {
        let app = launch(tab: 9)

        try exerciseNamedRecordCRUD(
            in: app,
            filter: "Exercises",
            addTitle: "Add Exercise",
            editTitle: "Edit Exercise",
            nameIdentifier: "exercise-editor-name",
            saveIdentifier: "exercise-editor-save",
            prefix: "Exercise"
        )
        try exerciseNamedRecordCRUD(
            in: app,
            filter: "Workouts",
            addTitle: "New Workout",
            editTitle: "Edit Workout",
            nameIdentifier: "workout-editor-name",
            saveIdentifier: "workout-editor-save",
            prefix: "Workout"
        )

        print("VAL1-CRUD|PASS|exercise,workout|create,edit,delete")
    }

    func testMealPlanCRUD() throws {
        let app = launch(tab: 2)
        selectFilter("Meal Plans", in: app)

        let originalName = uniqueName("Meal Plan")
        tapFloatingButton(in: app)
        XCTAssertTrue(app.staticTexts["New Meal Plan"].waitForExistence(timeout: 10))
        enter(originalName, into: app.textFields["meal-plan-name"], in: app)
        addCatalogResult(named: "Aam panna", in: app)
        saveEditor(identifier: "meal-plan-save", title: "New Meal Plan", in: app)

        let editedName = originalName + " Edited"
        editNamedRow(
            originalName,
            editedName: editedName,
            editorTitle: "Edit Meal Plan",
            fieldIdentifier: "meal-plan-name",
            saveIdentifier: "meal-plan-save",
            in: app
        )
        deleteNamedRow(editedName, preferredDeleteButton: "Delete Plan Only", in: app)
        assertNamedRowsAbsentAfterRelaunch(
            [editedName],
            tab: 2,
            filter: "Meal Plans",
            in: app
        )
        print("VAL1-CRUD|PASS|meal-plan|create,edit,delete")
    }

    func testTrainingPlanCRUD() throws {
        let app = launch(tab: 9)
        selectFilter("Training Plans", in: app)

        let originalName = uniqueName("Training Plan")
        tapFloatingButton(in: app)
        XCTAssertTrue(app.staticTexts["New Training Plan"].waitForExistence(timeout: 10))
        enter(originalName, into: app.textFields["training-plan-name"], in: app)
        addCatalogResult(named: "Abdominal Lock", in: app)
        saveEditor(identifier: "training-plan-save", title: "New Training Plan", in: app)

        let editedName = originalName + " Edited"
        editNamedRow(
            originalName,
            editedName: editedName,
            editorTitle: "Edit Training Plan",
            fieldIdentifier: "training-plan-name",
            saveIdentifier: "training-plan-save",
            in: app
        )
        deleteNamedRow(editedName, preferredDeleteButton: "Delete Plan Only", in: app)
        assertNamedRowsAbsentAfterRelaunch(
            [editedName],
            tab: 9,
            filter: "Training Plans",
            in: app
        )
        print("VAL1-CRUD|PASS|training-plan|create,edit,delete")
    }

    func testShoppingListCRUDIncludingDuplication() throws {
        let app = launch(tab: 5)
        if app.buttons["All Lists"].waitForExistence(timeout: 5) {
            app.buttons["All Lists"].tap()
        }
        XCTAssertTrue(app.staticTexts["Shopping Lists"].waitForExistence(timeout: 15))

        let originalName = uniqueName("Shopping List")
        tapFloatingButton(in: app)
        let name = app.textFields["shopping-list-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        replaceText(in: name, with: originalName, app: app)
        addCatalogResult(named: "Aam panna", in: app)
        saveEditor(identifier: "shopping-list-save", fieldIdentifier: "shopping-list-name", in: app)

        let editedName = originalName + " Edited"
        openNamedRow(originalName, in: app)
        replaceText(in: app.textFields["shopping-list-name"], with: editedName, app: app)
        saveEditor(identifier: "shopping-list-save", fieldIdentifier: "shopping-list-name", in: app)

        revealTrailingActions(for: namedRow(editedName, in: app), in: app)
        let duplicate = app.buttons["Duplicate \(editedName)"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5))
        tapVisibleCenter(of: duplicate, in: app)
        XCTAssertTrue(app.textFields["shopping-list-name"].waitForExistence(timeout: 10))
        let duplicateName = editedName + " Copy"
        replaceText(in: app.textFields["shopping-list-name"], with: duplicateName, app: app)
        saveEditor(identifier: "shopping-list-save", fieldIdentifier: "shopping-list-name", in: app)

        deleteNamedRow(duplicateName, in: app)
        deleteNamedRow(editedName, in: app)
        assertNamedRowsAbsentAfterRelaunch(
            [duplicateName, editedName],
            tab: 5,
            in: app
        )
        print("VAL1-CRUD|PASS|shopping-list|create,edit,duplicate,delete")
    }

    func testStorageCRUDAndBatchMutation() throws {
        // A unique user food prevents this test from colliding with storage
        // records created manually or by another UI test.
        let foodName = uniqueName("Storage Food")
        var app = launch(tab: 2)
        selectFilter("Foods", in: app)
        createSimpleFood(named: foodName, in: app)

        app.terminate()
        app = launch(tab: 4)
        XCTAssertTrue(app.staticTexts["Storage"].waitForExistence(timeout: 15))
        tapFloatingButton(in: app)
        XCTAssertTrue(app.staticTexts["Add to Storage"].waitForExistence(timeout: 10))
        let search = app.textFields["global-search-field"]
        enter(foodName, into: search, in: app, dismissKeyboard: false)
        let result = app.staticTexts[foodName].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        tapVisibleCenter(of: result, in: app)
        saveEditor(identifier: "storage-save", title: "Add to Storage", in: app)

        openNamedRow(foodName, in: app)
        let editBatches = app.buttons["Edit Batches"]
        XCTAssertTrue(editBatches.waitForExistence(timeout: 10))
        editBatches.tap()
        let addBatch = app.buttons["Add Another Batch"]
        XCTAssertTrue(addBatch.waitForExistence(timeout: 10))
        tapVisibleCenter(of: addBatch, in: app)
        XCTAssertEqual(app.state, .runningForeground)
        tapVisibleCenter(of: app.buttons["Close"].firstMatch, in: app)

        deleteNamedRow(foodName, in: app)
        assertNamedRowsAbsentAfterRelaunch([foodName], tab: 4, in: app)

        relaunch(app, tab: 2)
        selectFilter("Foods", in: app)
        deleteNamedRow(foodName, in: app)
        assertNamedRowsAbsentAfterRelaunch(
            [foodName],
            tab: 2,
            filter: "Foods",
            in: app
        )
        print("VAL1-CRUD|PASS|storage|create,edit-batches,delete")
    }

    func testNodeCRUD() throws {
        let app = launch(tab: 10)
        XCTAssertTrue(app.staticTexts["Notes"].waitForExistence(timeout: 15))

        let originalText = uniqueName("Note")
        tapFloatingButton(in: app)
        XCTAssertTrue(app.staticTexts["New Node"].waitForExistence(timeout: 10))
        enter(originalText, into: app.textViews["node-editor-text"], in: app)
        saveEditor(identifier: "node-editor-save", title: "New Node", in: app)

        let row = namedRow(originalText, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        tapVisibleCenter(of: row, in: app)
        XCTAssertTrue(app.staticTexts["Edit Node"].waitForExistence(timeout: 10))
        let editedText = originalText + " Edited"
        replaceText(in: app.textViews["node-editor-text"], with: editedText, app: app)
        saveEditor(identifier: "node-editor-save", title: "Edit Node", in: app)
        deleteNamedRow(editedText, in: app)
        assertNamedRowsAbsentAfterRelaunch([editedText], tab: 10, in: app)
        print("VAL1-CRUD|PASS|node|create,edit,delete")
    }

    func testProfileCRUDWithRelaunchPersistence() throws {
        let profileArguments = ["-uiTestPremium"]
        let app = launch(tab: 10, additionalArguments: profileArguments)
        openProfilesDrawer(in: app)

        let originalName = uniqueName("Profile")
        let addProfile = app.buttons["profile-add-button"]
        XCTAssertTrue(addProfile.waitForExistence(timeout: 10))
        XCTAssertTrue(addProfile.isEnabled)
        tapVisibleCenter(of: addProfile, in: app)

        XCTAssertTrue(app.staticTexts["New Profile"].waitForExistence(timeout: 10))
        enter(
            originalName,
            into: app.textFields["profile-wizard-name"],
            in: app
        )
        advanceProfileWizard(
            from: "What's your name?",
            to: "Add your photo",
            in: app
        )
        advanceProfileWizard(
            from: "Add your photo",
            to: "When is your birthday?",
            in: app
        )
        advanceProfileWizard(
            from: "When is your birthday?",
            to: "What's your biological sex?",
            in: app
        )
        advanceProfileWizard(
            from: "What's your biological sex?",
            to: "What's your height?",
            in: app
        )
        advanceProfileWizard(
            from: "What's your height?",
            to: "What's your weight?",
            in: app
        )
        advanceProfileWizard(
            from: "What's your weight?",
            to: "Your traditional constitution",
            in: app
        )

        let vata = app.buttons["ayurveda-constitution-option-vata"]
        XCTAssertTrue(vata.waitForExistence(timeout: 10))
        tapVisibleCenter(of: vata, in: app)
        let constitutionContinue = app.buttons[
            "ayurveda-constitution-continue"
        ]
        XCTAssertTrue(constitutionContinue.waitForExistence(timeout: 5))
        XCTAssertTrue(constitutionContinue.isEnabled)
        tapVisibleCenter(of: constitutionContinue, in: app)
        XCTAssertTrue(
            app.staticTexts["Your constitution result"]
                .waitForExistence(timeout: 10)
        )
        let constitutionFinish = app.buttons["ayurveda-constitution-finish"]
        XCTAssertTrue(constitutionFinish.waitForExistence(timeout: 5))
        tapVisibleCenter(of: constitutionFinish, in: app)
        XCTAssertTrue(app.staticTexts["Meal Times"].waitForExistence(timeout: 10))

        advanceProfileWizard(from: "Meal Times", to: "Workout Times", in: app)
        advanceProfileWizard(
            from: "Workout Times",
            to: "Priority Vitamins",
            in: app
        )
        advanceProfileWizard(
            from: "Priority Vitamins",
            to: "Priority Minerals",
            in: app
        )
        advanceProfileWizard(
            from: "Priority Minerals",
            to: "Any Allergies?",
            in: app
        )
        advanceProfileWizard(
            from: "Any Allergies?",
            to: "Confirm Your Details",
            in: app
        )

        let saveProfile = app.buttons["profile-wizard-save"]
        XCTAssertTrue(saveProfile.waitForExistence(timeout: 5))
        XCTAssertTrue(saveProfile.isEnabled)
        tapVisibleCenter(of: saveProfile, in: app)
        XCTAssertTrue(
            profileRow(originalName, in: app).waitForExistence(timeout: 30),
            "New profile did not appear after saving"
        )
        assertNoSaveError(in: app)

        let editedName = originalName + " Edited"
        revealTrailingActions(for: profileRow(originalName, in: app), in: app)
        let edit = app.buttons["Edit \(originalName)"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        tapVisibleCenter(of: edit, in: app)
        XCTAssertTrue(app.staticTexts["Edit Profile"].waitForExistence(timeout: 10))
        replaceText(
            in: app.textFields["profile-editor-name"],
            with: editedName,
            app: app
        )
        saveEditor(
            identifier: "profile-editor-save",
            title: "Edit Profile",
            in: app
        )
        XCTAssertTrue(profileRow(editedName, in: app).waitForExistence(timeout: 15))

        relaunch(
            app,
            tab: 10,
            additionalArguments: profileArguments
        )
        openProfilesDrawer(in: app)
        XCTAssertTrue(
            profileRow(editedName, in: app).waitForExistence(timeout: 15),
            "Edited profile name did not persist across relaunch"
        )
        XCTAssertFalse(app.staticTexts[originalName].firstMatch.exists)

        deleteProfileNamedRow(editedName, in: app)
        // Profile deletion also removes its EventKit calendars asynchronously.
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        relaunch(
            app,
            tab: 10,
            additionalArguments: profileArguments
        )
        openProfilesDrawer(in: app)
        XCTAssertFalse(
            app.staticTexts[editedName].firstMatch.waitForExistence(timeout: 4),
            "Deleted profile returned after relaunch"
        )
        assertNoSaveError(in: app)
        print("VAL1-CRUD|PASS|profile|create,edit,delete,persist")
    }

    func testDailyMealAndTrainingEntryCRUD() throws {
        // Daily entries reference catalogue/user records, so use unique
        // user-owned records and remove them at the end of the scenario.
        let foodName = uniqueName("Daily Food")
        var app = launch(tab: 2)
        selectFilter("Foods", in: app)
        createSimpleFood(named: foodName, in: app)

        app.terminate()
        app = launch(tab: 0)
        addCatalogResult(named: foodName, in: app)
        let foodRowID = "meal-food-row-\(foodName)"
        let foodQuantityID = "meal-food-quantity-\(foodName)"
        XCTAssertTrue(
            app.descendants(matching: .any)[foodRowID]
                .waitForExistence(timeout: 15)
        )
        replaceText(
            in: app.textFields[foodQuantityID],
            with: "125",
            app: app
        )
        waitForDailyAutosave()

        // Relaunch proves that both create and update reached persistence,
        // rather than merely changing the current SwiftUI state.
        app.terminate()
        app = launch(tab: 0)
        let persistedFoodField = app.textFields[foodQuantityID]
        scrollToElement(persistedFoodField, in: app, maximumSwipes: 20)
        XCTAssertEqual(persistedFoodField.value as? String, "125")
        let persistedFoodRow = app.descendants(matching: .any)[foodRowID]
        revealTrailingActions(for: persistedFoodRow, in: app)
        let deleteFood = app.buttons["Delete meal food \(foodName)"]
        XCTAssertTrue(deleteFood.waitForExistence(timeout: 5))
        tapVisibleCenter(of: deleteFood, in: app)
        waitForDailyAutosave()

        app.terminate()
        app = launch(tab: 0)
        XCTAssertFalse(
            app.descendants(matching: .any)[foodRowID]
                .waitForExistence(timeout: 3),
            "Deleted daily food returned after relaunch"
        )

        app.terminate()
        app = launch(tab: 2)
        selectFilter("Foods", in: app)
        deleteNamedRow(foodName, in: app)
        assertNamedRowsAbsentAfterRelaunch(
            [foodName],
            tab: 2,
            filter: "Foods",
            in: app
        )

        let exerciseName = uniqueName("Daily Exercise")
        app.terminate()
        app = launch(tab: 9)
        selectFilter("Exercises", in: app)
        createSimpleExercise(named: exerciseName, in: app)

        app.terminate()
        app = launch(tab: 1)
        addCatalogResult(named: exerciseName, in: app)
        let exerciseRowID = "training-exercise-row-\(exerciseName)"
        let durationID = "training-exercise-duration-\(exerciseName)"
        XCTAssertTrue(
            app.descendants(matching: .any)[exerciseRowID]
                .waitForExistence(timeout: 15)
        )
        replaceText(in: app.textFields[durationID], with: "1200", app: app)
        waitForDailyAutosave()

        app.terminate()
        app = launch(tab: 1)
        let persistedDuration = app.textFields[durationID]
        scrollToElement(persistedDuration, in: app, maximumSwipes: 20)
        XCTAssertEqual(persistedDuration.value as? String, "1200")
        let persistedExerciseRow = app.descendants(matching: .any)[exerciseRowID]
        revealTrailingActions(for: persistedExerciseRow, in: app)
        let deleteExercise = app.buttons[
            "Delete training exercise \(exerciseName)"
        ]
        XCTAssertTrue(deleteExercise.waitForExistence(timeout: 5))
        tapVisibleCenter(of: deleteExercise, in: app)
        waitForDailyAutosave()

        app.terminate()
        app = launch(tab: 1)
        XCTAssertFalse(
            app.descendants(matching: .any)[exerciseRowID]
                .waitForExistence(timeout: 3),
            "Deleted daily exercise returned after relaunch"
        )

        app.terminate()
        app = launch(tab: 9)
        selectFilter("Exercises", in: app)
        deleteNamedRow(exerciseName, in: app)
        assertNamedRowsAbsentAfterRelaunch(
            [exerciseName],
            tab: 9,
            filter: "Exercises",
            in: app
        )
        print("VAL1-CRUD|PASS|daily-meal,daily-training|create,edit,delete,persist")
    }

    /// Recovery companion for interrupted UI runs. Production tests use the
    /// reserved `UI CRUD ` prefix, so this removes only automation artifacts
    /// through the same destructive controls a user sees. It never touches a
    /// normally named user record.
    func testZZZCleanupInterruptedCRUDArtifacts() throws {
        let app = launch(tab: 5)
        if app.buttons["All Lists"].waitForExistence(timeout: 3) {
            app.buttons["All Lists"].tap()
        }
        cleanupReservedRows(in: app)

        relaunch(app, tab: 4)
        cleanupReservedRows(in: app)

        relaunch(app, tab: 2)
        selectFilter("Meal Plans", in: app)
        cleanupReservedRows(
            preferredDeleteButton: "Delete Plan & Menus",
            in: app
        )
        for filter in ["Foods", "Recipes", "Menus"] {
            selectFilter(filter, in: app)
            cleanupReservedRows(in: app)
        }

        relaunch(app, tab: 9)
        selectFilter("Training Plans", in: app)
        cleanupReservedRows(
            preferredDeleteButton: "Delete Plan & Workouts",
            in: app
        )
        for filter in ["Exercises", "Workouts"] {
            selectFilter(filter, in: app)
            cleanupReservedRows(in: app)
            if filter == "Exercises" {
                // Very old interrupted edit tests could leave an empty
                // nameNormalized value. Such rows cannot match search even
                // though their visible name has the reserved prefix, so make
                // a second bounded pass over the unfiltered first page.
                filterCurrentList(to: "", in: app)
                dismissKeyboard(in: app)
                collapseGlobalSearchIfNeeded(in: app)
                cleanupReservedRows(in: app, useSearch: false)
            }
        }

        relaunch(app, tab: 10)
        cleanupReservedRows(in: app, useSearch: false)
        relaunch(app, tab: 10, additionalArguments: ["-uiTestPremium"])
        openProfilesDrawer(in: app)
        cleanupReservedProfiles(in: app)
        print("VAL1-CRUD|PASS|cleanup|reserved-ui-artifacts")
    }

    // MARK: - Domain workflows

    private func exerciseFoodFamilyCRUD(
        in app: XCUIApplication,
        filter: String,
        editorTitle: String,
        editTitle: String,
        nameIdentifier: String,
        saveIdentifier: String,
        needsServingWeight: Bool = false
    ) throws {
        selectFilter(filter, in: app)
        let originalName = uniqueName(String(filter.dropLast(filter.hasSuffix("s") ? 1 : 0)))
        tapFloatingButton(in: app)
        XCTAssertTrue(app.staticTexts[editorTitle].waitForExistence(timeout: 10))
        enter(originalName, into: app.textFields[nameIdentifier], in: app)
        if needsServingWeight {
            enter("100", into: app.textFields["food-editor-serving-weight"], in: app)
        }
        saveEditor(identifier: saveIdentifier, title: editorTitle, in: app)

        let editedName = originalName + " Edited"
        editNamedRow(
            originalName,
            editedName: editedName,
            editorTitle: editTitle,
            fieldIdentifier: nameIdentifier,
            saveIdentifier: saveIdentifier,
            in: app
        )

        revealTrailingActions(for: namedRow(editedName, in: app), in: app)
        let duplicate = app.buttons["Duplicate \(editedName)"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5))
        tapVisibleCenter(of: duplicate, in: app)
        XCTAssertTrue(app.staticTexts[editorTitle].waitForExistence(timeout: 10))
        let duplicateField = app.textFields[nameIdentifier]
        XCTAssertTrue(duplicateField.waitForExistence(timeout: 5))
        let duplicateName = editedName + " Copy"
        replaceText(in: duplicateField, with: duplicateName, app: app)
        saveEditor(identifier: saveIdentifier, title: editorTitle, in: app)

        deleteNamedRow(duplicateName, in: app)
        deleteNamedRow(editedName, in: app)
        assertNamedRowsAbsentAfterRelaunch(
            [duplicateName, editedName],
            tab: 2,
            filter: filter,
            in: app
        )
    }

    private func exerciseNamedRecordCRUD(
        in app: XCUIApplication,
        filter: String,
        addTitle: String,
        editTitle: String,
        nameIdentifier: String,
        saveIdentifier: String,
        prefix: String
    ) throws {
        selectFilter(filter, in: app)
        let originalName = uniqueName(prefix)
        tapFloatingButton(in: app)
        XCTAssertTrue(app.staticTexts[addTitle].waitForExistence(timeout: 10))
        enter(originalName, into: app.textFields[nameIdentifier], in: app)
        saveEditor(identifier: saveIdentifier, title: addTitle, in: app)

        let editedName = originalName + " Edited"
        editNamedRow(
            originalName,
            editedName: editedName,
            editorTitle: editTitle,
            fieldIdentifier: nameIdentifier,
            saveIdentifier: saveIdentifier,
            in: app
        )
        deleteNamedRow(editedName, in: app)
        assertNamedRowsAbsentAfterRelaunch(
            [editedName],
            tab: 9,
            filter: filter,
            in: app
        )
    }

    private func createSimpleFood(named name: String, in app: XCUIApplication) {
        tapFloatingButton(in: app)
        XCTAssertTrue(app.staticTexts["Add Food"].waitForExistence(timeout: 10))
        enter(name, into: app.textFields["food-editor-name"], in: app)
        enter("100", into: app.textFields["food-editor-serving-weight"], in: app)
        saveEditor(identifier: "food-editor-save", title: "Add Food", in: app)
    }

    private func createSimpleExercise(named name: String, in app: XCUIApplication) {
        tapFloatingButton(in: app)
        XCTAssertTrue(app.staticTexts["Add Exercise"].waitForExistence(timeout: 10))
        enter(name, into: app.textFields["exercise-editor-name"], in: app)
        saveEditor(
            identifier: "exercise-editor-save",
            title: "Add Exercise",
            in: app
        )
    }

    private func cleanupReservedRows(
        preferredDeleteButton: String? = nil,
        in app: XCUIApplication,
        useSearch: Bool = true
    ) {
        let reservedPrefix = "UI CRUD "
        var removedCount = 0

        while removedCount < 100 {
            if useSearch, supportsGlobalListFiltering(in: app) {
                filterCurrentList(to: reservedPrefix, in: app)
            } else {
                RunLoop.current.run(until: Date().addingTimeInterval(0.75))
            }

            let candidates = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", reservedPrefix)
            )
            var candidate: XCUIElement?
            for index in 0..<candidates.count {
                let element = candidates.element(boundBy: index)
                if isVisible(element, in: app) {
                    candidate = element
                    break
                }
            }

            guard let candidate else { break }
            let name = candidate.label
            deleteNamedRow(
                name,
                preferredDeleteButton: preferredDeleteButton,
                in: app
            )
            removedCount += 1
        }

        XCTAssertLessThan(
            removedCount,
            100,
            "Cleanup exceeded its safety bound"
        )
    }

    // MARK: - UI primitives

    private func launch(
        tab: Int,
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: bundleID)
        relaunch(app, tab: tab, additionalArguments: additionalArguments)
        return app
    }

    private func relaunch(
        _ app: XCUIApplication,
        tab: Int,
        additionalArguments: [String] = []
    ) {
        app.launchArguments = [
            "-uiTestNoAds",
            "-skipPermissionPrompts",
            "-lastSelectedTabRoot", String(tab)
        ] + additionalArguments
        if app.state != .notRunning {
            app.terminate()
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        waitForDatabasePreparation(in: app)
        dismissWellnessCheckInIfNeeded(in: app)
        dismissRestoredDetailIfNeeded(in: app)
    }

    private func openProfilesDrawer(in app: XCUIApplication) {
        let opener = app.buttons["profile-drawer-button"]
        XCTAssertTrue(opener.waitForExistence(timeout: 15))
        tapVisibleCenter(of: opener, in: app)
        XCTAssertTrue(
            app.buttons["profile-add-button"].waitForExistence(timeout: 10),
            "Profiles drawer did not open"
        )
    }

    private func advanceProfileWizard(
        from currentTitle: String,
        to nextTitle: String,
        in app: XCUIApplication
    ) {
        XCTAssertTrue(app.staticTexts[currentTitle].waitForExistence(timeout: 10))
        let next = app.buttons["profile-wizard-continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: next
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        tapVisibleCenter(of: next, in: app)
        XCTAssertTrue(
            app.staticTexts[nextTitle].waitForExistence(timeout: 10),
            "Profile wizard did not advance from \(currentTitle) to \(nextTitle)"
        )
    }

    private func profileRow(
        _ name: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        let identified = app.descendants(matching: .any)[
            "profile-row-\(name)"
        ].firstMatch
        if identified.waitForExistence(timeout: 2) {
            scrollToElement(identified, in: app, maximumSwipes: 20)
            return identified
        }
        let fallback = app.staticTexts[name].firstMatch
        scrollToElement(fallback, in: app, maximumSwipes: 20)
        return fallback
    }

    private func deleteProfileNamedRow(
        _ name: String,
        in app: XCUIApplication
    ) {
        let row = profileRow(name, in: app)
        revealTrailingActions(for: row, in: app)
        let delete = app.buttons["Delete \(name)"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        tapVisibleCenter(of: delete, in: app)
        if app.alerts["Delete Profile"].waitForExistence(timeout: 1) {
            app.alerts["Delete Profile"].buttons["Delete"].tap()
        }
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: row
        )
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 20), .completed)
    }

    private func cleanupReservedProfiles(in app: XCUIApplication) {
        var removedCount = 0
        while removedCount < 12 {
            let candidates = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "UI CRUD Profile")
            )
            guard candidates.count > 0 else { break }
            let name = candidates.firstMatch.label
            deleteProfileNamedRow(name, in: app)
            removedCount += 1
        }
        XCTAssertLessThan(removedCount, 12, "Profile cleanup exceeded its safety bound")
    }

    private func assertNoSaveError(in app: XCUIApplication) {
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(app.alerts["Error"].exists)
        XCTAssertFalse(app.alerts["Unable to Save"].exists)
    }

    /// A disappearing SwiftUI row only proves that the view model changed.
    /// Relaunching and searching for the exact unique name proves that the
    /// create/edit/delete transaction really reached the user SQLite store.
    private func assertNamedRowsAbsentAfterRelaunch(
        _ names: [String],
        tab: Int,
        filter: String? = nil,
        in app: XCUIApplication
    ) {
        relaunch(app, tab: tab)
        if tab == 5, app.buttons["All Lists"].waitForExistence(timeout: 3) {
            app.buttons["All Lists"].tap()
        }
        if let filter {
            selectFilter(filter, in: app)
        }

        for name in names {
            if supportsGlobalListFiltering(in: app) {
                filterCurrentList(to: name, in: app)
            } else {
                RunLoop.current.run(until: Date().addingTimeInterval(1))
            }
            XCTAssertFalse(
                app.staticTexts[name].firstMatch.waitForExistence(timeout: 3),
                "\(name) returned after relaunch; deletion was not persisted"
            )
        }

        if supportsGlobalListFiltering(in: app) {
            filterCurrentList(to: "", in: app)
            dismissKeyboard(in: app)
            collapseGlobalSearchIfNeeded(in: app)
        }
    }

    private func supportsGlobalListFiltering(in app: XCUIApplication) -> Bool {
        let field = app.textFields["global-search-field"].firstMatch
        guard field.waitForExistence(timeout: 2) else { return false }
        // Notes exposes its own compact search field with the same legacy
        // identifier but has no global-search toggle. Treat it as a plain
        // list and verify the unique row directly after relaunch.
        return field.frame.width >= 40
            || app.descendants(matching: .any)["global-search-toggle"]
                .firstMatch.exists
    }

    private func dismissRestoredDetailIfNeeded(in app: XCUIApplication) {
        let detailTitles = [
            "Food Details", "Recipe Details", "Menu Details",
            "Exercise Details", "Workout Details",
            "Meal Plan Details", "Training Plan Details"
        ]
        guard detailTitles.contains(where: { app.staticTexts[$0].exists }) else {
            return
        }
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    private func selectFilter(_ label: String, in app: XCUIApplication) {
        collapseGlobalSearchIfNeeded(in: app)
        let identified = app.buttons["segment-\(label)"]
        let button = identified.waitForExistence(timeout: 3)
            ? identified
            : app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 15), "Missing \(label) filter")
        // WrappingSegmentedControl currently reports a frame displaced into
        // the first list row on iOS 26. Tap the visible segment strip rather
        // than that incorrect accessibility frame. The identifiers above
        // still prove that the requested production control is present.
        let xByLabel: [String: CGFloat] = [
            "Foods": 0.07,
            "Recipes": 0.20,
            "Menus": 0.36,
            "Meal Plans": 0.54,
            "Exercises": 0.11,
            "Workouts": 0.31,
            "Training Plans": 0.55
        ]
        let x = xByLabel[label] ?? 0.5
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.137)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    private func addCatalogResult(named query: String, in app: XCUIApplication) {
        let toggle = app.descendants(matching: .any)["global-search-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        tapVisibleCenter(of: toggle, in: app)
        let search = app.textFields["global-search-field"]
        enter(query, into: search, in: app, dismissKeyboard: false)
        let result = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", query)
        ).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "Missing catalog result for \(query)")
        tapVisibleCenter(of: result, in: app)
    }

    private func editNamedRow(
        _ currentName: String,
        editedName: String,
        editorTitle: String,
        fieldIdentifier: String,
        saveIdentifier: String,
        in app: XCUIApplication
    ) {
        let row = namedRow(currentName, in: app)
        revealTrailingActions(for: row, in: app)
        let edit = app.buttons["Edit \(currentName)"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Missing edit action for \(currentName)")
        tapVisibleCenter(of: edit, in: app)
        XCTAssertTrue(app.staticTexts[editorTitle].waitForExistence(timeout: 10))
        replaceText(in: app.textFields[fieldIdentifier], with: editedName, app: app)
        saveEditor(identifier: saveIdentifier, title: editorTitle, in: app)
    }

    private func deleteNamedRow(
        _ name: String,
        preferredDeleteButton: String? = nil,
        in app: XCUIApplication
    ) {
        let row = namedRow(name, in: app)
        revealTrailingActions(for: row, in: app)
        let delete = app.buttons["Delete \(name)"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Missing delete action for \(name)")
        tapVisibleCenter(of: delete, in: app)

        if let preferredDeleteButton,
           app.buttons[preferredDeleteButton].waitForExistence(timeout: 3) {
            app.buttons[preferredDeleteButton].tap()
        } else if app.alerts.firstMatch.waitForExistence(timeout: 1) {
            let destructive = app.alerts.firstMatch.buttons["Delete"]
            if destructive.exists { destructive.tap() }
        }

        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: row
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [gone], timeout: 15),
            .completed,
            "\(name) remained visible after delete"
        )
    }

    private func openNamedRow(_ name: String, in app: XCUIApplication) {
        let row = namedRow(name, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        tapVisibleCenter(of: row, in: app)
    }

    private func namedRow(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let row = app.staticTexts[name].firstMatch
        if row.waitForExistence(timeout: 1), isVisible(row, in: app) {
            return row
        }

        // All records made by this suite have unique names. Filtering through
        // the production search UI avoids depending on the row's old scroll
        // position after an edit changes its sort order.
        if name.hasPrefix("UI CRUD ") {
            filterCurrentList(to: name, in: app)
        }
        scrollToElement(row, in: app, maximumSwipes: 35)
        return row
    }

    private func isVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, !element.frame.isEmpty else { return false }
        return element.frame.maxY >= app.frame.minY + 100
            && element.frame.minY <= app.frame.maxY - 100
    }

    private func filterCurrentList(to query: String, in app: XCUIApplication) {
        let field = app.textFields["global-search-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Missing global search field")

        if field.frame.width < 40 {
            let toggle = app.descendants(matching: .any)["global-search-toggle"].firstMatch
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Missing global search toggle")
            tapVisibleCenter(of: toggle, in: app)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }

        replaceText(in: field, with: query, app: app, dismissKeyboard: false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.45))
    }

    private func collapseGlobalSearchIfNeeded(in app: XCUIApplication) {
        let field = app.textFields["global-search-field"].firstMatch
        guard field.exists, field.frame.width >= 40 else { return }
        let toggle = app.descendants(matching: .any)["global-search-toggle"].firstMatch
        guard toggle.exists else { return }
        tapVisibleCenter(of: toggle, in: app)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    }

    private func saveEditor(
        identifier: String,
        title: String? = nil,
        fieldIdentifier: String? = nil,
        in app: XCUIApplication
    ) {
        dismissKeyboard(in: app)
        let save = app.buttons[identifier]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Missing save button \(identifier)")
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: save
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        save.tap()

        let sentinel: XCUIElement
        if let title {
            sentinel = app.staticTexts[title]
        } else if let fieldIdentifier {
            sentinel = app.textFields[fieldIdentifier]
        } else {
            XCTFail("saveEditor requires a title or field identifier")
            return
        }
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: sentinel
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [closed], timeout: 20),
            .completed,
            "Editor did not close after saving with \(identifier)"
        )
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(app.alerts["Error"].exists)
        XCTAssertFalse(app.alerts["Unable to Save"].exists)
    }

    private func enter(
        _ text: String,
        into field: XCUIElement,
        in app: XCUIApplication,
        dismissKeyboard shouldDismiss: Bool = true
    ) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Missing input field")
        tapVisibleCenter(of: field, in: app)
        field.typeText(text)
        if shouldDismiss { dismissKeyboard(in: app) }
    }

    private func replaceText(
        in field: XCUIElement,
        with text: String,
        app: XCUIApplication,
        dismissKeyboard shouldDismiss: Bool = true
    ) {
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        // Put the insertion point at the end before sending backspaces. A
        // centre tap can leave a suffix behind in long search strings.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
        // Long press and Command-A are both unreliable for text fields
        // embedded in the glass/scroll containers on iOS 26. Delete exactly
        // the current value after focusing the field, then type the new one.
        let currentLength = (field.value as? String)?.count ?? 200
        field.typeText(
            String(
                repeating: XCUIKeyboardKey.delete.rawValue,
                count: max(currentLength, 1)
            )
        )
        field.typeText(text)
        if shouldDismiss { dismissKeyboard(in: app) }
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let returnKey = app.keyboards.buttons["Return"]
        if returnKey.exists {
            returnKey.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.30)).tap()
        }
    }

    private func waitForDatabasePreparation(in app: XCUIApplication) {
        let preparing = app.staticTexts["Preparing database…"]
        guard preparing.waitForExistence(timeout: 3) else { return }
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: preparing
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 90), .completed)
    }

    /// Daily logs debounce for 1.5 seconds and then write through EventKit.
    /// Waiting only for the debounce boundary makes an immediate process
    /// termination race the asynchronous calendar save on a busy full-suite
    /// run. This interval verifies completed persistence, not just UI state.
    private func waitForDailyAutosave() {
        RunLoop.current.run(until: Date().addingTimeInterval(5))
    }

    private func dismissWellnessCheckInIfNeeded(in app: XCUIApplication) {
        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 1) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.56)).tap()
        }
    }

    private func scrollToElement(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int
    ) {
        var swipes = 0
        while (!element.exists || element.frame.isEmpty
               || element.frame.minY > app.frame.maxY - 170
               || element.frame.maxY < app.frame.minY + 145),
              swipes < maximumSwipes {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(element.exists, "Element did not become visible: \(element)")
    }

    private func revealTrailingActions(for element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        // Ask XCTest to swipe the resolved row element itself. A screen-level
        // coordinate can land on the floating search/tab chrome when a tall
        // workout card is near the bottom edge, leaving its actions hidden.
        element.swipeLeft(velocity: .slow)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    }

    private func tapFloatingButton(in app: XCUIApplication) {
        for identifier in [
            "food-add-button",
            "exercise-add-button",
            "shopping-list-add-button",
            "storage-add-button",
            "node-add-button"
        ] {
            // SwiftUI may expose the icon and its ancestors with the same
            // identifier. Restrict this to the actual semantic button.
            let control = app.buttons[identifier].firstMatch
            if control.waitForExistence(timeout: 1) {
                tapVisibleCenter(of: control, in: app)
                return
            }
        }
        for identifier in [
            "widget.large.badge.plus",
            "document.badge.plus",
            "sparkles"
        ] {
            let image = app.images[identifier]
            if image.exists && image.isHittable {
                image.tap()
                return
            }
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.815, dy: 0.84)).tap()
    }

    private func tapVisibleCenter(of element: XCUIElement, in app: XCUIApplication) {
        XCTAssertFalse(element.frame.isEmpty, "Element has no visible frame: \(element)")
        app.coordinate(
            withNormalizedOffset: CGVector(
                dx: element.frame.midX / app.frame.width,
                dy: element.frame.midY / app.frame.height
            )
        ).tap()
    }

    private func uniqueName(_ prefix: String) -> String {
        "UI CRUD \(prefix) \(UUID().uuidString.prefix(8))"
    }
}
