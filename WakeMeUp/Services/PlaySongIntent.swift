import AlarmKit
import AppIntents
import Foundation
import UIKit

/// Writes the song the alarm button asked to open. The intent runs in the app
/// when `openAppWhenRun` is set, and also in the widget process, so both the
/// standard defaults and the app group are updated.
enum LaunchHandoff {
    private static let alarmKey = "wakemeup.pendingAlarm"
    private static let songKey = "wakemeup.pendingSong"

    static func write(alarmID: String, songURL: URL) {
        let group = UserDefaults(suiteName: AppConfig.appGroupID)
        group?.set(alarmID, forKey: alarmKey)
        group?.set(songURL.absoluteString, forKey: songKey)
        UserDefaults.standard.set(alarmID, forKey: alarmKey)
        UserDefaults.standard.set(songURL.absoluteString, forKey: songKey)
    }

    static func consume() -> (alarmID: UUID, songURL: URL)? {
        let group = UserDefaults(suiteName: AppConfig.appGroupID)
        let alarm = group?.string(forKey: alarmKey) ?? UserDefaults.standard.string(forKey: alarmKey)
        let song = group?.string(forKey: songKey) ?? UserDefaults.standard.string(forKey: songKey)
        group?.removeObject(forKey: alarmKey)
        group?.removeObject(forKey: songKey)
        UserDefaults.standard.removeObject(forKey: alarmKey)
        UserDefaults.standard.removeObject(forKey: songKey)
        guard let alarm, let song, let id = UUID(uuidString: alarm), let url = URL(string: song) else {
            return nil
        }
        return (id, url)
    }

    static func isAlarmVideo(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "wakemeup" && url.host?.lowercased() == "video"
    }

    static func videoURL(alarmID: UUID) -> URL {
        URL(string: "wakemeup://video/\(alarmID.uuidString)")!
    }
}

struct PlaySongIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Play my song"
    static var description = IntentDescription("Stops the Wakito alarm and opens the linked song.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Alarm ID")
    var alarmID: String

    @Parameter(title: "Song URL")
    var songURL: String

    init() {
        alarmID = ""
        songURL = ""
    }

    init(alarmID: String, songURL: String) {
        self.alarmID = alarmID
        self.songURL = songURL
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        let destination = URL(string: songURL) ?? URL(string: "wakemeup://ring/\(alarmID)")!
        LaunchHandoff.write(alarmID: alarmID, songURL: destination)
        if !Bundle.main.bundlePath.hasSuffix(".appex") {
            await MainActor.run {
                UIApplication.shared.open(destination)
            }
            if let id = UUID(uuidString: alarmID) {
                try? AlarmManager.shared.stop(id: id)
            }
        }
        return .result(opensIntent: OpenURLIntent(destination))
    }
}

struct OpenAlarmVideoIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Watch video"
    static var description = IntentDescription("Opens Wakito and plays the alarm's video message.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() { alarmID = "" }

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let id = UUID(uuidString: alarmID) else {
            return .result(opensIntent: OpenURLIntent(URL(string: "wakemeup://")!))
        }
        let destination = LaunchHandoff.videoURL(alarmID: id)
        LaunchHandoff.write(alarmID: alarmID, songURL: destination)
        if !Bundle.main.bundlePath.hasSuffix(".appex") {
            await MainActor.run {
                UIApplication.shared.open(destination)
            }
            try? AlarmManager.shared.stop(id: id)
        }
        return .result(opensIntent: OpenURLIntent(destination))
    }
}
