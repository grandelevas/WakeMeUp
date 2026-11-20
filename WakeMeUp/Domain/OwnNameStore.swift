import Foundation

protocol StringKeyValueStore {
    func string(forKey key: String) -> String?
    func setString(_ value: String, forKey key: String)
}

struct UserDefaultsStringStore: StringKeyValueStore {
    let defaults: UserDefaults

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func setString(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

struct UbiquitousStringStore: StringKeyValueStore {
    let store: NSUbiquitousKeyValueStore

    func string(forKey key: String) -> String? {
        store.string(forKey: key)
    }

    func setString(_ value: String, forKey key: String) {
        store.set(value, forKey: key)
        store.synchronize()
    }
}

/// The name from Twoje imię. UserDefaults is the source of truth.
/// iCloud key-value storage is a copy, and an empty value never replaces a saved name.
struct OwnNameStore {
    static let key = "wakito.ownDisplayName"

    var local: StringKeyValueStore
    var cloud: StringKeyValueStore?

    func load() -> String {
        if let localName = PersonName.nonempty(local.string(forKey: Self.key)) {
            return localName
        }
        guard let cloudName = PersonName.nonempty(cloud?.string(forKey: Self.key)) else { return "" }
        local.setString(cloudName, forKey: Self.key)
        return cloudName
    }

    /// Saves a non-empty name. Empty and whitespace-only values are ignored.
    func save(_ proposed: String) {
        guard let name = PersonName.nonempty(proposed) else { return }
        guard name != load() else { return }
        local.setString(name, forKey: Self.key)
        cloud?.setString(name, forKey: Self.key)
    }
}
