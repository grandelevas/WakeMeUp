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

    @MainActor
    static func contacts(in model: AppModel) -> [SharingContact] {
        ContactRoster.contacts(profileID: model.profile.id, grants: model.grants)
    }
}

struct WakitoContactEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("siri.contact"))
    static var defaultQuery = WakitoContactQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

struct WakitoContactQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [WakitoContactEntity.ID]) async throws -> [WakitoContactEntity] {
        let all = await allContacts()
        return all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WakitoContactEntity] {
        await allContacts()
    }

    func entities(matching string: String) async throws -> [WakitoContactEntity] {
        let all = await allContacts()
        guard let match = SpokenContactMatch.match(name: string, contacts: all.map {
            SharingContact(id: $0.id, name: $0.name, memberID: nil, wakeGrantID: nil, hostedGrantID: nil, isPending: false)
        }) else {
            return all.filter { $0.name.localizedCaseInsensitiveContains(string) }
        }
        return all.filter { $0.id == match.id }
    }

    private func allContacts() async -> [WakitoContactEntity] {
        guard let model = await WakitoIntentRuntime.model() else { return [] }
        let contacts = await MainActor.run { WakitoIntentRuntime.contacts(in: model) }
        return contacts.map { WakitoContactEntity(id: $0.id, name: $0.name) }
    }
}

struct SetWakitoAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Set an alarm"
    static var description = IntentDescription("Sets a Wakito alarm for a time.")
    static var openAppWhenRun = true

    @Parameter(title: "Time")
    var time: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Set an alarm for \(\.$time)")
    }

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
        if let failure = await model.startNap() {
            return .result(dialog: IntentDialog(stringLiteral: failure))
        }
        let minutes = await model.napMinutes
        let text = String(format: String(localized: "siri.napStarted"), minutes)
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct WakeWakitoContactIntent: AppIntent {
    static var title: LocalizedStringResource = "Wake a contact"
    static var description = IntentDescription("Sends Wake now to someone in Wakito.")
    static var openAppWhenRun = true

    @Parameter(title: "Contact")
    var contact: WakitoContactEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Wake \(\.$contact)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = await WakitoIntentRuntime.model() else {
            return .result(dialog: IntentDialog(LocalizedStringResource("siri.unavailable")))
        }
        let woken = await model.wakeContact(named: contact.name)
        if woken {
            return .result(dialog: IntentDialog(stringLiteral: String(format: String(localized: "siri.woke"), contact.name)))
        }
        return .result(dialog: IntentDialog(stringLiteral: String(format: String(localized: "siri.wakeMissing"), contact.name)))
    }
}

struct WakitoShortcuts: AppShortcutsProvider {
    /// Shortcut phrases can only insert an app name, an AppEnum, or an AppEntity.
    /// The clock time stays a normal parameter, so Siri asks for it and Shortcuts can fill it in.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetWakitoAlarmIntent(),
            phrases: [
                "Set an alarm in \(.applicationName)",
                "Ustaw alarm w \(.applicationName)"
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
                "Wake \(\.$contact) in \(.applicationName)",
                "Obudź \(\.$contact) w \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("siri.wake.short"),
            systemImageName: "sun.max"
        )
    }
}
