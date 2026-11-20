import Foundation

struct ReleaseNote: Equatable, Identifiable {
    var version: String
    var build: Int?
    var date: Date
    var changes: [String: [String]]

    var id: String {
        let day = Self.dayStamp.string(from: date)
        let hint = changes.values.flatMap(\.self).first ?? ""
        return "\(version)-\(build.map(String.init) ?? "none")-\(day)-\(hint)"
    }

    func bullets(for languageCode: String) -> [String] {
        if let exact = changes[languageCode], !exact.isEmpty {
            return exact
        }
        let prefix = String(languageCode.prefix(2)).lowercased()
        if let match = changes.first(where: { $0.key.lowercased().hasPrefix(prefix) && !$0.value.isEmpty }) {
            return match.value
        }
        return changes["en"] ?? []
    }

    var heading: String {
        if let build {
            return "\(version) (\(build))"
        }
        return version
    }

    private static let dayStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct ReleaseNotesDocument: Equatable {
    var entries: [ReleaseNote]

    var newestFirst: [ReleaseNote] {
        entries.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return (lhs.build ?? -1) > (rhs.build ?? -1)
        }
    }

    static func decode(_ data: Data) throws -> ReleaseNotesDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(ReleaseNote.dayParser)
        let raw = try decoder.decode(File.self, from: data)
        return ReleaseNotesDocument(entries: raw.entries.map(\.note))
    }

    static func bundled(bundle: Bundle = .main) -> ReleaseNotesDocument {
        guard let url = bundle.url(forResource: "release-notes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? decode(data) else {
            return ReleaseNotesDocument(entries: [])
        }
        return document
    }
}

enum ReleaseNotesPrompt {
    static let storageKey = "wakito.lastSeenBuild"

    /// Shows after the installed build changes. The first launch only remembers the build.
    static func shouldShow(currentBuild: String, defaults: UserDefaults) -> Bool {
        let trimmed = currentBuild.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let seen = defaults.string(forKey: storageKey), !seen.isEmpty else { return false }
        return seen != trimmed
    }

    static func markSeen(currentBuild: String, defaults: UserDefaults) {
        let trimmed = currentBuild.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        defaults.set(trimmed, forKey: storageKey)
    }
}

private struct File: Decodable {
    var entries: [RawEntry]
}

private struct RawEntry: Decodable {
    var version: String
    var build: Int?
    var date: Date
    var changes: [String: [String]]

    var note: ReleaseNote {
        ReleaseNote(version: version, build: build, date: date, changes: changes)
    }
}

private extension ReleaseNote {
    static let dayParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
