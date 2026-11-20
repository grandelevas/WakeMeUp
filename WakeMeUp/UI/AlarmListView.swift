import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AlarmListView: View {
    @Environment(AppModel.self) private var model
    @State private var reorderMode = EditMode.inactive
    @State private var collapsedGroups: Set<UUID> = GroupExpansionStore.collapsedIDs()
    @State private var collapseBeforeSelection: Set<UUID>?
    @State private var collapseBeforeReorder: Set<UUID>?
    @State private var editingGroupID: UUID?
    @State private var showSettings = false
    @State private var selecting = false
    @State private var selectedAlarmIDs: Set<UUID> = []
    @State private var changingSelectionSound = false
    @State private var soundGroupID: UUID?
    @State private var draggingGroupID: UUID?

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
                    Menu {
                        Button(selecting ? "alarms.done" : "alarms.select", systemImage: "checkmark.circle") {
                            toggleSelecting()
                        }
                        .accessibilityIdentifier("alarms.select")
                        Button(isReordering ? "groups.reorder.done" : "groups.reorder", systemImage: "arrow.up.arrow.down") {
                            toggleReorder()
                        }
                        .accessibilityIdentifier("groups.reorder")
                        Button("groups.add", systemImage: "folder.badge.plus") {
                            model.showGroups = true
                        }
                        Button("settings.title", systemImage: "gearshape") {
                            showSettings = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("alarms.more")
                    .accessibilityLabel("groups.more")
                }
            }
            .navigationDestination(isPresented: groupsPresented) {
                GroupListView()
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(item: $editingGroupID) { id in
                GroupEditorView(groupID: id)
            }
            .sheet(isPresented: $changingSelectionSound) {
                SoundPickerSheet { soundID in
                    model.setSound(soundID, for: selectedAlarmIDs)
                    if let collapseBeforeSelection {
                        collapsedGroups = collapseBeforeSelection
                    }
                    collapseBeforeSelection = nil
                    selecting = false
                    selectedAlarmIDs.removeAll()
                }
            }
            .sheet(isPresented: groupSoundPresented) {
                if let soundGroupID {
                    SoundPickerSheet(title: "groups.changeSound") { soundID in
                        model.setSound(soundID, forGroup: soundGroupID)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if selecting {
                    Button {
                        changingSelectionSound = true
                    } label: {
                        Text(String(format: String(localized: "alarms.changeSoundCount"), selectedAlarmIDs.count))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedAlarmIDs.isEmpty)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(.bar)
                    .accessibilityIdentifier("change-sound")
                }
            }
        }
        .accessibilityIdentifier("alarm-list")
    }

    private var isReordering: Bool {
        reorderMode == .active
    }

    private func toggleSelecting() {
        if selecting {
            if let collapseBeforeSelection {
                collapsedGroups = collapseBeforeSelection
            }
            collapseBeforeSelection = nil
            selecting = false
            selectedAlarmIDs.removeAll()
        } else {
            if isReordering { toggleReorder() }
            collapseBeforeSelection = collapsedGroups
            collapsedGroups = []
            selecting = true
        }
    }

    private func toggleReorder() {
        if isReordering {
            reorderMode = .inactive
            if let collapseBeforeReorder {
                collapsedGroups = collapseBeforeReorder
            }
            collapseBeforeReorder = nil
        } else {
            if selecting { toggleSelecting() }
            collapseBeforeReorder = collapsedGroups
            collapsedGroups = Set(model.library.groups.map(\.id))
            reorderMode = .active
        }
    }

    private var groupSoundPresented: Binding<Bool> {
        Binding(get: { soundGroupID != nil }, set: { if !$0 { soundGroupID = nil } })
    }

    private var groupsPresented: Binding<Bool> {
        Binding(get: { model.showGroups }, set: { model.showGroups = $0 })
    }

    private var list: some View {
        List {
            if let next = nextAlarmDescription {
                Section("alarms.next") {
                    Text(next)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
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
                groupRow(group)
            }
            .onMove { source, destination in
                model.moveGroups(from: source, to: destination)
            }
            let ungrouped = model.library.alarms(in: nil)
            if !ungrouped.isEmpty {
                section(groupID: nil, title: String(localized: "alarms.otherGroup"), symbol: "alarm", group: nil, alarms: ungrouped)
            }
        }
        .environment(\.editMode, $reorderMode)
    }

    private func groupRow(_ group: AlarmGroup) -> some View {
        let alarms = model.library.alarms(in: group.id)
        let expanded = !isReordering && !collapsedGroups.contains(group.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                guard !isReordering else { return }
                setExpanded(!expanded, groupID: group.id)
            } label: {
                groupHeader(group, alarms: alarms)
            }
            .buttonStyle(.plain)
            if expanded {
                alarmRows(alarms, emptyKey: "alarms.empty.group")
                    .padding(.leading, 8)
            }
        }
        .accessibilityIdentifier("group-row-\(group.id.uuidString)")
        .accessibilityValue(Text(alarms.count, format: .number))
        .modifier(GroupDragModifier(
            enabled: !isReordering,
            groupID: group.id,
            groups: model.library.groups,
            draggingID: $draggingGroupID,
            move: { source, target in model.moveGroup(source, before: target) }
        ))
    }

    private func groupHeader(_ group: AlarmGroup, alarms: [Alarm]) -> some View {
        let mark = GroupSelection.mark(alarmIDs: alarms.map(\.id), selected: selectedAlarmIDs)
        return HStack(spacing: 8) {
            if selecting {
                Button {
                    selectedAlarmIDs = GroupSelection.toggle(
                        alarmIDs: alarms.map(\.id),
                        selected: selectedAlarmIDs
                    )
                } label: {
                    Image(systemName: selectionSymbol(mark))
                        .foregroundStyle(mark == .none ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.borderless)
                .disabled(alarms.isEmpty)
                .accessibilityLabel(group.name)
            }
            Label(group.name, systemImage: group.symbol)
            Text(alarms.count, format: .number)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Menu {
                Button("groups.changeSound", systemImage: "speaker.wave.2") {
                    soundGroupID = group.id
                }
                Button("groups.edit", systemImage: "info.circle") {
                    editingGroupID = group.id
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("groups.more")
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

    private func selectionSymbol(_ mark: GroupSelectionMark) -> String {
        switch mark {
        case .none: "circle"
        case .partial: "minus.circle.fill"
        case .all: "checkmark.circle.fill"
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
        if !selecting {
            GroupExpansionStore.setExpanded(expanded, id: groupID)
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
                    if selecting {
                        if selectedAlarmIDs.contains(alarm.id) {
                            selectedAlarmIDs.remove(alarm.id)
                        } else {
                            selectedAlarmIDs.insert(alarm.id)
                        }
                    } else {
                        model.edit(alarm)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if selecting {
                            Image(systemName: selectedAlarmIDs.contains(alarm.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedAlarmIDs.contains(alarm.id) ? Color.accentColor : Color.secondary)
                        }
                        AlarmRow(alarm: alarm, enabled: alarm.isEnabled, showsToggle: !selecting)
                    }
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
    var showsToggle: Bool = true

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
            if showsToggle {
                Toggle(isOn: Binding(
                    get: { enabled },
                    set: { _ in model.toggle(alarmID: alarm.id) }
                )) {
                    Text(alarm.label)
                }
                .labelsHidden()
                .disabled(groupDisabled)
            }
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

private struct GroupDragModifier: ViewModifier {
    let enabled: Bool
    let groupID: UUID
    let groups: [AlarmGroup]
    @Binding var draggingID: UUID?
    let move: (UUID, UUID) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag {
                    draggingID = groupID
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    return NSItemProvider(object: groupID.uuidString as NSString)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: GroupReorderDropDelegate(
                        targetID: groupID,
                        groups: groups,
                        draggingID: $draggingID,
                        move: move
                    )
                )
        } else {
            content
        }
    }
}

private struct GroupReorderDropDelegate: DropDelegate {
    let targetID: UUID
    let groups: [AlarmGroup]
    @Binding var draggingID: UUID?
    let move: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else { return }
        guard let from = groups.firstIndex(where: { $0.id == draggingID }),
              let to = groups.firstIndex(where: { $0.id == targetID }),
              from != to else { return }
        move(draggingID, targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }

    func dropSessionDidEnd(_ session: DropSession) {
        draggingID = nil
    }
}
