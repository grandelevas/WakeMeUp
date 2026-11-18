import Foundation

enum RepeatPattern: Equatable {
    case never
    case everyDay
    case weekdays
    case weekends
    case custom
}

enum RepeatPatternClassifier {
    static let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let weekends: Set<Weekday> = [.saturday, .sunday]

    static func classify(_ days: [Weekday]) -> RepeatPattern {
        let set = Set(days)
        if set.isEmpty { return .never }
        if set.count == Weekday.allCases.count { return .everyDay }
        if set == weekdays { return .weekdays }
        if set == weekends { return .weekends }
        return .custom
    }
}
