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

        let handle = weekend.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
        let destination = weekdays.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        handle.press(forDuration: 0.8, thenDragTo: destination)

        let ordered = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'group-row-'"))
            .allElementsBoundByIndex
            .map(\.identifier)
        XCTAssertEqual(ordered.first, "group-row-BBBBBBBB-0000-0000-0000-000000000002")
    }
}
