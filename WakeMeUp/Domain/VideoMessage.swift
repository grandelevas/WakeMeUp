import Foundation

enum EditorDraftSession {
    /// A camera presentation can make SwiftUI dismiss the editor sheet and write nil into the item binding.
    /// While a video is being recorded, that nil is ignored so the draft stays on screen.
    static func draft(current: AlarmDraft?, proposed: AlarmDraft?, capturingVideo: Bool) -> AlarmDraft? {
        if proposed == nil, capturingVideo {
            return current
        }
        return proposed
    }
}

enum VideoMessagePolicy {
    static let maxSeconds: TimeInterval = 30
    /// Medium export, then a lower preset if needed, stays under a CloudKit asset.
    static let maxBytes = 12 * 1024 * 1024
    static let fileExtension = "mp4"

    static func clamped(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return min(seconds, maxSeconds)
    }

    static func fits(byteCount: Int) -> Bool {
        byteCount > 0 && byteCount <= maxBytes
    }

    static func makeID() -> String {
        "video-\(UUID().uuidString)"
    }

    static func isVideoID(_ id: String?) -> Bool {
        guard let id else { return false }
        return id.hasPrefix("video-")
    }
}

enum OutgoingVideo {
    struct Payload: Equatable {
        var recordName: String?
        var warn: Bool
    }

    /// A failed video upload must not cancel the alarm. The command goes out without the clip.
    static func payload(recordName: String?, uploaded: Bool) -> Payload {
        if let recordName, uploaded, VideoMessagePolicy.isVideoID(recordName) {
            return Payload(recordName: recordName, warn: false)
        }
        return Payload(recordName: nil, warn: recordName != nil)
    }
}

enum PickedVideoFile {
    /// `UIImagePickerController` deletes `mediaURL` when the camera is dismissed.
    /// The bytes have to be copied first, into a folder the app owns.
    static func durableCopy(of source: URL, inbox: URL, name: String = UUID().uuidString) throws -> URL {
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let destination = inbox.appendingPathComponent("\(name).\(ext)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}

enum RecentAlarmVideo {
    static let idKey = "wakito.recentVideoAlarm"
    static let atKey = "wakito.recentVideoAt"
    static let window: TimeInterval = 180

    static func remember(_ id: UUID, now: Date, defaults: UserDefaults) {
        defaults.set(id.uuidString, forKey: idKey)
        defaults.set(now.timeIntervalSince1970, forKey: atKey)
    }

    static func pending(now: Date, defaults: UserDefaults) -> UUID? {
        guard let text = defaults.string(forKey: idKey), let id = UUID(uuidString: text) else { return nil }
        let at = Date(timeIntervalSince1970: defaults.double(forKey: atKey))
        guard now.timeIntervalSince(at) <= window else {
            clear(defaults: defaults)
            return nil
        }
        return id
    }

    static func clear(defaults: UserDefaults) {
        defaults.removeObject(forKey: idKey)
        defaults.removeObject(forKey: atKey)
    }
}

enum VideoFileCheck {
    static func byteCount(at url: URL) -> Int {
        let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return size?.intValue ?? 0
    }
}
