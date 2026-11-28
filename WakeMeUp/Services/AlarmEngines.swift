import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import os
import SwiftUI
import UserNotifications

/// Our model is also named `Alarm`, so AlarmKit's type has to be qualified.
private typealias SystemAlarm = AlarmKit.Alarm

private let alarmLog = Logger(subsystem: "com.grandelevas.wakemeup", category: "AlarmKit")

struct AlarmKitAttempt: Equatable {
    var permission: AlarmAccessState
    /// Set when the named file could not be scheduled. Nil means that attempt succeeded.
    var namedSoundError: String?
    /// Set when the system alarm sound also failed. Nil means it was not needed or it succeeded.
    var defaultSoundError: String?
}

@MainActor
final class AlarmKitEngine {
    private let manager = AlarmManager.shared

    func accessState() -> AlarmAccessState {
        map(manager.authorizationState)
    }

    func requestAccess() async -> AlarmAccessState {
        if Bundle.main.object(forInfoDictionaryKey: "NSAlarmKitUsageDescription") == nil {
            alarmLog.error("NSAlarmKitUsageDescription is missing from the built app")
        }
        switch manager.authorizationState {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            do {
                let state = try await manager.requestAuthorization()
                let mapped = map(state)
                alarmLog.info("AlarmKit authorization is \(String(describing: mapped), privacy: .public)")
                return mapped
            } catch {
                alarmLog.error("AlarmKit authorization failed: \(error.localizedDescription, privacy: .public)")
                return map(manager.authorizationState)
            }
        @unknown default:
            return .unknown
        }
    }

    /// Schedules a full-screen AlarmKit alarm. A missing custom sound retries with the system sound.
    /// This does not schedule a notification.
    func schedule(_ alarm: Alarm, customSounds: [CustomSound]) async -> AlarmKitAttempt {
        let permission = await requestAccess()
        guard permission == .authorized else {
            alarmLog.error("AlarmKit schedule skipped; authorization is \(String(describing: permission), privacy: .public)")
            return AlarmKitAttempt(permission: permission, namedSoundError: nil, defaultSoundError: nil)
        }
        cancel(id: alarm.id)
        let filename = SoundFiles.alarmKitName(for: alarm.soundID, customSounds: customSounds)
        let choice = AlarmSoundResolver.choose(
            preferredFilename: filename,
            present: presentSoundNames(preferred: filename)
        )
        switch choice {
        case .named(let name):
            do {
                try await submit(alarm, sound: .named(name))
                alarmLog.info("Scheduled AlarmKit alarm \(alarm.id.uuidString, privacy: .public) with \(name, privacy: .public)")
                return AlarmKitAttempt(permission: .authorized, namedSoundError: nil, defaultSoundError: nil)
            } catch {
                let namedError = error.localizedDescription
                alarmLog.error("AlarmKit sound \(name, privacy: .public) failed: \(namedError, privacy: .public)")
                return await scheduleSystemSound(alarm, namedError: namedError)
            }
        case .systemDefault:
            let namedError = "No alarm file named \(filename) in the app bundle or Library/Sounds."
            alarmLog.error("\(namedError, privacy: .public)")
            return await scheduleSystemSound(alarm, namedError: namedError)
        }
    }

    private func scheduleSystemSound(
        _ alarm: Alarm,
        namedError: String
    ) async -> AlarmKitAttempt {
        do {
            try await submit(alarm, sound: .default)
            alarmLog.info("Scheduled AlarmKit alarm \(alarm.id.uuidString, privacy: .public) with the system sound")
            return AlarmKitAttempt(permission: .authorized, namedSoundError: namedError, defaultSoundError: nil)
        } catch {
            let message = error.localizedDescription
            alarmLog.error("AlarmKit system sound failed: \(message, privacy: .public)")
            return AlarmKitAttempt(permission: .authorized, namedSoundError: namedError, defaultSoundError: message)
        }
    }

    private func submit(
        _ alarm: Alarm,
        sound: AlertConfiguration.AlertSound
    ) async throws {
        let configuration = makeConfiguration(for: alarm, sound: sound)
        _ = try await manager.schedule(id: alarm.id, configuration: configuration)
    }

    /// Names AlarmKit can load: bundle root, or a file already in Library/Sounds.
    private func presentSoundNames(preferred: String) -> Set<String> {
        var names = Set<String>()
        let base = (preferred as NSString).deletingPathExtension
        let ext = (preferred as NSString).pathExtension
        if !ext.isEmpty, Bundle.main.url(forResource: base, withExtension: ext) != nil {
            names.insert(preferred)
        }
        if let directory = try? SoundFiles.librarySoundsDirectory(),
           FileManager.default.fileExists(atPath: directory.appendingPathComponent(preferred).path) {
            names.insert(preferred)
        }
        return names
    }

    private func map(_ state: AlarmManager.AuthorizationState) -> AlarmAccessState {
        switch state {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        @unknown default: .unknown
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

    func alertingIDs() -> Set<UUID>? {
        guard let alarms = try? manager.alarms else { return nil }
        return Set(alarms.compactMap { $0.state == .alerting ? $0.id : nil })
    }

    /// Countdown or paused means the alarm was snoozed, not stopped.
    func countingDownIDs() -> Set<UUID>? {
        guard let alarms = try? manager.alarms else { return nil }
        return Self.countingDownIDs(in: alarms)
    }

    /// AlarmKit publishes on an arbitrary executor. The caller applies the sets on the main actor.
    func observe(_ onUpdate: @escaping @MainActor (_ alerting: Set<UUID>, _ countingDown: Set<UUID>) -> Void) async {
        let updates = manager.alarmUpdates
        for await alarms in updates {
            let alerting = Set(alarms.compactMap { $0.state == .alerting ? $0.id : nil })
            let countingDown = Self.countingDownIDs(in: alarms)
            await MainActor.run {
                onUpdate(alerting, countingDown)
            }
        }
    }

    private static func countingDownIDs(in alarms: some Sequence<SystemAlarm>) -> Set<UUID> {
        Set(alarms.compactMap { alarm in
            switch alarm.state {
            case .countdown, .paused: alarm.id
            default: nil
            }
        })
    }

    private func makeConfiguration(
        for alarm: Alarm,
        sound: AlertConfiguration.AlertSound
    ) -> AlarmManager.AlarmConfiguration<WakeMeUpAlarmMetadata> {
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
        let countdown: SystemAlarm.CountdownDuration?
        if let lead = alarm.countdownLead, lead > 0 {
            let countdownUI = AlarmPresentation.Countdown(title: localizedTitle, pauseButton: nil)
            presentation = AlarmPresentation(alert: alert, countdown: countdownUI)
            countdown = SystemAlarm.CountdownDuration(preAlert: lead, postAlert: nil)
        } else if alarm.snoozeEnabled {
            let countdownUI = AlarmPresentation.Countdown(title: localizedTitle, pauseButton: nil)
            presentation = AlarmPresentation(alert: alert, countdown: countdownUI)
            countdown = SystemAlarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(alarm.snoozeMinutes * 60))
        } else {
            presentation = AlarmPresentation(alert: alert)
            countdown = nil
        }
        let attributes = AlarmAttributes<WakeMeUpAlarmMetadata>(
            presentation: presentation,
            metadata: WakeMeUpAlarmMetadata(
                alarmID: alarm.id.uuidString,
                label: title,
                songURL: alarm.songLink?.url.absoluteString
            ),
            tintColor: AppearanceSettings.storedAccent.color
        )
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

    /// Drops every quiet banner this app scheduled, including alarms that were deleted.
    func cancelAllAlarmNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.filter {
            $0.content.categoryIdentifier == NotificationAction.categoryPlain
                || $0.content.categoryIdentifier == NotificationAction.categorySong
        }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
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
    private var notificationIDs = Set<UUID>()
    private var standaloneIDs = Set<UUID>()

    func accessState() -> AlarmAccessState {
        alarmKit.accessState()
    }

    func requestAccess() async -> AlarmAccessState {
        await alarmKit.requestAccess()
    }

    func notificationStatus() async -> UNAuthorizationStatus {
        await notifications.authorizationStatus()
    }

    /// Re-schedules enabled alarms through AlarmKit and removes pending notification banners.
    /// Returns the first AlarmKit failure that was not replaced by the system alarm sound.
    func scheduleStandalone(_ alarm: Alarm, customSounds: [CustomSound]) async -> String? {
        let attempt = await alarmKit.schedule(alarm, customSounds: customSounds)
        let delivery = AlarmDeliveryPolicy.decide(
            permission: attempt.permission,
            alarmKitAvailable: true,
            namedSoundError: attempt.namedSoundError,
            defaultSoundError: attempt.defaultSoundError
        )
        switch delivery {
        case .alarmKit, .alarmKitSystemSound:
            standaloneIDs.insert(alarm.id)
            return nil
        case .notificationFallback:
            await notifications.schedule(alarm, customSounds: customSounds)
            standaloneIDs.insert(alarm.id)
            return nil
        case .blocked(let message):
            alarmLog.error("AlarmKit nap blocked: \(message, privacy: .public)")
            return message
        }
    }

    func cancelStandalone(id: UUID) async {
        alarmKit.cancel(id: id)
        await notifications.cancel(id: id)
        standaloneIDs.remove(id)
    }

    func sync(alarms: [Alarm], customSounds: [CustomSound]) async -> String? {
        let plan = AlarmSyncPlan.make(previous: lastSynced, current: alarms)
        let byID = Dictionary(uniqueKeysWithValues: alarms.map { ($0.id, $0) })
        await notifications.cancelAllAlarmNotifications()
        for id in plan.cancel {
            alarmKit.cancel(id: id)
            alarmKitIDs.remove(id)
            notificationIDs.remove(id)
        }
        var failure: String?
        for id in plan.schedule {
            guard let alarm = byID[id] else { continue }
            let attempt = await alarmKit.schedule(alarm, customSounds: customSounds)
            let delivery = AlarmDeliveryPolicy.decide(
                permission: attempt.permission,
                alarmKitAvailable: true,
                namedSoundError: attempt.namedSoundError,
                defaultSoundError: attempt.defaultSoundError
            )
            switch delivery {
            case .alarmKit, .alarmKitSystemSound:
                alarmKitIDs.insert(id)
                notificationIDs.remove(id)
            case .notificationFallback:
                alarmKitIDs.remove(id)
                notificationIDs.insert(id)
                await notifications.schedule(alarm, customSounds: customSounds)
            case .blocked(let message):
                alarmKitIDs.remove(id)
                notificationIDs.remove(id)
                alarmLog.error("AlarmKit schedule blocked: \(message, privacy: .public)")
                if failure == nil { failure = message }
            }
        }
        lastSynced = alarms
        return failure
    }

    func stop(id: UUID) async {
        alarmKit.stop(id: id)
        await notifications.cancel(id: id)
    }

    func snooze(_ alarm: Alarm, customSounds: [CustomSound]) async {
        if alarmKitIDs.contains(alarm.id) {
            alarmKit.snooze(id: alarm.id)
        } else if notificationIDs.contains(alarm.id) {
            await notifications.scheduleSnooze(alarm, customSounds: customSounds)
        }
    }

    func alertingIDs() -> Set<UUID>? {
        alarmKit.alertingIDs()
    }

    func countingDownIDs() -> Set<UUID>? {
        alarmKit.countingDownIDs()
    }

    func observeAlerting(_ onChange: @escaping @MainActor (Set<UUID>, Set<UUID>) -> Void) async {
        await alarmKit.observe { alerting, countingDown in
            onChange(alerting, countingDown)
        }
    }
}
