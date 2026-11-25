import Foundation

enum NapSettings {
    static let minimumMinutes = 1
    static let maximumMinutes = 180
    static let stepMinutes = 1
    static let defaultMinutes = 15
    static let presets = [10, 15, 20, 30, 45, 60]
    static let minutesKey = "wakito.napMinutes"
    static let soundKey = "wakito.napSound"
    static let activeAlarmKey = "wakito.napAlarmID"

    static func clamped(_ minutes: Int) -> Int {
        min(maximumMinutes, max(minimumMinutes, minutes))
    }

    static func minutes(in defaults: UserDefaults) -> Int {
        guard defaults.object(forKey: minutesKey) != nil else { return defaultMinutes }
        return clamped(defaults.integer(forKey: minutesKey))
    }

    static func setMinutes(_ minutes: Int, in defaults: UserDefaults) {
        defaults.set(clamped(minutes), forKey: minutesKey)
    }

    static func soundID(in defaults: UserDefaults) -> String {
        let stored = defaults.string(forKey: soundKey) ?? ""
        return stored.isEmpty ? SoundCatalog.defaultID : stored
    }

    static func setSoundID(_ id: String, in defaults: UserDefaults) {
        defaults.set(id, forKey: soundKey)
    }

    static func activeAlarmID(in defaults: UserDefaults) -> UUID? {
        guard let text = defaults.string(forKey: activeAlarmKey) else { return nil }
        return UUID(uuidString: text)
    }

    static func setActiveAlarmID(_ id: UUID?, in defaults: UserDefaults) {
        if let id {
            defaults.set(id.uuidString, forKey: activeAlarmKey)
        } else {
            defaults.removeObject(forKey: activeAlarmKey)
        }
    }
}

enum DefaultSnooze {
    static let minimumMinutes = 1
    static let maximumMinutes = 30
    static let fallback = 9
    static let key = "wakito.defaultSnoozeMinutes"

    static func clamped(_ minutes: Int) -> Int {
        min(maximumMinutes, max(minimumMinutes, minutes))
    }

    static func minutes(in defaults: UserDefaults) -> Int {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return clamped(defaults.integer(forKey: key))
    }

    static func setMinutes(_ minutes: Int, in defaults: UserDefaults) {
        defaults.set(clamped(minutes), forKey: key)
    }
}

enum NapCountdown {
    static func remaining(until fire: Date, now: Date) -> TimeInterval {
        max(0, fire.timeIntervalSince(now))
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds).rounded(.down))
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }
}

enum NapFailure {
    /// A missing permission or a failed AlarmKit schedule must be shown. Silence looks like a broken button.
    static func message(authorization: AlarmAccessState, scheduleFailure: String?) -> String? {
        if let scheduleFailure, !scheduleFailure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return scheduleFailure
        }
        if authorization != .authorized {
            return String(localized: "nap.needsPermission")
        }
        return nil
    }
}

enum NapAlarm {
    static func make(minutes: Int, soundID: String = SoundCatalog.defaultID, now: Date, id: UUID = UUID()) -> Alarm {
        let length = NapSettings.clamped(minutes)
        let lead = TimeInterval(length * 60)
        return Alarm(
            id: id,
            schedule: .oneShot(fireAt: now.addingTimeInterval(lead)),
            label: String(localized: "nap.alarmLabel"),
            soundID: soundID,
            snoozeEnabled: false,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            note: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
    }
}
