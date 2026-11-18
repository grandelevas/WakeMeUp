import Foundation

enum ClockFormat {
    struct Parts: Equatable {
        var time: String
        var period: String
    }

    static func parts(
        hour: Int,
        minute: Int,
        locale: Locale,
        timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!
    ) -> Parts {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 15, hour: hour, minute: minute)
        ) ?? .now
        let uses12Hour = uses12HourClock(locale: locale)
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = locale
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = uses12Hour ? "h:mm" : "HH:mm"
        let periodFormatter = DateFormatter()
        periodFormatter.calendar = calendar
        periodFormatter.locale = locale
        periodFormatter.timeZone = timeZone
        periodFormatter.dateFormat = "a"
        return Parts(
            time: timeFormatter.string(from: date),
            period: uses12Hour ? periodFormatter.string(from: date) : ""
        )
    }

    static func uses12HourClock(locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
        return format.contains("a")
    }
}
