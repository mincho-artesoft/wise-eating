import XCTest

final class VAL1DeviceDriverUITests: XCTestCase {
    private let wiseEatingBundleID = "WiseEating.Arte-Soft"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureWiseEatingHierarchy() throws {
        let app = XCUIApplication(bundleIdentifier: wiseEatingBundleID)
        app.launchArguments = ["-wePlannerTelemetry", "-uiTestNoAds"]
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 30),
            "Wise Eating did not reach the foreground"
        )
        sleep(15)
        print("VAL1-HIERARCHY-BEGIN")
        print(app.debugDescription)
        print("VAL1-HIERARCHY-END")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "VAL1-WiseEating-root"
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

        let app = XCUIApplication(bundleIdentifier: wiseEatingBundleID)
        app.activate()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 30),
            "Wise Eating did not reach the foreground"
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

    func testSingleColdLaunchMetric() throws {
        let app = XCUIApplication(bundleIdentifier: wiseEatingBundleID)
        app.launchArguments = [
            "-uiTestNoAds",
            "-we6LaunchProfile",
            "-wePlannerTelemetry"
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
        while (!element.exists || !element.isHittable) && swipes < maximumSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(
            element.exists && element.isHittable,
            "Element did not become hittable after \(swipes) swipe(s): \(element)"
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
}
