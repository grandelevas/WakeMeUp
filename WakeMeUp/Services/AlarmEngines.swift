import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import SwiftUI
import UserNotifications

/// Our model is also named `Alarm`, so AlarmKit's type has to be qualified.
private typealias SystemAlarm = AlarmKit.Alarm

enum AlarmAccessState: Equatable {
    case unknown
    case notDetermined
    case authorized
    case denied
}

@MainActor
final class AlarmKitEngine {
    private let manager = AlarmManager.shared

    func accessState() -> AlarmAccessState {
        switch manager.authorizationState {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        @unknown default: .unknown
        }
    }

    func requestAccess() async -> AlarmAccessState {
        switch manager.authorizationState {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            let state = try? await manager.requestAuthorization()
            return state == .authorized ? .authorized : .denied
        @unknown default:
            return .unknown
        }
    }

    /// Schedules with AlarmKit. Returns false when the system will not ring it
    /// (authorization denied, or the framework rejected the configuration).
    @discardableResult
    func schedule(_ alarm: Alarm, customSounds: [CustomSound]) async -> Bool {
        guard await requestAccess() == .authorized else { return false }
        do {
            let configuration = try makeConfiguration(for: alarm, customSounds: customSounds)
            _ = try await manager.schedule(id: alarm.id, configuration: configuration)
            return true
        } catch {
            return false
        }
    }

    func cancel(id: UUID) {
        try? manager.cancel(id: id)
    }

    func stop(id: UUID) {
        try? manager.stop(id: id)
    }

    func snooze(id: UUID) {
        try? manager.countdown(id: id)
    }

    func observe(_ onUpdate: @escaping @MainActor ([Alarm.ID]) -> Void) async {
        for await alarms in manager.alarmUpdates {
            let alerting = alarms.filter { $0.state == .alerting }.map(\.id)
            onUpdate(alerting)
        }
    }

    private func makeConfiguration(
        for alarm: Alarm,
        customSounds: [CustomSound]
    ) throws -> AlarmManager.AlarmConfiguration<WakeMeUpAlarmMetadata> {
        let title = alarm.label.isEmpty ? String(localized: "alarm.defaultLabel") : alarm.label
        let localizedTitle = LocalizedStringResource(stringLiteral: title)
        let wantsSong = alarm.songLink != nil
        let secondaryBehavior: AlarmPresentation.Alert.SecondaryButtonBehavior? = {
            if wantsSong { return .custom }
            if alarm.snoozeEnabled { return .countdown }
            return nil
        }()
        let secondaryButton: AlarmButton? = {
            guard let secondaryBehavior else { return nil }
            switch secondaryBehavior {
            case .custom:
                return AlarmButton(
                    text: LocalizedStringResource(stringLiteral: String(localized: "song.play")),
                    textColor: .white,
                    systemImageName: "music.note"
                )
            case .countdown:
                return AlarmButton(
                    text: LocalizedStringResource(stringLiteral: String(localized: "ringing.snooze")),
                    textColor: .white,
                    systemImageName: "zzz"
                )
            @unknown default:
                return nil
            }
        }()
        let alert = AlarmPresentation.Alert(
            title: localizedTitle,
            secondaryButton: secondaryButton,
            secondaryButtonBehavior: secondaryBehavior
        )
        let presentation: AlarmPresentation
        if alarm.snoozeEnabled {
            let countdown = AlarmPresentation.Countdown(title: localizedTitle, pauseButton: nil)
            presentation = AlarmPresentation(alert: alert, countdown: countdown)
        } else {
            presentation = AlarmPresentation(alert: alert)
        }
        let attributes = AlarmAttributes<WakeMeUpAlarmMetadata>(
            presentation: presentation,
            metadata: WakeMeUpAlarmMetadata(
                alarmID: alarm.id.uuidString,
                label: title,
                songURL: alarm.songLink?.url.absoluteString
            ),
            tintColor: .orange
        )
        // `.named` looks up this filename in the main bundle or Library/Sounds.
        let soundName = SoundFiles.alarmKitName(for: alarm.soundID, customSounds: customSounds)
        let sound: AlertConfiguration.AlertSound = soundName.isEmpty ? .default : .named(soundName)
        let countdown: SystemAlarm.CountdownDuration? = alarm.snoozeEnabled
            ? SystemAlarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(alarm.snoozeMinutes * 60))
            : nil
        let intent: (any LiveActivityIntent)? = {
            guard let link = alarm.songLink else { return nil }
            return PlaySongIntent(alarmID: alarm.id.uuidString, songURL: link.url.absoluteString)
        }()
        return AlarmManager.AlarmConfiguration(
            countdownDuration: countdown,
            schedule: systemSchedule(for: alarm),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: intent,
            sound: sound
        )
    }

    private func systemSchedule(for alarm: Alarm) -> SystemAlarm.Schedule {
        switch alarm.schedule {
        case let .wallClock(hour, minute, days):
            let weekdays = days.map(\.localeWeekday)
            let repeats: SystemAlarm.Schedule.Relative.Recurrence = weekdays.isEmpty ? .never : .weekly(weekdays)
            return .relative(.init(time: .init(hour: hour, minute: minute), repeats: repeats))
        case let .oneShot(fireAt):
            return .fixed(fireAt)
        }
    }
}

@MainActor
final class NotificationAlarmEngine {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAccess() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { registerCategories() }
        return granted
    }

    func registerCategories() {
        let stop = UNNotificationAction(identifier: NotificationAction.stop, title: String(localized: "song.stop"), options: [])
        let snooze = UNNotificationAction(identifier: NotificationAction.snooze, title: String(localized: "ringing.snooze"), options: [])
        let play = UNNotificationAction(
            identifier: NotificationAction.playSong,
            title: String(localized: "song.play"),
            options: [.foreground]
        )
        let withSong = UNNotificationCategory(
            identifier: NotificationAction.categorySong,
            actions: [stop, snooze, play],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let plain = UNNotificationCategory(
            identifier: NotificationAction.categoryPlain,
            actions: [stop, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([withSong, plain])
    }

    func schedule(_ alarm: Alarm, customSounds: [CustomSound]) async {
        guard await requestAccess() else { return }
        await cancel(id: alarm.id)
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? String(localized: "alarm.defaultLabel") : alarm.label
        content.body = String(localized: "ringing.title")
        content.sound = UNNotificationSound(
            named: UNNotificationSoundName(SoundFiles.notificationName(for: alarm.soundID, customSounds: customSounds))
        )
        content.categoryIdentifier = alarm.songLink == nil ? NotificationAction.categoryPlain : NotificationAction.categorySong
        content.interruptionLevel = .timeSensitive
        if let song = alarm.songLink?.url.absoluteString {
            content.userInfo = ["song": song, "alarmID": alarm.id.uuidString]
        } else {
            content.userInfo = ["alarmID": alarm.id.uuidString]
        }
        switch alarm.schedule {
        case let .oneShot(fireAt):
            let interval = max(1, fireAt.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: "\(alarm.id.uuidString).once", content: content, trigger: trigger)
            try? await center.add(request)
        case let .wallClock(hour, minute, days):
            if days.isEmpty, let next = alarm.schedule.nextFireDate(from: .now, calendar: .current) {
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: next)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: "\(alarm.id.uuidString).once", content: content, trigger: trigger)
                try? await center.add(request)
            } else {
                for day in days {
                    var components = DateComponents()
                    components.hour = hour
                    components.minute = minute
                    components.weekday = day.gregorianIndex
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    let request = UNNotificationRequest(
                        identifier: "\(alarm.id.uuidString).\(day.rawValue)",
                        content: content,
                        trigger: trigger
                    )
                    try? await center.add(request)
                }
            }
        }
    }

    func cancel(id: UUID) async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(id.uuidString) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Notification-only snooze. AlarmKit alarms snooze through `AlarmManager.countdown`.
    func scheduleSnooze(_ alarm: Alarm, customSounds: [CustomSound]) async {
        guard await requestAccess() else { return }
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? String(localized: "alarm.defaultLabel") : alarm.label
        content.body = String(localized: "ringing.snooze")
        content.sound = UNNotificationSound(
            named: UNNotificationSoundName(SoundFiles.notificationName(for: alarm.soundID, customSounds: customSounds))
        )
        content.categoryIdentifier = alarm.songLink == nil ? NotificationAction.categoryPlain : NotificationAction.categorySong
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(max(60, alarm.snoozeMinutes * 60)),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: "\(alarm.id.uuidString).snooze", content: content, trigger: trigger)
        try? await center.add(request)
    }
}

enum NotificationAction {
    static let stop = "STOP"
    static let snooze = "SNOOZE"
    static let playSong = "PLAY_SONG"
    static let categoryPlain = "ALARM"
    static let categorySong = "ALARM_SONG"
}

@MainActor
final class AlarmCoordinator {
    private let alarmKit = AlarmKitEngine()
    private let notifications = NotificationAlarmEngine()
    private var lastSynced: [Alarm] = []
    private var alarmKitIDs = Set<UUID>()

    func accessState() -> AlarmAccessState {
        alarmKit.accessState()
    }

    func requestAccess() async -> AlarmAccessState {
        await alarmKit.requestAccess()
    }

    func notificationStatus() async -> UNAuthorizationStatus {
        await notifications.authorizationStatus()
    }

    func sync(alarms: [Alarm], customSounds: [CustomSound]) async {
        let plan = AlarmSyncPlan.make(previous: lastSynced, current: alarms)
        let byID = Dictionary(uniqueKeysWithValues: alarms.map { ($0.id, $0) })
        for id in plan.cancel {
            alarmKit.cancel(id: id)
            await notifications.cancel(id: id)
            alarmKitIDs.remove(id)
        }
        for id in plan.schedule {
            guard let alarm = byID[id] else { continue }
            await notifications.cancel(id: id)
            let scheduled = await alarmKit.schedule(alarm, customSounds: customSounds)
            if scheduled {
                alarmKitIDs.insert(id)
            } else {
                alarmKitIDs.remove(id)
                await notifications.schedule(alarm, customSounds: customSounds)
            }
        }
        lastSynced = alarms
    }

    func stop(id: UUID) async {
        alarmKit.stop(id: id)
        await notifications.cancel(id: id)
    }

    func snooze(_ alarm: Alarm, customSounds: [CustomSound]) async {
        if alarmKitIDs.contains(alarm.id) {
            alarmKit.snooze(id: alarm.id)
        } else {
            await notifications.scheduleSnooze(alarm, customSounds: customSounds)
        }
    }

    func observeAlerting(_ onAlerting: @escaping @MainActor (UUID) -> Void) async {
        await alarmKit.observe { ids in
            if let id = ids.first {
                onAlerting(id)
            }
        }
    }
}
