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

    static func communityCount(urlString: String, session: URLSession = .shared) async -> CommunityCountSnapshot? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https" else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }
        return try? JSONDecoder().decode(CommunityCountSnapshot.self, from: data)
    }

    private static func cacheURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("WakeMeUp", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(cacheName)
    }
}

protocol FirstUseStore {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: FirstUseStore {}
extension NSUbiquitousKeyValueStore: FirstUseStore {}

enum SupportTenureStore {
    static let key = "wakito.firstUse"

    /// The earlier of the local date and iCloud Key-Value Storage, so a new phone keeps the original start.
    static func ensureFirstUse(
        now: Date = .now,
        local: FirstUseStore = UserDefaults.standard,
        cloud: FirstUseStore = NSUbiquitousKeyValueStore.default
    ) -> Date {
        let localDate = date(in: local)
        let cloudDate = date(in: cloud)
        let first = [localDate, cloudDate].compactMap { $0 }.min() ?? now
        write(first, to: local)
        write(first, to: cloud)
        return first
    }

    private static func date(in store: FirstUseStore) -> Date? {
        if let number = store.object(forKey: key) as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        if let value = store.object(forKey: key) as? Double {
            return Date(timeIntervalSince1970: value)
        }
        return nil
    }

    private static func write(_ date: Date, to store: FirstUseStore) {
        store.set(date.timeIntervalSince1970, forKey: key)
    }
}
