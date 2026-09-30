import XCTest

/// Drives the real app with synthesized touches and reads back what happened
/// from the canvas's accessibility value ("zoom=1.000;cx=0.0;...").
final class GestureUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Launches straight into a hexagon puzzle with `tiles` extra tiles.
    private func launch(tiles: Int? = nil, shape: String = "hexagon") {
        app.launchEnvironment["SEED_SHAPE"] = shape
        if let tiles { app.launchEnvironment["SEED_TILES"] = String(tiles) }
        app.launch()
        XCTAssertTrue(board.waitForExistence(timeout: 10))
    }

    private var board: XCUIElement { app.descendants(matching: .any)["board"] }

    private func value(_ key: String) -> Double {
        let text = (board.value as? String) ?? ""
        for part in text.split(separator: ";") {
            let kv = part.split(separator: "=")
            if kv.count == 2, kv[0] == key, let v = Double(kv[1]) { return v }
        }
        XCTFail("no \(key) in '\(text)'")
        return .nan
    }

    private func settle() { Thread.sleep(forTimeInterval: 0.6) }

    func testPinchOutZoomsIn() {
        launch(tiles: 60)
        settle()
        let start = value("zoom")
        app.descendants(matching: .any)["pinchpad"].pinch(withScale: 2.0, velocity: 2.0)
        settle()
        XCTAssertGreaterThan(value("zoom"), start * 1.3, "pinching outward should zoom in")
    }

    func testPinchInZoomsOut() {
        launch(tiles: 60)
        settle()
        let start = value("zoom")
        app.descendants(matching: .any)["pinchpad"].pinch(withScale: 0.5, velocity: -1.0)
        settle()
        XCTAssertLessThan(value("zoom"), start * 0.9, "pinching inward should zoom out")
    }

    func testOneFingerDragOnEmptyCanvasPansInGrabMode() {
        launch(tiles: 30)
        settle()
        let cx = value("cx")
        let from = board.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.25))
        let to = board.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.25))
        from.press(forDuration: 0.1, thenDragTo: to)
        settle()
        XCTAssertLessThan(value("cx"), cx - 50, "dragging right should move the view left")
    }

    func testMarqueeInSelectModeSelectsTheShapesItTouches() {
        launch(tiles: 60)
        app.buttons["Select"].tap()
        settle()
        XCTAssertEqual(value("selected"), 0)
        let from = board.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35))
        let to = board.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.65))
        from.press(forDuration: 0.1, thenDragTo: to)
        settle()
        XCTAssertGreaterThan(value("selected"), 5)
        // a second marquee over the same area toggles them back off
        from.press(forDuration: 0.1, thenDragTo: to)
        settle()
        XCTAssertEqual(value("selected"), 0)
    }

    func testTappingAShapeInSelectModeSelectsIt() {
        launch()  // just the seed tile, at the middle of the screen
        app.buttons["Select"].tap()
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        settle()
        XCTAssertEqual(value("selected"), 1)
    }

    func testHoldingPlusKeepsAddingTiles() {
        launch()
        settle()
        XCTAssertEqual(value("tiles"), 1)
        app.descendants(matching: .any)["Add tile"].firstMatch.press(forDuration: 0.3)
        settle()
        XCTAssertEqual(value("tiles"), 2, "a short tap adds exactly one")
        app.descendants(matching: .any)["Add tile"].firstMatch.press(forDuration: 2.5)
        settle()
        XCTAssertGreaterThan(value("tiles"), 12, "holding past the delay repeats quickly")
    }

    func testSwitchingShapeAsksFirstAndCancelKeepsTheBoard() {
        launch(tiles: 20)
        settle()
        app.buttons["Shape"].tap()
        app.buttons["Triangle"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["A puzzle can only use one shape — switching clears the current board. Continue?"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        settle()
        XCTAssertEqual(value("tiles"), 21)

        app.buttons["Shape"].tap()
        app.buttons["Triangle"].firstMatch.tap()
        app.buttons["Switch to Triangle"].tap()
        settle()
        XCTAssertEqual(value("tiles"), 1, "a new puzzle with one seed tile")
    }
}
