import Foundation

enum AlarmAccessState: Equatable {
    case unknown
    case notDetermined
    case authorized
    case denied
}

enum AlarmSoundChoice: Equatable {
    case named(String)
    case systemDefault
}

enum AlarmSoundResolver {
    /// AlarmKit `.named` only sees the app bundle root and Library/Sounds.
    /// Prefer `classic.wav`. If that file is not there, use the system alarm sound
    /// instead of a notification.
    static func choose(preferredFilename: String, present: Set<String>) -> AlarmSoundChoice {
        let base = (preferredFilename as NSString).deletingPathExtension
        let ext = (preferredFilename as NSString).pathExtension
        var candidates = [preferredFilename]
        if ext.isEmpty {
            candidates.append("\(base).wav")
        } else {
            candidates.append(base)
        }
        if let match = candidates.first(where: { present.contains($0) }) {
            return .named(match)
        }
        return .systemDefault
    }
}

enum AlarmDelivery: Equatable {
    case alarmKit
    case alarmKitSystemSound
    case notificationFallback
    case blocked(String)
}

enum AlarmDeliveryPolicy {
    /// A granted AlarmKit permission never becomes a notification.
    /// Notifications are only for a denied or unavailable AlarmKit.
    static func decide(
        permission: AlarmAccessState,
        alarmKitAvailable: Bool,
        namedSoundError: String?,
        defaultSoundError: String?
    ) -> AlarmDelivery {
        if !alarmKitAvailable || permission == .denied {
            return .notificationFallback
        }
        guard permission == .authorized else {
            return .blocked("Alarm permission has not been granted.")
        }
        if namedSoundError == nil {
            return .alarmKit
        }
        if defaultSoundError == nil {
            return .alarmKitSystemSound
        }
        return .blocked(defaultSoundError ?? namedSoundError ?? "Could not schedule the system alarm.")
    }
}
