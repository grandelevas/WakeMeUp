import Foundation

enum NapSettings {
    static let minimumMinutes = 5
    static let maximumMinutes = 120
    static let stepMinutes = 5
    static let defaultMinutes = 15
    static let minutesKey = "wakito.napMinutes"
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

enum NapAlarm {
    static func make(minutes: Int, now: Date, id: UUID = UUID()) -> Alarm {
        let length = NapSettings.clamped(minutes)
        return Alarm(
            id: id,
            schedule: .oneShot(fireAt: now.addingTimeInterval(TimeInterval(length * 60))),
            label: String(localized: "nap.alarmLabel"),
            soundID: SoundCatalog.defaultID,
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
