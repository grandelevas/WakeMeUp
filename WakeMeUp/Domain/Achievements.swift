import Foundation

struct LocalizedCopy: Codable, Equatable {
    var en: String
    var pl: String

    func resolved(languageCode: String) -> String {
        if languageCode.hasPrefix("pl") {
            return pl.isEmpty ? en : pl
        }
        return en.isEmpty ? pl : en
    }
}

struct AchievementCampaign: Codable, Equatable, Identifiable {
    var id: String
    var title: LocalizedCopy
    var who: LocalizedCopy
    var why: LocalizedCopy
    var photoURL: String
    var goalAmount: Decimal
    var raisedAmount: Decimal
    var date: String
    var linkURL: String

    var progress: Double {
        guard goalAmount > 0 else { return 0 }
        let ratio = (raisedAmount as NSDecimalNumber).doubleValue / (goalAmount as NSDecimalNumber).doubleValue
        return min(1, max(0, ratio))
    }
}

struct AchievementProof: Codable, Equatable, Identifiable {
    var id: String
    var title: LocalizedCopy
    var url: String
}

struct AchievementGift: Codable, Equatable, Identifiable {
    var id: String
    var recipient: LocalizedCopy
    var amount: Decimal
    var date: String
    var method: LocalizedCopy
    var description: LocalizedCopy
    var proof: [AchievementProof]
}

struct AchievementsDocument: Codable, Equatable {
    var schemaVersion: Int
    var currency: String
    var disclosure: LocalizedCopy
    var campaign: AchievementCampaign?
    var history: [AchievementGift]

    static let supportedSchemaVersion = 1

    var totalDonated: Decimal {
        history.reduce(0) { $0 + $1.amount }
    }

    var peopleHelped: Int {
        Set(history.map { $0.recipient.en }).count
    }

    static func decode(_ data: Data) throws -> AchievementsDocument {
        let decoder = JSONDecoder()
        let document = try decoder.decode(AchievementsDocument.self, from: data)
        guard document.schemaVersion == supportedSchemaVersion else {
            throw AchievementsContentError.unsupportedSchema(document.schemaVersion)
        }
        return document
    }
}

enum AchievementsContentError: Error, Equatable {
    case unsupportedSchema(Int)
    case unreadable
}

struct LocalAchievements: Codable, Equatable {
    var firstAlarm = false
    var friendAlarm = false
    var wakeDays: [String] = []
    var snoozeDays: [String] = []
    var bestStreak = 0

    static let streakGoal = 7

    var sevenDayStreak: Bool { bestStreak >= Self.streakGoal }

    mutating func recordFirstAlarm() {
        firstAlarm = true
    }

    mutating func recordFriendAlarm() {
        friendAlarm = true
    }

    mutating func recordWake(on day: String) {
        guard !snoozeDays.contains(day) else { return }
        if !wakeDays.contains(day) {
            wakeDays.append(day)
        }
        bestStreak = max(bestStreak, Self.longestStreak(wakeDays))
    }

    mutating func recordSnooze(on day: String) {
        if !snoozeDays.contains(day) {
            snoozeDays.append(day)
        }
        wakeDays.removeAll { $0 == day }
        bestStreak = max(bestStreak, Self.longestStreak(wakeDays))
    }

    static func longestStreak(_ days: [String]) -> Int {
        let unique = Array(Set(days)).sorted()
        guard !unique.isEmpty else { return 0 }
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        var best = 1
        var run = 1
        for index in unique.indices.dropFirst() {
            guard let previous = formatter.date(from: unique[index - 1]),
                  let current = formatter.date(from: unique[index]),
                  let gap = calendar.dateComponents([.day], from: previous, to: current).day else {
                run = 1
                continue
            }
            if gap == 1 {
                run += 1
                best = max(best, run)
            } else if gap > 1 {
                run = 1
            }
        }
        return best
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
