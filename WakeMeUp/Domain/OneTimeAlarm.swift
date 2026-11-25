import Foundation

enum IncomingCommandPolicy {
    /// Commands this phone wrote for someone else are not alarms for this phone.
    static func shouldApply(command: RemoteAlarmCommand, profileID: UUID) -> Bool {
        command.recipientID == profileID && command.senderID != profileID
    }
}

enum SelfAlarmCleanup {
    static func isSelfAuthored(_ alarm: Alarm, profileID: UUID) -> Bool {
        guard case let .remote(senderID, _, _) = alarm.origin else { return false }
        return senderID == profileID
    }

    static func removingSelfAuthored(from alarms: [Alarm], profileID: UUID) -> [Alarm] {
        alarms.filter { !isSelfAuthored($0, profileID: profileID) }
    }
}

enum OneTimeAlarmExpiry {
    static func isRepeating(_ schedule: AlarmSchedule) -> Bool {
        switch schedule {
        case .oneShot:
            false
        case let .wallClock(_, _, days):
            !days.isEmpty
        }
    }

    /// Non-repeating alarms leave after they ring, or after their one-time date has passed.
    static func shouldRemove(
        schedule: AlarmSchedule,
        firesOnceAt: Date?,
        now: Date,
        hasRung: Bool
    ) -> Bool {
        if isRepeating(schedule) { return false }
        if hasRung { return true }
        switch schedule {
        case let .oneShot(fireAt):
            return fireAt <= now
        case .wallClock:
            guard let firesOnceAt else { return false }
            return firesOnceAt <= now
        }
    }

    static func stamped(_ alarm: Alarm, now: Date, calendar: Calendar) -> Alarm {
        guard !isRepeating(alarm.schedule) else { return alarm }
        if case .oneShot = alarm.schedule { return alarm }
        guard alarm.firesOnceAt == nil else { return alarm }
        var copy = alarm
        copy.firesOnceAt = alarm.schedule.nextFireDate(from: now, calendar: calendar)
        return copy
    }

    static func shouldRemoveSent(_ item: SentAlarm, now: Date, calendar: Calendar) -> Bool {
        if isRepeating(item.alarm.schedule) { return false }
        if item.wakeStatus != nil { return true }
        switch item.alarm.schedule {
        case let .oneShot(fireAt):
            return fireAt <= now
        case .wallClock:
            let due = item.alarm.firesOnceAt ?? item.alarm.schedule.nextFireDate(from: item.sentAt, calendar: calendar)
            guard let due else { return false }
            return due <= now
        }
    }

    static func partition(
        alarms: [Alarm],
        sent: [SentAlarm],
        now: Date,
        calendar: Calendar,
        rungIDs: Set<UUID>
    ) -> (alarms: [Alarm], sent: [SentAlarm]) {
        let keptAlarms = alarms.compactMap { alarm -> Alarm? in
            let stamped = stamped(alarm, now: now, calendar: calendar)
            if shouldRemove(
                schedule: stamped.schedule,
                firesOnceAt: stamped.firesOnceAt,
                now: now,
                hasRung: rungIDs.contains(stamped.id)
            ) {
                return nil
            }
            return stamped
        }
        let keptSent = sent.filter { !shouldRemoveSent($0, now: now, calendar: calendar) }
        return (keptAlarms, keptSent)
    }
}
