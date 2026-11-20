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

    var isBlank: Bool {
        en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && pl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Paragraphs are separated by a blank line. A single newline stays inside a paragraph.
    func paragraphs(languageCode: String) -> [String] {
        resolved(languageCode: languageCode)
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct CampaignPhoto: Codable, Equatable {
    var url: String
    var caption: LocalizedCopy?

    var link: URL? { SecureLink.url(from: url) }

    var visibleCaption: LocalizedCopy? {
        guard let caption, !caption.isBlank else { return nil }
        return caption
    }
}

struct CampaignUpdate: Codable, Equatable {
    var date: String
    var title: LocalizedCopy?
    var text: LocalizedCopy
    var photos: [CampaignPhoto]?

    var visibleTitle: LocalizedCopy? {
        guard let title, !title.isBlank else { return nil }
        return title
    }

    var gallery: [CampaignPhoto] {
        (photos ?? []).filter { $0.link != nil }
    }
}

struct CampaignThanks: Codable, Equatable {
    var from: String?
    var date: String?
    var text: LocalizedCopy
    var photoURL: String?
    var videoURL: String?

    var author: String? {
        let trimmed = from?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var day: String? {
        let trimmed = date?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var photo: URL? { SecureLink.url(from: photoURL) }
    var video: URL? { SecureLink.url(from: videoURL) }
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
    /// Optional since schema 1. Missing means the older file, and the extra UI stays hidden.
    var description: LocalizedCopy?
    var photos: [CampaignPhoto]?
    var updates: [CampaignUpdate]?
    var thanks: [CampaignThanks]?

    var progress: Double {
        guard goalAmount > 0 else { return 0 }
        let ratio = (raisedAmount as NSDecimalNumber).doubleValue / (goalAmount as NSDecimalNumber).doubleValue
        return min(1, max(0, ratio))
    }

    func story(languageCode: String) -> [String] {
        guard let description, !description.isBlank else { return [] }
        return description.paragraphs(languageCode: languageCode)
    }

    var gallery: [CampaignPhoto] {
        (photos ?? []).filter { $0.link != nil }
    }

    var visibleUpdates: [CampaignUpdate] {
        (updates ?? []).filter { !$0.text.isBlank }
    }

    var visibleThanks: [CampaignThanks] {
        (thanks ?? []).filter { !$0.text.isBlank }
    }

    var hasStory: Bool {
        story(languageCode: "pl").isEmpty == false || story(languageCode: "en").isEmpty == false
    }
}

enum SecureLink {
    static func url(from string: String?) -> URL? {
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https" else { return nil }
        return url
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
    var userCount: Int?
    var userCountDate: String?

    /// A missing or non-positive count is hidden. The app never invents one.
    var visibleUserCount: Int? {
        guard let userCount, userCount > 0 else { return nil }
        return userCount
    }

    static let supportedSchemaVersion = 1

    var totalDonated: Decimal {
        history.reduce(0) { $0 + $1.amount }
    }

    var peopleHelped: Int {
        Set(history.map { $0.recipient.en }).count
    }

    func applying(community: CommunityCountSnapshot) -> AchievementsDocument {
        guard community.userCount != nil else { return self }
        var copy = self
        copy.userCount = community.userCount
        let date = community.userCountDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        copy.userCountDate = date.isEmpty ? nil : date
        return copy
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

struct CommunityCountSnapshot: Decodable, Equatable {
    var userCount: Int?
    var userCountDate: String?
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
