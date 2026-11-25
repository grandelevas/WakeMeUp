import CoreGraphics
import Foundation

enum TabEdgeSwipe {
    /// A drag that starts farther in than this belongs to a row swipe action, not the tab pager.
    static let edgeInset: CGFloat = 24
    /// Far enough that a short row swipe does not change tabs.
    static let minimumTravel: CGFloat = 72

    enum Direction: Equatable {
        case previous
        case next
    }

    /// Horizontal swipe from the screen edge. Drags that start on a row return nil.
    static func direction(
        startX: CGFloat,
        translationX: CGFloat,
        translationY: CGFloat,
        width: CGFloat
    ) -> Direction? {
        guard width > edgeInset * 2 else { return nil }
        guard abs(translationX) >= minimumTravel else { return nil }
        guard abs(translationX) > abs(translationY) else { return nil }
        if startX <= edgeInset, translationX > 0 { return .previous }
        if startX >= width - edgeInset, translationX < 0 { return .next }
        return nil
    }
}

extension AppTab {
    static let displayOrder: [AppTab] = [.nap, .alarms, .sharing, .calendar, .achievements]

    func shifted(_ direction: TabEdgeSwipe.Direction) -> AppTab {
        let order = Self.displayOrder
        guard let index = order.firstIndex(of: self) else { return self }
        let next = direction == .next ? index + 1 : index - 1
        guard order.indices.contains(next) else { return self }
        return order[next]
    }

    var tabIndex: Int {
        Self.displayOrder.firstIndex(of: self) ?? 0
    }
}
