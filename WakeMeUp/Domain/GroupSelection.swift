import Foundation

enum GroupSelectionMark: Equatable {
    case none
    case partial
    case all
}

enum GroupSelection {
    static func mark(alarmIDs: [UUID], selected: Set<UUID>) -> GroupSelectionMark {
        let ids = Set(alarmIDs)
        guard !ids.isEmpty, !ids.isDisjoint(with: selected) else { return .none }
        return ids.isSubset(of: selected) ? .all : .partial
    }

    static func toggle(alarmIDs: [UUID], selected: Set<UUID>) -> Set<UUID> {
        let ids = Set(alarmIDs)
        guard !ids.isEmpty else { return selected }
        var next = selected
        if ids.isSubset(of: selected) {
            next.subtract(ids)
        } else {
            next.formUnion(ids)
        }
        return next
    }
}
