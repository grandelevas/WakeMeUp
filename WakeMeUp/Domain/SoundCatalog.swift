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
    /// Alarms this phone sent to someone else. They are not scheduled here.
    var sentAlarms: [SentAlarm] = []

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

extension LibrarySnapshot {
    private enum CodingKeys: String, CodingKey {
        case library, permissions, customSounds, profile, simulatedFriend
        case appliedCommandIDs, pendingOutbox, sentAlarms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        library = try container.decode(AlarmLibrary.self, forKey: .library)
        permissions = try container.decode(PermissionCenter.self, forKey: .permissions)
        customSounds = try container.decode([CustomSound].self, forKey: .customSounds)
        profile = try container.decode(Participant.self, forKey: .profile)
        simulatedFriend = try container.decodeIfPresent(Participant.self, forKey: .simulatedFriend)
        appliedCommandIDs = try container.decode([UUID].self, forKey: .appliedCommandIDs)
        pendingOutbox = try container.decode([RemoteAlarmCommand].self, forKey: .pendingOutbox)
        sentAlarms = try container.decodeIfPresent([SentAlarm].self, forKey: .sentAlarms) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(library, forKey: .library)
        try container.encode(permissions, forKey: .permissions)
        try container.encode(customSounds, forKey: .customSounds)
        try container.encode(profile, forKey: .profile)
        try container.encodeIfPresent(simulatedFriend, forKey: .simulatedFriend)
        try container.encode(appliedCommandIDs, forKey: .appliedCommandIDs)
        try container.encode(pendingOutbox, forKey: .pendingOutbox)
        try container.encode(sentAlarms, forKey: .sentAlarms)
    }
}
