import XCTest

final class GroupReorderUITests: XCTestCase {
    func testEditModeDragMovesTheSecondGroupAboveTheFirst() {
        let app = XCUIApplication()
        app.launchArguments = ["-WakeMeUpDemo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let weekdaysID = "group-row-BBBBBBBB-0000-0000-0000-000000000001"
        let weekendID = "group-row-BBBBBBBB-0000-0000-0000-000000000002"
        let weekdaysBefore = row(weekdaysID, in: app)
        XCTAssertTrue(weekdaysBefore.waitForExistence(timeout: 15))
        XCTAssertFalse(
            reorderHandle(near: weekdaysBefore, in: app).waitForExistence(timeout: 1),
            "Reorder handles should stay hidden until Edit"
        )

        let edit = app.buttons["alarms.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        let weekdays = row(weekdaysID, in: app)
        let weekend = row(weekendID, in: app)
        XCTAssertTrue(weekdays.waitForExistence(timeout: 5))
        XCTAssertTrue(weekend.waitForExistence(timeout: 5))

        let handle = reorderHandle(near: weekend, in: app)
        if handle.waitForExistence(timeout: 3) {
            drag(handle, to: weekdays.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.15)))
        }
        let starts: [CGFloat] = [0.92, 1.08, 0.98]
        let ends: [CGFloat] = [0.2, -0.25, 0.0]
        for (startX, endY) in zip(starts, ends) where !weekendIsAbove(weekendID, weekdaysID, in: app) {
            let weekendRow = row(weekendID, in: app)
            let weekdaysRow = row(weekdaysID, in: app)
            let start = weekendRow.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.5))
            let end = weekdaysRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
            start.press(forDuration: 0.7, thenDragTo: end)
        }

        let weekendAfter = row(weekendID, in: app)
        let weekdaysAfter = row(weekdaysID, in: app)
        XCTAssertTrue(
            weekendIsAbove(weekendID, weekdaysID, in: app),
            "Weekend \(weekendAfter.frame) should sit above weekdays \(weekdaysAfter.frame). Buttons: \(buttonLabels(in: app))"
        )
    }

    /// A drag preview can leave a second element with the same identifier. Use the topmost one.
    private func row(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        let matches = query.allElementsBoundByIndex.filter(\.exists)
        guard matches.count > 1 else { return query.firstMatch }
        return matches.min { lhs, rhs in
            if abs(lhs.frame.minY - rhs.frame.minY) > 1 { return lhs.frame.minY < rhs.frame.minY }
            return lhs.frame.height < rhs.frame.height
        } ?? query.firstMatch
    }

    private func reorderHandle(near row: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'reorder'"))
        let nearest = matches.allElementsBoundByIndex.min { lhs, rhs in
            abs(lhs.frame.midY - row.frame.midY) < abs(rhs.frame.midY - row.frame.midY)
        }
        return nearest ?? matches.firstMatch
    }

    private func drag(_ handle: XCUIElement, to destination: XCUICoordinate) {
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.6, thenDragTo: destination)
    }

    private func weekendIsAbove(_ weekendID: String, _ weekdaysID: String, in app: XCUIApplication) -> Bool {
        let weekend = row(weekendID, in: app)
        let weekdays = row(weekdaysID, in: app)
        return weekend.exists && weekdays.exists && weekend.frame.minY + 8 < weekdays.frame.minY
    }

    private func buttonLabels(in app: XCUIApplication) -> [String] {
        app.buttons.allElementsBoundByIndex.prefix(25).map(\.label)
    }
}
