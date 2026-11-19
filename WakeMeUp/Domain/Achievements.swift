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

enum SupportMilestone: Int, CaseIterable, Identifiable {
    case oneMonth = 1
    case sixMonths = 6
    case oneYear = 12
    case twoYears = 24
    case threeYears = 36

    var id: Int { rawValue }

    func isUnlocked(firstUse: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard let due = calendar.date(byAdding: .month, value: rawValue, to: firstUse) else { return false }
        return now >= due
    }
}
