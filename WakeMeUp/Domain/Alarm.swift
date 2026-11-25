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

    var isFromSomeoneElse: Bool {
        if case .remote = self { return true }
        return false
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
    /// Optional note, at most 1000 characters. Empty means no note.
    var note: String? = nil
    /// When a non-repeating wall-clock alarm should ring once. Not a CloudKit field.
    var firesOnceAt: Date? = nil
    /// Local file id for an attached video message. The bytes travel as a WMVoice `Video` asset.
    var videoFileID: String? = nil
    /// When set, AlarmKit shows a countdown for this many seconds and then rings. Not a CloudKit field.
    var countdownLead: TimeInterval? = nil
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
    /// Position in the alarms list. Older saved groups omit this and keep their existing order.
    var sortIndex: Int

    private enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, symbol, sortIndex
    }

    init(id: UUID, name: String, isEnabled: Bool, symbol: String, sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.symbol = symbol
        self.sortIndex = sortIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        symbol = try container.decode(String.self, forKey: .symbol)
        sortIndex = try container.decodeIfPresent(Int.self, forKey: .sortIndex) ?? -1
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(sortIndex, forKey: .sortIndex)
    }
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

    mutating func setSound(_ soundID: String, alarmIDs: some Sequence<UUID>) {
        let ids = Set(alarmIDs)
        for index in alarms.indices where ids.contains(alarms[index].id) {
            alarms[index].soundID = soundID
        }
    }

    /// Renames an alarm this phone created. A friend's alarm keeps the name they sent.
    @discardableResult
    mutating func rename(alarmID: UUID, to label: String) -> Bool {
        guard let index = alarms.firstIndex(where: { $0.id == alarmID }) else { return false }
        guard !alarms[index].origin.isFromSomeoneElse else { return false }
        alarms[index].label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return true
    }

    mutating func apply(_ patch: BulkAlarmPatch, to alarmIDs: some Sequence<UUID>, now: Date = .now, calendar: Calendar = .current) {
        let ids = Set(alarmIDs)
        for index in alarms.indices where ids.contains(alarms[index].id) {
            alarms[index] = BulkAlarmEdit.applying(patch, to: alarms[index], now: now, calendar: calendar)
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

    /// Gives groups saved before ordering a stable index, then sorts by that index.
    mutating func normalizeGroupOrder() {
        var next = (groups.map(\.sortIndex).filter { $0 >= 0 }.max() ?? -1) + 1
        for index in groups.indices where groups[index].sortIndex < 0 {
            groups[index].sortIndex = next
            next += 1
        }
        groups.sort { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Reorders groups the way `List` `.onMove` reports offsets.
    mutating func moveGroups(from source: IndexSet, to destination: Int) {
        normalizeGroupOrder()
        groups.move(fromOffsets: source, toOffset: destination)
        for index in groups.indices {
            groups[index].sortIndex = index
        }
    }

    /// Places `sourceID` where `targetID` currently sits. The target shifts down.
    mutating func moveGroup(_ sourceID: UUID, before targetID: UUID) {
        normalizeGroupOrder()
        guard sourceID != targetID,
              let from = groups.firstIndex(where: { $0.id == sourceID }),
              var to = groups.firstIndex(where: { $0.id == targetID }) else { return }
        let item = groups.remove(at: from)
        if from < to { to -= 1 }
        groups.insert(item, at: to)
        for index in groups.indices {
            groups[index].sortIndex = index
        }
    }

    @discardableResult
    mutating func addGroup(name: String, symbol: String = "folder") -> AlarmGroup {
        let next = (groups.map(\.sortIndex).filter { $0 >= 0 }.max() ?? -1) + 1
        let group = AlarmGroup(id: UUID(), name: name, isEnabled: true, symbol: symbol, sortIndex: next)
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
            .sorted(by: Self.byTime)
    }

    /// Alarms the person created. Remote alarms stay out of the group and ungrouped sections.
    func ownAlarms(in groupID: UUID?) -> [Alarm] {
        alarms(in: groupID).filter { !$0.origin.isFromSomeoneElse }
    }

    /// Alarms other people created for this phone.
    var receivedFromOthers: [Alarm] {
        alarms
            .filter { $0.origin.isFromSomeoneElse }
            .sorted(by: Self.byTime)
    }

    private static func byTime(_ lhs: Alarm, _ rhs: Alarm) -> Bool {
        if lhs.sortMinute != rhs.sortMinute { return lhs.sortMinute < rhs.sortMinute }
        return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
    }
}

enum GroupAlarmCandidates {
    /// Alarms that can be added to a group. Anything already in a group stays hidden.
    static func unassigned(_ alarms: [Alarm]) -> [Alarm] {
        alarms
            .filter { $0.groupID == nil }
            .sorted { lhs, rhs in
                if lhs.sortMinute != rhs.sortMinute { return lhs.sortMinute < rhs.sortMinute }
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
    }
}

struct BulkAlarmPatch: Equatable {
    var hour: Int
    var minute: Int
    var repeatDays: Set<Weekday>
    var soundID: String
    var snoozeEnabled: Bool
    var snoozeMinutes: Int
    var label: String
    var applyLabel: Bool
}

enum BulkAlarmEdit {
    static func applying(_ patch: BulkAlarmPatch, to alarm: Alarm, now: Date = .now, calendar: Calendar = .current) -> Alarm {
        var copy = alarm
        let hour = min(23, max(0, patch.hour))
        let minute = min(59, max(0, patch.minute))
        let days = Array(patch.repeatDays).normalized()
        let schedule = AlarmSchedule.wallClock(hour: hour, minute: minute, repeatDays: days)
        copy.schedule = schedule
        copy.soundID = patch.soundID
        copy.snoozeEnabled = patch.snoozeEnabled
        copy.snoozeMinutes = min(30, max(1, patch.snoozeMinutes))
        if patch.applyLabel {
            copy.label = patch.label.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        copy.firesOnceAt = days.isEmpty ? schedule.nextFireDate(from: now, calendar: calendar) : nil
        return copy
    }
}

enum AlarmNote {
    static let maxCharacters = 1000

    static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxCharacters))
    }
}

struct SentAlarm: Codable, Equatable, Identifiable {
    var alarm: Alarm
    var recipientID: UUID
    var recipientName: String
    var sentAt: Date
    var commandID: UUID
    var wakeStatus: WakeStatusKind? = nil
    var wakeStatusAt: Date? = nil
    var friendGroupID: UUID? = nil
    var friendGroupName: String? = nil

    var id: UUID { commandID }
}

struct FriendGroup: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var memberIDs: [UUID]
}

struct WakeTracking: Codable, Equatable, Identifiable {
    var alarmID: UUID
    var commandID: UUID
    var senderID: UUID
    var firedAt: Date
    var snoozeCount: Int
    var dismissedAt: Date?
    var reported: WakeStatusKind?

    var id: UUID { alarmID }
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
    var note: String
    var videoFileID: String?
    var countdownLead: TimeInterval?
    var origin: AlarmOrigin
    var isNew: Bool

    static func makeNew(now: Date = .now, calendar: Calendar = .current, snoozeMinutes: Int = 9) -> AlarmDraft {
        let hour = (calendar.component(.hour, from: now) + 1) % 24
        return AlarmDraft(
            id: UUID(),
            hour: hour,
            minute: 0,
            label: "",
            repeatDays: [],
            soundID: SoundCatalog.defaultID,
            snoozeEnabled: true,
            snoozeMinutes: snoozeMinutes,
            isEnabled: true,
            groupID: nil,
            songText: "",
            note: "",
            videoFileID: nil,
            countdownLead: nil,
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
        note = alarm.note ?? ""
        videoFileID = alarm.videoFileID
        countdownLead = alarm.countdownLead
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
        note: String,
        videoFileID: String? = nil,
        countdownLead: TimeInterval? = nil,
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
        self.note = note
        self.videoFileID = videoFileID
        self.countdownLead = countdownLead
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
            note: AlarmNote.cleaned(note),
            firesOnceAt: repeatDays.isEmpty
                ? schedule.nextFireDate(from: .now, calendar: .current)
                : nil,
            videoFileID: videoFileID,
            countdownLead: countdownLead,
            origin: origin,
            resumeWhenGroupEnables: nil
        )
    }
}
