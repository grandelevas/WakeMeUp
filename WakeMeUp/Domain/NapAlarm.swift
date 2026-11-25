import Foundation

enum NapSettings {
    static let minimumMinutes = 5
    static let maximumMinutes = 120
    static let stepMinutes = 5
    static let defaultMinutes = 15
    static let minutesKey = "wakito.napMinutes"
    static let soundKey = "wakito.napSound"
    static let activeAlarmKey = "wakito.napAlarmID"

    static func clamped(_ minutes: Int) -> Int {
        let bounded = min(maximumMinutes, max(minimumMinutes, minutes))
        let steps = bounded / stepMinutes
        let snapped = steps * stepMinutes
        return min(maximumMinutes, max(minimumMinutes, snapped == 0 ? minimumMinutes : snapped))
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

enum NapCountdown {
    static func remaining(until fire: Date, now: Date) -> TimeInterval {
        max(0, fire.timeIntervalSince(now))
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds).rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
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
            countdownLead: lead,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
    }
}
