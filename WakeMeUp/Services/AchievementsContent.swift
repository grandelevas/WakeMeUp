import Foundation

enum AchievementsContentStore {
    private static let cacheName = "achievements-cache.json"

    static func bundled() -> AchievementsDocument? {
        guard let url = Bundle.main.url(forResource: "achievements", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? AchievementsDocument.decode(data)
    }

    static func cached() -> AchievementsDocument? {
        guard let data = try? Data(contentsOf: cacheURL()) else { return nil }
        return try? AchievementsDocument.decode(data)
    }

    static func saveCache(_ data: Data) {
        guard (try? AchievementsDocument.decode(data)) != nil else { return }
        try? data.write(to: cacheURL(), options: .atomic)
    }

    static func startingDocument() -> AchievementsDocument? {
        cached() ?? bundled()
    }

    @discardableResult
    static func refresh(urlString: String, session: URLSession = .shared) async -> AchievementsDocument? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let document = try? AchievementsDocument.decode(data) else {
            return nil
        }
        saveCache(data)
        return document
    }

    private static func cacheURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("WakeMeUp", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(cacheName)
    }
}

enum LocalAchievementsStore {
    private static let key = "wakito.localAchievements"

    static func load() -> LocalAchievements {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(LocalAchievements.self, from: data) else {
            return LocalAchievements()
        }
        return decoded
    }

    static func save(_ value: LocalAchievements) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
