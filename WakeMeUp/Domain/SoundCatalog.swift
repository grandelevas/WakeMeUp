import Foundation

struct BundledSound: Identifiable, Equatable {
    var id: String
    var localizationKey: String
    /// AlarmKit and notification sounds need this extension in the file name.
    var fileExtension: String = "wav"
}

enum SoundCatalog {
    static let defaultID = "classic"
    static let bundled: [BundledSound] = [
        BundledSound(id: "classic", localizationKey: "sound.classic"),
        BundledSound(id: "chime", localizationKey: "sound.chime"),
        BundledSound(id: "rise", localizationKey: "sound.rise"),
        BundledSound(id: "pulse", localizationKey: "sound.pulse"),
        BundledSound(id: "bell", localizationKey: "sound.bell"),
        BundledSound(id: "dawn", localizationKey: "sound.dawn", fileExtension: "caf"),
        BundledSound(id: "beep", localizationKey: "sound.beep", fileExtension: "caf"),
        BundledSound(id: "bells", localizationKey: "sound.bells", fileExtension: "caf"),
        BundledSound(id: "digital", localizationKey: "sound.digital", fileExtension: "caf"),
        BundledSound(id: "morning", localizationKey: "sound.morning", fileExtension: "caf"),
        BundledSound(id: "birds", localizationKey: "sound.birds", fileExtension: "caf"),
        BundledSound(id: "marimba", localizationKey: "sound.marimba", fileExtension: "caf"),
        BundledSound(id: "sleepy", localizationKey: "sound.sleepy", fileExtension: "caf"),
    ]

    static func fileExtension(for id: String) -> String {
        bundled.first { $0.id == id }?.fileExtension ?? "wav"
    }

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
