import Foundation

final class LibraryStore {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    static func applicationSupportURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("WakeMeUp", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("library.json")
    }

    func load() -> LibrarySnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LibrarySnapshot.self, from: data)
    }

    func save(_ snapshot: LibrarySnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}

enum AppConfig {
    static var communityCountURL: String {
        guard let url = Bundle.main.url(forResource: "WakeMeUpConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let address = plist["CommunityCountURL"] as? String else {
            return ""
        }
        return address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var achievementsContentURL: String {
        guard let url = Bundle.main.url(forResource: "WakeMeUpConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let address = plist["AchievementsContentURL"] as? String else {
            return ""
        }
        return address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var cloudKitContainerID: String {
        guard let url = Bundle.main.url(forResource: "WakeMeUpConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let identifier = plist["CloudKitContainerID"] as? String else {
            return ""
        }
        return identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var usesCloudKit: Bool {
        let identifier = cloudKitContainerID
        return !identifier.isEmpty && !identifier.hasPrefix("REPLACE")
    }

    /// Debug CI has no iCloud entitlement. Creating CKContainer there traps the test host.
    /// Release and TestFlight use the real container.
    static var activatesCloudKit: Bool {
        #if DEBUG
        false
        #else
        usesCloudKit
        #endif
    }

    static var appGroupID: String {
        "group.\(Bundle.main.bundleIdentifier ?? "com.grandelevas.wakemeup")"
    }
}

enum LaunchConfiguration {
    enum Screen: String {
        case alarms
        case editor
        case groups
        case sharing
        case ringing
    }

    static var screen: Screen {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-WakeMeUpScreen"),
              index + 1 < arguments.count else {
            return .alarms
        }
        return Screen(rawValue: arguments[index + 1]) ?? .alarms
    }

    static var seedDemo: Bool {
        ProcessInfo.processInfo.arguments.contains("-WakeMeUpDemo")
    }
}

enum SoundFiles {
    static func previewURL(for soundID: String, customSounds: [CustomSound]) -> URL? {
        if let custom = customSounds.first(where: { $0.id == soundID }) {
            guard let directory = try? librarySoundsDirectory() else { return nil }
            let url = directory.appendingPathComponent(custom.filename)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return bundledURL(id: soundID)
    }

    static func bundledURL(id: String) -> URL? {
        if let url = Bundle.main.url(forResource: id, withExtension: "wav") {
            return url
        }
        return Bundle.main.url(forResource: id, withExtension: "wav", subdirectory: "Sounds")
    }

    static func librarySoundsDirectory() throws -> URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = library.appendingPathComponent("Sounds", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// AlarmKit `.named` and `UNNotificationSound` both need the filename,
    /// including its extension, in the app bundle root or in Library/Sounds.
    static func soundFilename(for soundID: String, customSounds: [CustomSound]) -> String {
        if let custom = customSounds.first(where: { $0.id == soundID }) {
            return custom.filename
        }
        return "\(soundID).wav"
    }

    static func alarmKitName(for soundID: String, customSounds: [CustomSound]) -> String {
        soundFilename(for: soundID, customSounds: customSounds)
    }

    static func notificationName(for soundID: String, customSounds: [CustomSound]) -> String {
        soundFilename(for: soundID, customSounds: customSounds)
    }
}
