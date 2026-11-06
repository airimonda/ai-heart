import XCTest

/// Drives a slow tour of the app on sample data so `scripts/record-demo.sh` can record it.
/// Not a correctness test: it only waits and taps, and passes as long as the screens open.
/// Skips screens that load the language model (too slow on the simulator); Talk it through runs scripted.
final class DemoTourUITests: XCTestCase {
    private var app: XCUIApplication!

    private func pause(_ seconds: Double = 2.0) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func tap(_ element: XCUIElement, timeout: TimeInterval = 8) {
        guard element.waitForExistence(timeout: timeout) else { return }
        element.tap()
        pause()
    }

    private func scroll(up times: Int) {
        for _ in 0..<times { app.swipeUp(velocity: .slow); pause(1.4) }
    }

    private func scroll(down times: Int) {
        for _ in 0..<times { app.swipeDown(velocity: .slow); pause(0.8) }
    }

    /// Edge swipe back, which works for custom back buttons too.
    private func back() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        pause()
    }

    private func button(startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    func testDemoTour() throws {
        app = XCUIApplication()
        app.launchArguments = ["-seedSamples", "-skipFirstRun", "-openJournal"]
        app.launch()
        pause(4)

        // Journal: entries colored by mood, and a resting entry with only its kept lines.
        scroll(up: 2)
        scroll(down: 3)
        pause(1)

        // The month calendar that colors itself.
        tap(app.buttons["Month"])
        tap(app.buttons["Previous month"], timeout: 3)
        pause(3)

        // Insights: body against my own baseline.
        tap(app.tabBars.buttons["Insights"])
        pause(3)

        // Mood outlook: a lean with an uncertainty band.
        tap(button(startingWith: "Mood outlook"))
        pause(3)
        scroll(up: 2)
        back()
        scroll(down: 3)

        // Patterns: where mood has been.
        tap(app.buttons["Patterns"])
        pause(2.5)
        tap(app.buttons["90 days"], timeout: 3)
        pause(2)
        scroll(up: 3)
        pause(1.5)

        // Talk it through: a scripted conversation (-talkDemo), labeled on screen, no model loaded.
        app.terminate()
        app.launchArguments = ["-seedSamples", "-skipFirstRun", "-openTalk", "-talkDemo"]
        app.launch()
        _ = app.navigationBars["Talk it through"].waitForExistence(timeout: 15)
        pause(27)
    }
}
