import SwiftUI
import UIKit

struct AlarmListView: View {
    @Environment(AppModel.self) private var model
    @State private var collapsedGroups: Set<UUID> = GroupExpansionStore.collapsedIDs()
    @State private var editingGroupID: UUID?

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
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("settings.title")
                }
            }
            .navigationDestination(isPresented: groupsPresented) {
                GroupListView()
            }
            .navigationDestination(item: $editingGroupID) { id in
                GroupEditorView(groupID: id)
            }
        }
        .accessibilityIdentifier("alarm-list")
    }

    private var groupsPresented: Binding<Bool> {
        Binding(get: { model.showGroups }, set: { model.showGroups = $0 })
    }

    private var list: some View {
        List {
            if !model.suppressPermissionBanner && model.authorization == .denied {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.systemAlarm.denied")
                        Text("settings.systemAlarm.fallback")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("settings.open") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else if !model.suppressPermissionBanner && model.authorization != .authorized {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.banner")
                        Button("settings.allow") {
                            Task { await model.allowAlarms() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .font(.subheadline)
                }
            }
            if let failure = model.scheduleFailure, !model.suppressPermissionBanner {
                Section {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(model.library.groups) { group in
                groupSection(group)
            }
            let ungrouped = model.library.alarms(in: nil)
            if !ungrouped.isEmpty {
                section(groupID: nil, title: String(localized: "alarms.otherGroup"), symbol: "alarm", group: nil, alarms: ungrouped)
            }
            if let next = nextAlarmDescription {
                Section("alarms.next") {
                    Text(next)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func groupSection(_ group: AlarmGroup) -> some View {
        let alarms = model.library.alarms(in: group.id)
        Section {
            DisclosureGroup(isExpanded: expandedBinding(group.id)) {
                alarmRows(alarms, emptyKey: "alarms.empty.group")
            } label: {
                HStack(spacing: 8) {
                    Label(group.name, systemImage: group.symbol)
                    Text(alarms.count, format: .number)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button {
                        editingGroupID = group.id
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("groups.edit")
                    Toggle(isOn: Binding(
                        get: { group.isEnabled },
                        set: { _ in model.toggle(groupID: group.id) }
                    )) {
                        Text(group.name)
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("group-toggle-\(group.id.uuidString)")
                }
            }
            .accessibilityValue(Text(alarms.count, format: .number))
        }
    }

    private func expandedBinding(_ groupID: UUID) -> Binding<Bool> {
        Binding(
            get: { !collapsedGroups.contains(groupID) },
            set: { setExpanded($0, groupID: groupID) }
        )
    }

    private func setExpanded(_ expanded: Bool, groupID: UUID) {
        if expanded {
            collapsedGroups.remove(groupID)
        } else {
            collapsedGroups.insert(groupID)
        }
        GroupExpansionStore.setExpanded(expanded, id: groupID)
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
            alarmRows(alarms, emptyKey: "alarms.empty.group")
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
                    .accessibilityIdentifier("group-toggle-\(group.id.uuidString)")
                }
            }
        }
    }

    @ViewBuilder
    private func alarmRows(_ alarms: [Alarm], emptyKey: LocalizedStringKey) -> some View {
        if alarms.isEmpty {
            Text(emptyKey)
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
    @Environment(\.appAccent) private var appAccent
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
                        .foregroundStyle(appAccent)
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
                return Weekday.sorted(days, calendar: .current)
                    .map { $0.veryShortSymbol(calendar: .current) }
                    .joined(separator: " ")
            }
        }
    }
}
