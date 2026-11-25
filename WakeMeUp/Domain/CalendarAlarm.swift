import Foundation

enum CalendarRepeat: String, Codable, Equatable, CaseIterable, Identifiable {
    case yearly
    case monthly
    case weekly
    case once

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .yearly: "calendar.repeat.yearly"
        case .monthly: "calendar.repeat.monthly"
        case .weekly: "calendar.repeat.weekly"
        case .once: "calendar.repeat.once"
        }
    }

    var repeats: Bool { self != .once }
}

struct CalendarAlarm: Codable, Equatable, Identifiable {
    var id: UUID
    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var minute: Int
    var repeatRule: CalendarRepeat
    var label: String
    var soundID: String
    var snoozeEnabled: Bool
    var snoozeMinutes: Int
    var isEnabled: Bool
    var note: String? = nil

    func nextFire(from now: Date, calendar: Calendar) -> Date? {
        CalendarFire.next(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            rule: repeatRule,
            from: now,
            calendar: calendar
        )
    }

    func occurs(on day: Date, calendar: Calendar) -> Bool {
        CalendarFire.occurs(self, on: day, calendar: calendar)
    }

    /// AlarmKit has weekly and one-time schedules. Monthly and yearly use the next date, then the app schedules the one after that.
    func alarmForScheduling(now: Date, calendar: Calendar) -> Alarm? {
        guard isEnabled else { return nil }
        switch repeatRule {
        case .weekly:
            guard let anchor = CalendarFire.date(year: year, month: month, day: day, hour: hour, minute: minute, calendar: calendar),
                  let weekday = Weekday.from(date: anchor, calendar: calendar) else { return nil }
            return makeAlarm(schedule: .wallClock(hour: hour, minute: minute, repeatDays: [weekday]), firesOnceAt: nil)
        case .once, .monthly, .yearly:
            guard let fire = nextFire(from: now, calendar: calendar) else { return nil }
            return makeAlarm(schedule: .oneShot(fireAt: fire), firesOnceAt: fire)
        }
    }

    private func makeAlarm(schedule: AlarmSchedule, firesOnceAt: Date?) -> Alarm {
        Alarm(
            id: id,
            schedule: schedule,
            label: label,
            soundID: soundID,
            snoozeEnabled: snoozeEnabled,
            snoozeMinutes: snoozeMinutes,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            note: note,
            firesOnceAt: firesOnceAt,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
    }
}

enum CalendarFire {
    static func next(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        rule: CalendarRepeat,
        from now: Date,
        calendar: Calendar
    ) -> Date? {
        switch rule {
        case .once:
            guard let date = date(year: year, month: month, day: day, hour: hour, minute: minute, calendar: calendar) else {
                return nil
            }
            return date > now ? date : nil
        case .weekly:
            guard let anchor = date(year: year, month: month, day: day, hour: hour, minute: minute, calendar: calendar),
                  let weekday = Weekday.from(date: anchor, calendar: calendar) else { return nil }
            return NextFireDate.wallClock(
                hour: hour,
                minute: minute,
                repeatDays: [weekday],
                from: now,
                calendar: calendar
            )
        case .monthly:
            return nextMonth(day: day, hour: hour, minute: minute, from: now, calendar: calendar)
        case .yearly:
            return nextYear(month: month, day: day, hour: hour, minute: minute, from: now, calendar: calendar)
        }
    }

    static func occurs(_ alarm: CalendarAlarm, on day: Date, calendar: Calendar) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let anchor = date(
            year: alarm.year,
            month: alarm.month,
            day: alarm.day,
            hour: alarm.hour,
            minute: alarm.minute,
            calendar: calendar
        ) else { return false }
        if dayStart < calendar.startOfDay(for: anchor) { return false }
        switch alarm.repeatRule {
        case .once:
            return calendar.isDate(dayStart, inSameDayAs: anchor)
        case .weekly:
            return calendar.component(.weekday, from: dayStart) == calendar.component(.weekday, from: anchor)
        case .monthly:
            return calendar.component(.day, from: dayStart) == clampedDay(alarm.day, in: dayStart, calendar: calendar)
        case .yearly:
            return calendar.component(.month, from: dayStart) == alarm.month
                && calendar.component(.day, from: dayStart) == clampedDay(alarm.day, in: dayStart, calendar: calendar)
        }
    }

    /// A one-time calendar alarm leaves after it rings or its moment has passed. Repeating ones stay.
    static func shouldRemove(_ alarm: CalendarAlarm, now: Date, calendar: Calendar, hasRung: Bool) -> Bool {
        guard alarm.repeatRule == .once else { return false }
        if hasRung { return true }
        return alarm.nextFire(from: now, calendar: calendar) == nil
    }

    static func keeping(_ alarms: [CalendarAlarm], now: Date, calendar: Calendar, rungIDs: Set<UUID>) -> [CalendarAlarm] {
        alarms.filter { !shouldRemove($0, now: now, calendar: calendar, hasRung: rungIDs.contains($0.id)) }
    }

    static func scheduled(_ alarms: [CalendarAlarm], now: Date, calendar: Calendar) -> [Alarm] {
        alarms.compactMap { $0.alarmForScheduling(now: now, calendar: calendar) }
    }

    static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        let probe = DateComponents(year: year, month: month, day: 1)
        guard let monthStart = calendar.date(from: probe) else { return nil }
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = clampedDay(day, in: monthStart, calendar: calendar)
        parts.hour = min(23, max(0, hour))
        parts.minute = min(59, max(0, minute))
        parts.second = 0
        return calendar.date(from: parts)
    }

    static func clampedDay(_ day: Int, in monthDate: Date, calendar: Calendar) -> Int {
        let count = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 28
        return min(max(1, day), count)
    }

    private static func nextMonth(day: Int, hour: Int, minute: Int, from now: Date, calendar: Calendar) -> Date? {
        let parts = calendar.dateComponents([.year, .month], from: now)
        guard var cursor = calendar.date(from: parts) else { return nil }
        for _ in 0..<36 {
            if let candidate = date(
                year: calendar.component(.year, from: cursor),
                month: calendar.component(.month, from: cursor),
                day: day,
                hour: hour,
                minute: minute,
                calendar: calendar
            ), candidate > now {
                return candidate
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { return nil }
            cursor = next
        }
        return nil
    }

    private static func nextYear(month: Int, day: Int, hour: Int, minute: Int, from now: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: now)
        for offset in 0..<8 {
            if let candidate = date(year: year + offset, month: month, day: day, hour: hour, minute: minute, calendar: calendar),
               candidate > now {
                return candidate
            }
        }
        return nil
    }
}

enum CalendarGrid {
    struct Cell: Identifiable, Equatable {
        var date: Date
        var inMonth: Bool
        var id: Date { date }
    }

    static func cells(monthContaining date: Date, calendar: Calendar) -> [Cell] {
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let start = calendar.date(from: parts),
              let dayCount = calendar.range(of: .day, in: .month, for: start)?.count else { return [] }
        let weekday = calendar.component(.weekday, from: start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [Cell] = []
        if leading > 0, let first = calendar.date(byAdding: .day, value: -leading, to: start) {
            for offset in 0..<leading {
                guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
                cells.append(Cell(date: day, inMonth: false))
            }
        }
        for offset in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            cells.append(Cell(date: day, inMonth: true))
        }
        while cells.count % 7 != 0 {
            guard let last = cells.last?.date, let next = calendar.date(byAdding: .day, value: 1, to: last) else { break }
            cells.append(Cell(date: next, inMonth: false))
        }
        return cells
    }
}
