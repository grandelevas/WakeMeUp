import Foundation

enum NextFireDate {
    /// The next strict-future moment that matches the wall-clock time.
    /// An empty `repeatDays` means "the next occurrence, once".
    static func wallClock(
        hour: Int,
        minute: Int,
        repeatDays: Set<Weekday>,
        from now: Date,
        calendar: Calendar
    ) -> Date? {
        let hour = min(23, max(0, hour))
        let minute = min(59, max(0, minute))
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else {
                continue
            }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let candidate = calendar.date(from: components), candidate > now else { continue }
            if repeatDays.isEmpty {
                return candidate
            }
            if let weekday = Weekday.from(date: candidate, calendar: calendar), repeatDays.contains(weekday) {
                return candidate
            }
        }
        return nil
    }
}
