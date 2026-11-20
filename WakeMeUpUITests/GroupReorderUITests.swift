import XCTest

final class GroupReorderUITests: XCTestCase {
    func testEditModeDragMovesTheSecondGroupAboveTheFirst() {
        let app = XCUIApplication()
        app.launchArguments = ["-WakeMeUpDemo"]
        app.launch()

        let more = app.buttons["alarms.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()

        let reorder = app.buttons["groups.reorder"]
        if reorder.waitForExistence(timeout: 3) {
            reorder.tap()
        } else {
            app.buttons["Reorder groups"].tap()
        }

        let weekdays = app.descendants(matching: .any)["group-row-BBBBBBBB-0000-0000-0000-000000000001"]
        let weekend = app.descendants(matching: .any)["group-row-BBBBBBBB-0000-0000-0000-000000000002"]
        XCTAssertTrue(weekdays.waitForExistence(timeout: 5))
        XCTAssertTrue(weekend.waitForExistence(timeout: 5))

        let destination = weekdays.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        let systemHandle = app.buttons["Reorder Weekend"]
        if systemHandle.waitForExistence(timeout: 2) {
            systemHandle.press(forDuration: 0.6, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.5)
        } else {
            let handle = weekend.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
            handle.press(forDuration: 0.8, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.5)
        }
        if firstGroupIdentifier(in: app) != "group-row-BBBBBBBB-0000-0000-0000-000000000002" {
            let handle = weekend.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5))
            let above = weekdays.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.4))
            handle.press(forDuration: 1.0, thenDragTo: above, withVelocity: .slow, thenHoldForDuration: 0.6)
        }

        XCTAssertEqual(firstGroupIdentifier(in: app), "group-row-BBBBBBBB-0000-0000-0000-000000000002")
    }

    private func firstGroupIdentifier(in app: XCUIApplication) -> String? {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'group-row-'"))
            .allElementsBoundByIndex
            .map(\.identifier)
            .first
    }
}
