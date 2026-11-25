import AppIntents
import Foundation

enum WakitoIntentRuntime {
    static func model() async -> AppModel? {
        for _ in 0..<30 {
            if let model = await MainActor.run(body: { AppRuntime.model }) {
                return model
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return await MainActor.run(body: { AppRuntime.model })
    }
}

struct SetWakitoAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Set an alarm"
    static var description = IntentDescription("Sets a Wakito alarm for a time.")
    static var openAppWhenRun = true

    @Parameter(title: "Time")
    var time: Date

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = await WakitoIntentRuntime.model() else {
            return .result(dialog: IntentDialog(LocalizedStringResource("siri.unavailable")))
        }
        await model.addSpokenAlarm(at: time)
        let parts = SpokenAlarm.hourAndMinute(from: time)
        let clock = ClockFormat.parts(hour: parts.hour, minute: parts.minute, locale: .current, timeZone: .current)
        let shown = clock.period.isEmpty ? clock.time : "\(clock.time) \(clock.period)"
        return .result(dialog: IntentDialog(stringLiteral: String(format: String(localized: "siri.alarmSet"), shown)))
    }
}

struct StartWakitoNapIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a nap"
    static var description = IntentDescription("Starts a Wakito nap.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = await WakitoIntentRuntime.model() else {
            return .result(dialog: IntentDialog(LocalizedStringResource("siri.unavailable")))
        }
        await model.startNap()
        let text = String(format: String(localized: "siri.napStarted"), model.napMinutes)
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct WakeWakitoContactIntent: AppIntent {
    static var title: LocalizedStringResource = "Wake a contact"
    static var description = IntentDescription("Sends Wake now to someone in Wakito.")
    static var openAppWhenRun = true

    @Parameter(title: "Name")
    var name: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = await WakitoIntentRuntime.model() else {
            return .result(dialog: IntentDialog(LocalizedStringResource("siri.unavailable")))
        }
        let woken = await model.wakeContact(named: name)
        if woken {
            return .result(dialog: IntentDialog(stringLiteral: String(format: String(localized: "siri.woke"), name)))
        }
        return .result(dialog: IntentDialog(stringLiteral: String(format: String(localized: "siri.wakeMissing"), name)))
    }
}

struct WakitoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetWakitoAlarmIntent(),
            phrases: [
                "Set an alarm in \(.applicationName) for \(\.$time)",
                "Ustaw alarm w \(.applicationName) na \(\.$time)"
            ],
            shortTitle: LocalizedStringResource("siri.setAlarm.short"),
            systemImageName: "alarm"
        )
        AppShortcut(
            intent: StartWakitoNapIntent(),
            phrases: [
                "Start a nap in \(.applicationName)",
                "Włącz drzemkę w \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("siri.nap.short"),
            systemImageName: "moon.zzz"
        )
        AppShortcut(
            intent: WakeWakitoContactIntent(),
            phrases: [
                "Wake \(\.$name) in \(.applicationName)",
                "Obudź \(\.$name) w \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("siri.wake.short"),
            systemImageName: "sun.max"
        )
    }
}
