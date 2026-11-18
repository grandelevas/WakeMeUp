import Foundation

enum Weekday: String, Codable, CaseIterable, Identifiable, Hashable {
    case sunday
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var id: String { rawValue }

    /// Gregorian `Calendar` weekday index. Sunday is 1.
    var gregorianIndex: Int {
        switch self {
        case .sunday: 1
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        case .saturday: 7
        }
    }

    var localeWeekday: Locale.Weekday {
        switch self {
        case .sunday: .sunday
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        }
    }

    static func from(date: Date, calendar: Calendar) -> Weekday? {
        let index = calendar.component(.weekday, from: date)
        return allCases.first { $0.gregorianIndex == index }
    }

    func veryShortSymbol(calendar: Calendar) -> String {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let index = gregorianIndex - 1
        guard symbols.indices.contains(index) else { return String(rawValue.prefix(1)).uppercased() }
        return symbols[index]
    }

    static func ordered(calendar: Calendar) -> [Weekday] {
        let start = calendar.firstWeekday
        return (0..<7).compactMap { offset in
            let index = ((start - 1 + offset) % 7) + 1
            return allCases.first { $0.gregorianIndex == index }
        }
    }
}

extension Array where Element == Weekday {
    func normalized() -> [Weekday] {
        var seen = Set<Weekday>()
        return filter { seen.insert($0).inserted }
            .sorted { $0.gregorianIndex < $1.gregorianIndex }
    }
}
