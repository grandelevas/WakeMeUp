import Foundation

enum SpokenAlarm {
    static func hourAndMinute(from date: Date, calendar: Calendar = .current) -> (hour: Int, minute: Int) {
        (calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }

    /// A spoken time is the next one-time alarm at that clock time.
    static func make(at date: Date, now: Date = .now, calendar: Calendar = .current, snoozeMinutes: Int = 9, id: UUID = UUID()) -> Alarm {
        let parts = hourAndMinute(from: date, calendar: calendar)
        let schedule = AlarmSchedule.wallClock(hour: parts.hour, minute: parts.minute, repeatDays: [])
        return Alarm(
            id: id,
            schedule: schedule,
            label: "",
            soundID: SoundCatalog.defaultID,
            snoozeEnabled: true,
            snoozeMinutes: snoozeMinutes,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            note: nil,
            firesOnceAt: schedule.nextFireDate(from: now, calendar: calendar),
            origin: .local,
            resumeWhenGroupEnables: nil
        )
    }
}

enum SpokenContactMatch {
    /// Picks the contact whose name matches the spoken name. A person who can be woken wins.
    static func match(name: String, contacts: [SharingContact]) -> SharingContact? {
        let needle = folded(name)
        guard !needle.isEmpty else { return nil }
        let hits = contacts.filter { contact in
            let hay = folded(contact.name)
            return hay == needle || hay.hasPrefix(needle) || needle.hasPrefix(hay)
        }
        return hits.first { $0.wakeGrantID != nil } ?? hits.first
    }

    private static func folded(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
