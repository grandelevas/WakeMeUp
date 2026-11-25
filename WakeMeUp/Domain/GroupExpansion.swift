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

enum SectionExpansionStore {
    static let key = "wakito.collapsedSections"
    static let fromOthers = "fromOthers"
    static let toOthers = "toOthers"

    static func isExpanded(_ id: String, defaults: UserDefaults = .standard) -> Bool {
        !collapsedIDs(defaults: defaults).contains(id)
    }

    static func setExpanded(_ expanded: Bool, id: String, defaults: UserDefaults = .standard) {
        var collapsed = collapsedIDs(defaults: defaults)
        if expanded {
            collapsed.remove(id)
        } else {
            collapsed.insert(id)
        }
        defaults.set(Array(collapsed), forKey: key)
    }

    static func collapsedIDs(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }
}
