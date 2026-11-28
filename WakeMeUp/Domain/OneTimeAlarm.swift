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

    /// The one-time occurrence has rung or its moment has passed. The alarm stays; it is switched off.
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

    /// Switch a finished one-time alarm off. An alarm that is still alerting or snoozed stays on.
    /// `rungIDs` are stops, so they are switched off even if AlarmKit has not caught up.
    static func partition(
        alarms: [Alarm],
        sent: [SentAlarm],
        now: Date,
        calendar: Calendar,
        rungIDs: Set<UUID>,
        keepAwake: Set<UUID> = []
    ) -> (alarms: [Alarm], sent: [SentAlarm]) {
        let awake = keepAwake.subtracting(rungIDs)
        let keptAlarms = alarms.map { alarm -> Alarm in
            let stamped = stamped(alarm, now: now, calendar: calendar)
            let finished = shouldRemove(
                schedule: stamped.schedule,
                firesOnceAt: stamped.firesOnceAt,
                now: now,
                hasRung: rungIDs.contains(stamped.id)
            )
            guard finished, !awake.contains(stamped.id) else { return stamped }
            var copy = stamped
            copy.isEnabled = false
            return copy
        }
        let keptSent = sent.map { item -> SentAlarm in
            guard shouldRemoveSent(item, now: now, calendar: calendar) else { return item }
            var copy = item
            copy.alarm.isEnabled = false
            return copy
        }
        return (keptAlarms, keptSent)
    }

    /// Turning a finished one-time alarm back on aims it at the next time that clock time occurs.
    static func armed(_ alarm: Alarm, now: Date, calendar: Calendar) -> Alarm {
        guard !isRepeating(alarm.schedule) else { return alarm }
        var copy = alarm
        copy.isEnabled = true
        switch copy.schedule {
        case let .oneShot(fireAt):
            guard fireAt <= now else { return copy }
            let hour = calendar.component(.hour, from: fireAt)
            let minute = calendar.component(.minute, from: fireAt)
            let wall = AlarmSchedule.wallClock(hour: hour, minute: minute, repeatDays: [])
            if let next = wall.nextFireDate(from: now, calendar: calendar) {
                copy.schedule = .oneShot(fireAt: next)
            }
        case .wallClock:
            if copy.firesOnceAt == nil || copy.firesOnceAt! <= now {
                copy.firesOnceAt = copy.schedule.nextFireDate(from: now, calendar: calendar)
            }
        }
        return copy
    }
}
