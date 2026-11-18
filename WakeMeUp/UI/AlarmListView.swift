import SwiftUI

struct AlarmListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.library.alarms.isEmpty && model.library.groups.isEmpty {
                    ContentUnavailableView(
                        "alarms.empty.title",
                        systemImage: "alarm",
                        description: Text("alarms.empty.message")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("alarms.title")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.addAlarm()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("add-alarm")
                    .accessibilityLabel("alarms.add")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.showGroups = true
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel("alarms.groups")
                }
            }
            .navigationDestination(isPresented: groupsPresented) {
                GroupListView()
            }
        }
        .accessibilityIdentifier("alarm-list")
    }

    private var groupsPresented: Binding<Bool> {
        Binding(get: { model.showGroups }, set: { model.showGroups = $0 })
    }

    private var list: some View {
        List {
            if !model.suppressPermissionBanner && model.authorization != .authorized {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.banner")
                        Button("settings.allow") {
                            Task { await model.allowAlarms() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .font(.subheadline)
                }
            }
            ForEach(model.library.groups) { group in
                section(groupID: group.id, title: group.name, symbol: group.symbol, group: group)
            }
            let ungrouped = model.library.alarms(in: nil)
            if !ungrouped.isEmpty {
                section(groupID: nil, title: String(localized: "alarms.otherGroup"), symbol: "alarm", group: nil, alarms: ungrouped)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let next = nextAlarmDescription {
                Text("\(String(localized: "alarms.next")) · \(next)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private func section(
        groupID: UUID?,
        title: String,
        symbol: String,
        group: AlarmGroup?,
        alarms explicit: [Alarm]? = nil
    ) -> some View {
        let alarms = explicit ?? model.library.alarms(in: groupID)
        Section {
            if alarms.isEmpty {
                Text("alarms.empty.group")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(alarms) { alarm in
                    Button {
                        model.edit(alarm)
                    } label: {
                        AlarmRow(alarm: alarm, enabled: alarm.isEnabled)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("alarm-row-\(alarm.id.uuidString)")
                    .swipeActions {
                        Button(role: .destructive) {
                            model.delete(alarmID: alarm.id)
                        } label: {
                            Label("alarm.delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        model.delete(alarmID: alarms[index].id)
                    }
                }
            }
        } header: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                if let group {
                    Toggle(isOn: Binding(
                        get: { group.isEnabled },
                        set: { _ in model.toggle(groupID: group.id) }
                    )) {
                        Text(title)
                    }
                    .labelsHidden()
                    .tint(.orange)
                    .accessibilityIdentifier("group-toggle-\(group.id.uuidString)")
                }
            }
        }
    }

    private var nextAlarmDescription: String? {
        let calendar = Calendar.current
        let now = Date()
        let next = model.library.alarms
            .filter(\.isEnabled)
            .compactMap { alarm -> (Alarm, Date)? in
                guard let date = alarm.schedule.nextFireDate(from: now, calendar: calendar) else { return nil }
                return (alarm, date)
            }
            .min { $0.1 < $1.1 }
        guard let next else { return nil }
        let parts = ClockFormat.parts(hour: next.0.schedule.hour, minute: next.0.schedule.minute, locale: .current, timeZone: calendar.timeZone)
        let label = next.0.label.isEmpty ? String(localized: "alarm.defaultLabel") : next.0.label
        return "\(parts.time) \(parts.period) · \(label)"
    }
}

struct AlarmRow: View {
    let alarm: Alarm
    let enabled: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(parts.time)
                        .font(.system(size: 52, weight: .thin))
                        .monospacedDigit()
                    if !parts.period.isEmpty {
                        Text(parts.period)
                            .font(.title3)
                    }
                }
                .foregroundStyle(enabled ? Color.primary : Color.secondary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let name = alarm.origin.senderName {
                    Text(String(format: String(localized: "sharing.remoteFrom"), name))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            Toggle(isOn: Binding(
                get: { enabled },
                set: { _ in model.toggle(alarmID: alarm.id) }
            )) {
                Text(alarm.label)
            }
            .labelsHidden()
            .tint(.orange)
            .disabled(groupDisabled)
        }
        .padding(.vertical, 4)
    }

    @Environment(AppModel.self) private var model

    private var groupDisabled: Bool {
        guard let groupID = alarm.groupID else { return false }
        return model.library.group(groupID)?.isEnabled == false
    }

    private var parts: ClockFormat.Parts {
        ClockFormat.parts(
            hour: alarm.schedule.hour,
            minute: alarm.schedule.minute,
            locale: .current,
            timeZone: .current
        )
    }

    private var subtitle: String {
        let label = alarm.label.isEmpty ? String(localized: "alarm.defaultLabel") : alarm.label
        return "\(label), \(repeatText)"
    }

    private var repeatText: String {
        switch alarm.schedule {
        case let .oneShot(fireAt):
            return fireAt.formatted(date: .abbreviated, time: .omitted)
        case let .wallClock(_, _, days):
            switch RepeatPatternClassifier.classify(days) {
            case .never: return String(localized: "repeat.never")
            case .everyDay: return String(localized: "repeat.everyDay")
            case .weekdays: return String(localized: "repeat.weekdays")
            case .weekends: return String(localized: "repeat.weekends")
            case .custom:
                return days.map { $0.veryShortSymbol(calendar: .current) }.joined(separator: " ")
            }
        }
    }
}
