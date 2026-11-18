import Foundation

struct BundledSound: Identifiable, Equatable {
    var id: String
    var localizationKey: String
}

enum SoundCatalog {
    static let defaultID = "classic"
    static let bundled: [BundledSound] = [
        BundledSound(id: "classic", localizationKey: "sound.classic"),
        BundledSound(id: "chime", localizationKey: "sound.chime"),
        BundledSound(id: "rise", localizationKey: "sound.rise"),
        BundledSound(id: "pulse", localizationKey: "sound.pulse"),
        BundledSound(id: "bell", localizationKey: "sound.bell"),
    ]

    static func isBundled(_ id: String) -> Bool {
        bundled.contains { $0.id == id }
    }
}

struct CustomSound: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var displayName: String
    /// File name inside `Library/Sounds`, including the extension.
    var filename: String
}

struct LibrarySnapshot: Codable, Equatable {
    var library: AlarmLibrary
    var permissions: PermissionCenter
    var customSounds: [CustomSound]
    var profile: Participant
    var simulatedFriend: Participant?
    var appliedCommandIDs: [UUID]
    var pendingOutbox: [RemoteAlarmCommand]

    static func empty(profile: Participant) -> LibrarySnapshot {
        LibrarySnapshot(
            library: AlarmLibrary(),
            permissions: PermissionCenter(),
            customSounds: [],
            profile: profile,
            simulatedFriend: nil,
            appliedCommandIDs: [],
            pendingOutbox: []
        )
    }
}
