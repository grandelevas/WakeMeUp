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

struct VideoNoticeArm: Equatable, Codable {
    var alarmID: UUID
    var videoFileID: String
    var label: String
    var fireAt: Date
}

enum VideoMessageNotice {
    static let userInfoKey = "videoMessage"
    static let fileInfoKey = "videoFileID"
    static let storageKey = "wakito.videoNoticeArms"
    /// A stop that happened while the app was not running is still announced for a few hours.
    static let staleAfter: TimeInterval = 6 * 60 * 60

    static func shouldPost(videoFileID: String?) -> Bool {
        VideoMessagePolicy.isVideoID(videoFileID)
    }

    static func identifier(alarmID: UUID) -> String {
        "video-message-\(alarmID.uuidString)"
    }

    static func load(defaults: UserDefaults) -> [VideoNoticeArm] {
        guard let data = defaults.data(forKey: storageKey),
              let arms = try? JSONDecoder().decode([VideoNoticeArm].self, from: data) else {
            return []
        }
        return arms
    }

    static func save(_ arms: [VideoNoticeArm], defaults: UserDefaults) {
        guard !arms.isEmpty, let data = try? JSONEncoder().encode(arms) else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    /// Future fires only. A fire that already passed stays in storage until it is announced or goes stale.
    static func arms(for alarms: [Alarm], now: Date, calendar: Calendar) -> [VideoNoticeArm] {
        alarms.compactMap { alarm in
            guard alarm.isEnabled,
                  let file = alarm.videoFileID,
                  shouldPost(videoFileID: file),
                  let fireAt = upcomingFire(of: alarm, now: now, calendar: calendar) else { return nil }
            return VideoNoticeArm(alarmID: alarm.id, videoFileID: file, label: alarm.label, fireAt: fireAt)
        }
    }

    static func merge(existing: [VideoNoticeArm], scheduled: [VideoNoticeArm], now: Date) -> [VideoNoticeArm] {
        var merged: [VideoNoticeArm] = []
        var consumed = Set<UUID>()
        for arm in scheduled {
            if let previous = existing.first(where: { $0.alarmID == arm.alarmID }),
               owesNotice(previous, now: now),
               previous.fireAt != arm.fireAt {
                merged.append(previous)
            } else {
                merged.append(arm)
            }
            consumed.insert(arm.alarmID)
        }
        for arm in existing where !consumed.contains(arm.alarmID) && owesNotice(arm, now: now) {
            merged.append(arm)
        }
        return merged
    }

    /// Remember a video alarm that is ringing now, so a later stop can still find the clip.
    static func noteRinging(
        arms: [VideoNoticeArm],
        alarmID: UUID,
        videoFileID: String,
        label: String,
        now: Date
    ) -> [VideoNoticeArm] {
        guard shouldPost(videoFileID: videoFileID) else { return arms }
        var arms = arms
        if let index = arms.firstIndex(where: { $0.alarmID == alarmID }) {
            arms[index].videoFileID = videoFileID
            arms[index].label = label
            if arms[index].fireAt > now {
                arms[index].fireAt = now
            }
        } else {
            arms.append(VideoNoticeArm(alarmID: alarmID, videoFileID: videoFileID, label: label, fireAt: now))
        }
        return arms
    }

    /// A due alarm that is no longer alerting and not snoozed gets one notification.
    static func noticesDue(
        arms: [VideoNoticeArm],
        alerting: Set<UUID>,
        countingDown: Set<UUID>,
        now: Date
    ) -> (post: [VideoNoticeArm], keep: [VideoNoticeArm]) {
        var post: [VideoNoticeArm] = []
        var keep: [VideoNoticeArm] = []
        for arm in arms {
            if alerting.contains(arm.alarmID) || countingDown.contains(arm.alarmID) || arm.fireAt > now {
                keep.append(arm)
            } else if owesNotice(arm, now: now) {
                post.append(arm)
            }
        }
        return (post, keep)
    }

    private static func owesNotice(_ arm: VideoNoticeArm, now: Date) -> Bool {
        arm.fireAt <= now && now.timeIntervalSince(arm.fireAt) <= staleAfter
    }

    private static func upcomingFire(of alarm: Alarm, now: Date, calendar: Calendar) -> Date? {
        if let once = alarm.firesOnceAt, once > now { return once }
        if case let .oneShot(date) = alarm.schedule, date > now { return date }
        return alarm.schedule.nextFireDate(from: now, calendar: calendar)
    }
}

enum VideoFileCheck {
    static func byteCount(at url: URL) -> Int {
        let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return size?.intValue ?? 0
    }
}
