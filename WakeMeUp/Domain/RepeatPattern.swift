import Foundation

enum RepeatPattern: Equatable {
    case never
    case everyDay
    case weekdays
    case weekends
    case custom
}

enum RepeatPreset: Equatable, Hashable, CaseIterable {
    case everyDay
    case weekdays
    case weekends

    var days: Set<Weekday> {
        switch self {
        case .everyDay: Set(Weekday.allCases)
        case .weekdays: RepeatPatternClassifier.weekdays
        case .weekends: RepeatPatternClassifier.weekends
        }
    }
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

    /// A preset that is already the whole selection clears it. Any other selection is replaced.
    static func toggle(_ preset: RepeatPreset, in selection: Set<Weekday>) -> Set<Weekday> {
        selection == preset.days ? [] : preset.days
    }

    static func selectedPreset(_ selection: Set<Weekday>) -> RepeatPreset? {
        RepeatPreset.allCases.first { $0.days == selection }
    }
}
