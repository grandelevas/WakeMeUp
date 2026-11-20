import Foundation

enum GroupExpansionStore {
    static let key = "wakito.collapsedGroups"

    static func isExpanded(_ id: UUID, defaults: UserDefaults = .standard) -> Bool {
        !collapsedIDs(defaults: defaults).contains(id)
    }

    static func setExpanded(_ expanded: Bool, id: UUID, defaults: UserDefaults = .standard) {
        var collapsed = collapsedIDs(defaults: defaults)
        if expanded {
            collapsed.remove(id)
        } else {
            collapsed.insert(id)
        }
        defaults.set(collapsed.map(\.uuidString), forKey: key)
    }

    static func collapsedIDs(defaults: UserDefaults = .standard) -> Set<UUID> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)))
    }
}
