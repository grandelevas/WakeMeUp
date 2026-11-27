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

enum VideoFileCheck {
    static func byteCount(at url: URL) -> Int {
        let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return size?.intValue ?? 0
    }
}
