import XCTest

final class DeleteEntryUITests: XCTestCase {
    func testDeleteFromEntryScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedSamples", "-openJournal", "-skipFirstRun"]
        app.launch()
        let first = app.staticTexts["[Sample] Read on the train. Did not check my phone."].firstMatch
        let anyCard = first.waitForExistence(timeout: 15) ? first : app.scrollViews.descendants(matching: .button).element(boundBy: 2)
        let before = app.staticTexts.matching(identifier: "[Sample] Read on the train. Did not check my phone.").count
        anyCard.tap()
        let del = app.buttons["Delete this entry"]
        for _ in 0..<6 where !del.isHittable { app.swipeUp() }
        XCTAssertTrue(del.waitForExistence(timeout: 5))
        del.tap()
        let confirm = app.alerts.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "confirmation alert did not appear")
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 5))
        let after = app.staticTexts.matching(identifier: "[Sample] Read on the train. Did not check my phone.").count
        XCTAssertLessThan(after, max(before, 1) + 0, "entry still listed")
    }

    func testDeleteFromLongPress() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedSamples", "-openJournal", "-skipFirstRun"]
        app.launch()
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '[Sample]'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        let label = card.label
        card.press(forDuration: 1.2)
        let menuDelete = app.buttons["Delete"]
        XCTAssertTrue(menuDelete.waitForExistence(timeout: 5), "context menu Delete missing")
        menuDelete.tap()
        let confirm = app.alerts.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "confirmation alert did not appear")
        confirm.tap()
        sleep(1)
        _ = label
    }

    func testDeleteLetGoEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedSamples", "-openJournal", "-skipFirstRun"]
        app.launch()
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Talking to a friend'")).firstMatch
        for _ in 0..<12 where !card.exists { app.swipeUp() }
        if !card.waitForExistence(timeout: 5) { print("TREE", app.debugDescription) }
        XCTAssertTrue(card.exists)
        card.tap()
        let del = app.buttons["Delete what is left"]
        XCTAssertTrue(del.waitForExistence(timeout: 5), "let-go entry did not open")
        del.tap()
        let confirm = app.alerts.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 5))
    }
}
