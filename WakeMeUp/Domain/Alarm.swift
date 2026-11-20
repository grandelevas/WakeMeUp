import Foundation

enum AlarmSchedule: Codable, Equatable, Hashable {
    case wallClock(hour: Int, minute: Int, repeatDays: [Weekday])
    case oneShot(fireAt: Date)

    var hour: Int {
        switch self {
        case let .wallClock(hour, _, _): hour
        case let .oneShot(fireAt): Calendar.current.component(.hour, from: fireAt)
        }
    }

    var minute: Int {
        switch self {
        case let .wallClock(_, minute, _): minute
        case let .oneShot(fireAt): Calendar.current.component(.minute, from: fireAt)
        }
    }

    var repeatDays: [Weekday] {
        switch self {
        case let .wallClock(_, _, days): days
        case .oneShot: []
        }
    }

    func nextFireDate(from now: Date, calendar: Calendar) -> Date? {
        switch self {
        case let .oneShot(fireAt):
            return fireAt > now ? fireAt : nil
        case let .wallClock(hour, minute, repeatDays):
            return NextFireDate.wallClock(
                hour: hour,
                minute: minute,
                repeatDays: Set(repeatDays),
                from: now,
                calendar: calendar
            )
        }
    }
}

enum AlarmOrigin: Codable, Equatable, Hashable {
    case local
    case remote(senderID: UUID, senderName: String, commandID: UUID)

    var senderName: String? {
        if case let .remote(_, name, _) = self { return name }
        return nil
    }

    func isOwned(by senderID: UUID) -> Bool {
        if case let .remote(id, _, _) = self { return id == senderID }
        return false
    }
}

struct Alarm: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var schedule: AlarmSchedule
    var label: String
    var soundID: String
    var snoozeEnabled: Bool
    var snoozeMinutes: Int
    var isEnabled: Bool
    var groupID: UUID?
    var songLink: SongLink?
    var origin: AlarmOrigin
    /// Enabled state to restore when a disabled group is turned back on.
    var resumeWhenGroupEnables: Bool?

    var sortMinute: Int {
        switch schedule {
        case let .wallClock(hour, minute, _):
            return hour * 60 + minute
        case let .oneShot(fireAt):
            let calendar = Calendar.current
            return calendar.component(.hour, from: fireAt) * 60 + calendar.component(.minute, from: fireAt)
        }
    }
}

struct AlarmGroup: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var symbol: String
}

struct AlarmLibrary: Codable, Equatable {
    var alarms: [Alarm] = []
    var groups: [AlarmGroup] = []

    func alarm(_ id: UUID) -> Alarm? {
        alarms.first { $0.id == id }
    }

    func group(_ id: UUID) -> AlarmGroup? {
        groups.first { $0.id == id }
    }

    mutating func upsert(_ alarm: Alarm) {
        var alarm = alarm
        if let groupID = alarm.groupID, group(groupID)?.isEnabled == false {
            let wantsOn = alarm.resumeWhenGroupEnables ?? alarm.isEnabled
            alarm.resumeWhenGroupEnables = wantsOn
            alarm.isEnabled = false
        } else {
            alarm.resumeWhenGroupEnables = nil
        }
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
        } else {
            alarms.append(alarm)
        }
    }

    mutating func delete(id: UUID) {
        alarms.removeAll { $0.id == id }
    }

    mutating func setEnabled(_ enabled: Bool, alarmID: UUID) {
        guard let index = alarms.firstIndex(where: { $0.id == alarmID }) else { return }
        if let groupID = alarms[index].groupID, group(groupID)?.isEnabled == false {
            alarms[index].resumeWhenGroupEnables = enabled
            alarms[index].isEnabled = false
            return
        }
        alarms[index].isEnabled = enabled
        alarms[index].resumeWhenGroupEnables = nil
    }

    mutating func setGroupEnabled(_ enabled: Bool, groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        if groups[index].isEnabled == enabled { return }
        groups[index].isEnabled = enabled
        for alarmIndex in alarms.indices where alarms[alarmIndex].groupID == groupID {
            if enabled {
                alarms[alarmIndex].isEnabled = alarms[alarmIndex].resumeWhenGroupEnables ?? false
                alarms[alarmIndex].resumeWhenGroupEnables = nil
            } else {
                if alarms[alarmIndex].resumeWhenGroupEnables == nil {
                    alarms[alarmIndex].resumeWhenGroupEnables = alarms[alarmIndex].isEnabled
                }
                alarms[alarmIndex].isEnabled = false
            }
        }
    }

    mutating func updateGroup(id: UUID, name: String, symbol: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            groups[index].name = trimmed
        }
        groups[index].symbol = symbol
    }

    /// Moves an alarm into a group, or out of every group when `groupID` is nil.
    /// A disabled group keeps the alarm off and remembers whether it should return.
    mutating func moveAlarm(_ alarmID: UUID, to groupID: UUID?) {
        guard let index = alarms.firstIndex(where: { $0.id == alarmID }) else { return }
        if alarms[index].groupID == groupID { return }
        if let current = alarms[index].groupID, group(current)?.isEnabled == false {
            alarms[index].isEnabled = alarms[index].resumeWhenGroupEnables ?? false
            alarms[index].resumeWhenGroupEnables = nil
        }
        alarms[index].groupID = groupID
        if let groupID, group(groupID)?.isEnabled == false {
            alarms[index].resumeWhenGroupEnables = alarms[index].isEnabled
            alarms[index].isEnabled = false
        }
    }

    @discardableResult
    mutating func addGroup(name: String, symbol: String = "folder") -> AlarmGroup {
        let group = AlarmGroup(id: UUID(), name: name, isEnabled: true, symbol: symbol)
        groups.append(group)
        return group
    }

    /// Removes the group. Alarms remain, and a disabled group's remembered state is restored.
    mutating func deleteGroup(id: UUID) {
        let wasDisabled = group(id)?.isEnabled == false
        groups.removeAll { $0.id == id }
        for index in alarms.indices where alarms[index].groupID == id {
            alarms[index].groupID = nil
            if wasDisabled {
                alarms[index].isEnabled = alarms[index].resumeWhenGroupEnables ?? false
                alarms[index].resumeWhenGroupEnables = nil
            }
        }
    }

    func alarms(in groupID: UUID?) -> [Alarm] {
        alarms
            .filter { $0.groupID == groupID }
            .sorted {
                if $0.sortMinute != $1.sortMinute { return $0.sortMinute < $1.sortMinute }
                return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }
    }
}

struct AlarmDraft: Equatable, Identifiable {
    var id: UUID
    var hour: Int
    var minute: Int
    var label: String
    var repeatDays: Set<Weekday>
    var soundID: String
    var snoozeEnabled: Bool
    var snoozeMinutes: Int
    var isEnabled: Bool
    var groupID: UUID?
    var songText: String
    var origin: AlarmOrigin
    var isNew: Bool

    static func makeNew(now: Date = .now, calendar: Calendar = .current) -> AlarmDraft {
        let hour = (calendar.component(.hour, from: now) + 1) % 24
        return AlarmDraft(
            id: UUID(),
            hour: hour,
            minute: 0,
            label: "",
            repeatDays: [],
            soundID: SoundCatalog.defaultID,
            snoozeEnabled: true,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: nil,
            songText: "",
            origin: .local,
            isNew: true
        )
    }

    init(alarm: Alarm, calendar: Calendar = .current) {
        id = alarm.id
        switch alarm.schedule {
        case let .wallClock(hour, minute, days):
            self.hour = hour
            self.minute = minute
            repeatDays = Set(days)
        case let .oneShot(fireAt):
            hour = calendar.component(.hour, from: fireAt)
            minute = calendar.component(.minute, from: fireAt)
            repeatDays = []
        }
        label = alarm.label
        soundID = alarm.soundID
        snoozeEnabled = alarm.snoozeEnabled
        snoozeMinutes = alarm.snoozeMinutes
        isEnabled = alarm.isEnabled || (alarm.resumeWhenGroupEnables ?? false)
        groupID = alarm.groupID
        songText = alarm.songLink?.url.absoluteString ?? ""
        origin = alarm.origin
        isNew = false
    }

    init(
        id: UUID,
        hour: Int,
        minute: Int,
        label: String,
        repeatDays: Set<Weekday>,
        soundID: String,
        snoozeEnabled: Bool,
        snoozeMinutes: Int,
        isEnabled: Bool,
        groupID: UUID?,
        songText: String,
        origin: AlarmOrigin,
        isNew: Bool
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.label = label
        self.repeatDays = repeatDays
        self.soundID = soundID
        self.snoozeEnabled = snoozeEnabled
        self.snoozeMinutes = snoozeMinutes
        self.isEnabled = isEnabled
        self.groupID = groupID
        self.songText = songText
        self.origin = origin
        self.isNew = isNew
    }

    var parsedSong: SongLink? {
        let trimmed = songText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return SongLink.parse(trimmed)
    }

    var songIsValid: Bool {
        songText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedSong != nil
    }

    func makeAlarm() -> Alarm? {
        guard songIsValid else { return nil }
        let schedule = AlarmSchedule.wallClock(
            hour: hour,
            minute: minute,
            repeatDays: Array(repeatDays).normalized()
        )
        return Alarm(
            id: id,
            schedule: schedule,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            soundID: soundID,
            snoozeEnabled: snoozeEnabled,
            snoozeMinutes: min(30, max(1, snoozeMinutes)),
            isEnabled: isEnabled,
            groupID: groupID,
            songLink: parsedSong,
            origin: origin,
            resumeWhenGroupEnables: nil
        )
    }
}
