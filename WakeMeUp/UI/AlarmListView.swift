import SwiftUI
import UIKit

private struct AlarmSectionCollapse {
    var groups: Set<UUID>
    var fromOthers: Bool
    var toOthers: Bool
    var other: Bool
}

struct AlarmListView: View {
    @Environment(AppModel.self) private var model
    @State private var reorderMode = EditMode.inactive
    @State private var collapsedGroups: Set<UUID> = GroupExpansionStore.collapsedIDs()
    @State private var fromOthersExpanded = SectionExpansionStore.isExpanded(SectionExpansionStore.fromOthers)
    @State private var toOthersExpanded = SectionExpansionStore.isExpanded(SectionExpansionStore.toOthers)
    @State private var collapseBeforeSelection: AlarmSectionCollapse?
    @State private var otherExpanded = true
    @State private var collapseBeforeReorder: Set<UUID>?
    @State private var editingGroupID: UUID?
    @State private var showSettings = false
    @State private var selecting = false
    @State private var selectedAlarmIDs: Set<UUID> = []
    @State private var bulkEditing = false
    @State private var appliedBulkEdit = false
    @State private var renamingAlarm: Alarm?
    @State private var alarmRenameText = ""
    @State private var soundGroupID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if model.library.alarms.isEmpty && model.library.groups.isEmpty && model.snapshot.sentAlarms.isEmpty {
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
                    HStack(spacing: 16) {
                        Button(isReordering ? "alarms.done" : "alarms.edit") {
                            toggleReorder()
                        }
                        .accessibilityIdentifier("alarms.edit")
                        Button {
                            model.showGroups = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .accessibilityIdentifier("groups.add")
                        .accessibilityLabel("groups.add")
                        Button {
                            toggleSelecting()
                        } label: {
                            Image(systemName: selecting ? "checkmark.circle.fill" : "checkmark.circle")
                        }
                        .accessibilityIdentifier("alarms.select")
                        .accessibilityLabel(Text(LocalizedStringKey(selecting ? "alarms.done" : "alarms.select")))
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityIdentifier("open-settings")
                        .accessibilityLabel("settings.title")
                        Button {
                            model.addAlarm()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityIdentifier("add-alarm")
                        .accessibilityLabel("alarms.add")
                    }
                    .buttonStyle(.borderless)
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
            .sheet(isPresented: $bulkEditing, onDismiss: finishBulkEdit) {
                if let seed = selectedSeed {
                    BulkAlarmEditor(seed: seed) { patch in
                        model.applyBulk(patch, to: selectedAlarmIDs)
                        appliedBulkEdit = true
                    }
                }
            }
            .alert("alarm.rename", isPresented: alarmRenamePresented) {
                TextField("alarm.label", text: $alarmRenameText)
                Button("alarm.save") {
                    if let renamingAlarm {
                        model.renameAlarm(renamingAlarm.id, to: alarmRenameText)
                    }
                    self.renamingAlarm = nil
                }
                Button("alarm.cancel", role: .cancel) { renamingAlarm = nil }
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
                        bulkEditing = true
                    } label: {
                        Text(String(format: String(localized: "alarms.changeSelectionCount"), selectedAlarmIDs.count))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedAlarmIDs.isEmpty)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(.bar)
                    .accessibilityIdentifier("change-alarms")
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
            restoreSectionsAfterSelection()
            selecting = false
            selectedAlarmIDs.removeAll()
        } else {
            if isReordering { toggleReorder() }
            collapseSectionsForSelection()
            selecting = true
        }
    }

    private func collapseSectionsForSelection() {
        collapseBeforeSelection = AlarmSectionCollapse(
            groups: collapsedGroups,
            fromOthers: fromOthersExpanded,
            toOthers: toOthersExpanded,
            other: otherExpanded
        )
        collapsedGroups = Set(model.library.groups.map(\.id))
        fromOthersExpanded = false
        toOthersExpanded = false
        otherExpanded = false
    }

    private func restoreSectionsAfterSelection() {
        if let collapseBeforeSelection {
            collapsedGroups = collapseBeforeSelection.groups
            fromOthersExpanded = collapseBeforeSelection.fromOthers
            toOthersExpanded = collapseBeforeSelection.toOthers
            otherExpanded = collapseBeforeSelection.other
        }
        self.collapseBeforeSelection = nil
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

    private func finishBulkEdit() {
        guard appliedBulkEdit else { return }
        appliedBulkEdit = false
        restoreSectionsAfterSelection()
        selecting = false
        selectedAlarmIDs.removeAll()
    }

    private var selectedSeed: Alarm? {
        model.library.alarms.first { selectedAlarmIDs.contains($0.id) }
    }

    private var alarmRenamePresented: Binding<Bool> {
        Binding(get: { renamingAlarm != nil }, set: { if !$0 { renamingAlarm = nil } })
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
            .onMove(perform: isReordering ? { source, destination in
                model.moveGroups(from: source, to: destination)
            } : nil)
            let ungrouped = model.library.ownAlarms(in: nil)
            if !ungrouped.isEmpty {
                Section {
                    if !selecting || otherExpanded {
                        alarmRows(ungrouped, emptyKey: "alarms.empty.group")
                    }
                } header: {
                    if selecting {
                        collapsibleHeader("alarms.otherGroup", expanded: otherExpanded) {
                            otherExpanded.toggle()
                        }
                    } else {
                        Label(String(localized: "alarms.otherGroup"), systemImage: "alarm")
                    }
                }
            }
            let received = model.library.receivedFromOthers
            if !received.isEmpty {
                Section {
                    if fromOthersExpanded {
                        alarmRows(received, emptyKey: "alarms.empty.group")
                    }
                } header: {
                    collapsibleHeader("alarms.fromOthers", expanded: fromOthersExpanded) {
                        fromOthersExpanded.toggle()
                        if !selecting {
                            SectionExpansionStore.setExpanded(fromOthersExpanded, id: SectionExpansionStore.fromOthers)
                        }
                    }
                }
            }
            if !model.snapshot.sentAlarms.isEmpty {
                Section {
                    if toOthersExpanded {
                        ForEach(FriendGroupRoster.sections(from: model.snapshot.sentAlarms)) { section in
                            if let title = section.title, !title.isEmpty {
                                Text(title)
                                    .font(.headline)
                            }
                            ForEach(section.rows) { row in
                                if let sent = model.snapshot.sentAlarms.first(where: { $0.commandID == row.commandID }) {
                                    SentAlarmRow(sent: sent)
                                        .swipeActions {
                                            Button(role: .destructive) {
                                                Task { await model.deleteSentAlarm(commandID: sent.commandID) }
                                            } label: {
                                                Label("alarm.delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                } header: {
                    collapsibleHeader("alarms.toOthers", expanded: toOthersExpanded) {
                        toOthersExpanded.toggle()
                        if !selecting {
                            SectionExpansionStore.setExpanded(toOthersExpanded, id: SectionExpansionStore.toOthers)
                        }
                    }
                }
            }
        }
        .environment(\.editMode, $reorderMode)
    }

    private func collapsibleHeader(
        _ title: LocalizedStringKey,
        expanded: Bool,
        toggle: @escaping () -> Void
    ) -> some View {
        Button(action: toggle) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func groupRow(_ group: AlarmGroup) -> some View {
        let alarms = model.library.ownAlarms(in: group.id)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("group-row-\(group.id.uuidString)")
        .accessibilityValue(Text(alarms.count, format: .number))
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
                        AlarmRow(
                            alarm: alarm,
                            enabled: alarm.isEnabled,
                            showsToggle: !selecting,
                            collaborationPaused: CollaborationPause.suppressesRinging(
                                alarm,
                                profileID: model.profile.id,
                                grants: model.grants
                            )
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("alarm-row-\(alarm.id.uuidString)")
                .contextMenu {
                    if !selecting, !alarm.origin.isFromSomeoneElse {
                        Button("alarm.rename", systemImage: "pencil") {
                            alarmRenameText = alarm.label
                            renamingAlarm = alarm
                        }
                        Button("alarm.delete", systemImage: "trash", role: .destructive) {
                            model.delete(alarmID: alarm.id)
                        }
                    }
                }
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
            .filter { !CollaborationPause.suppressesRinging($0, profileID: model.profile.id, grants: model.grants) }
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
    @State private var preview = SoundPreviewPlayer()
    @State private var showingVideo = false
    let alarm: Alarm
    let enabled: Bool
    var showsToggle: Bool = true
    var collaborationPaused: Bool = false

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
                if let note = alarm.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let name = alarm.origin.senderName {
                    Text(String(format: String(localized: "alarms.fromSender"), name))
                        .font(.caption)
                        .foregroundStyle(appAccent)
                }
                if collaborationPaused {
                    Text("sharing.paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let videoID = alarm.videoFileID, VideoFiles.url(id: videoID) != nil {
                Button {
                    showingVideo = true
                } label: {
                    Image(systemName: "video.circle")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("video.play")
                .sheet(isPresented: $showingVideo) {
                    if let url = VideoFiles.url(id: videoID) {
                        VideoMessagePlayer(url: url)
                            .ignoresSafeArea()
                    }
                }
            }
            if alarm.soundID.hasPrefix("voice-"),
               let url = SoundFiles.previewURL(for: alarm.soundID, customSounds: model.customSounds) {
                Button {
                    if preview.isPlaying(alarm.soundID) {
                        preview.stop()
                    } else {
                        preview.play(id: alarm.soundID, url: url, cap: VoiceClipPolicy.maxSeconds)
                    }
                } label: {
                    Image(systemName: preview.isPlaying(alarm.soundID) ? "stop.circle" : "play.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("sound.voice.play")
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
                .accessibilityIdentifier("alarm-toggle-\(alarm.id.uuidString)")
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

private struct SentAlarmRow: View {
    @Environment(\.appAccent) private var appAccent
    @Environment(AppModel.self) private var model
    @State private var preview = SoundPreviewPlayer()
    let sent: SentAlarm

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
                Text(sent.alarm.label.isEmpty ? String(localized: "alarm.defaultLabel") : sent.alarm.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(String(format: String(localized: "alarms.forRecipient"), sent.recipientName))
                    .font(.caption)
                    .foregroundStyle(appAccent)
                if let status = sent.wakeStatus {
                    Text(wakeStatusText(status, at: sent.wakeStatusAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("sent-status-\(sent.commandID.uuidString)")
                }
            }
            if sent.alarm.soundID.hasPrefix("voice-"),
               let url = SoundFiles.previewURL(for: sent.alarm.soundID, customSounds: model.customSounds) {
                Button {
                    if preview.isPlaying(sent.alarm.soundID) {
                        preview.stop()
                    } else {
                        preview.play(id: sent.alarm.soundID, url: url, cap: VoiceClipPolicy.maxSeconds)
                    }
                } label: {
                    Image(systemName: preview.isPlaying(sent.alarm.soundID) ? "stop.circle" : "play.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("sound.voice.play")
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("sent-alarm-\(sent.commandID.uuidString)")
    }

    private func wakeStatusText(_ status: WakeStatusKind, at date: Date?) -> String {
        switch status {
        case .up:
            let moment = date ?? .now
            let parts = ClockFormat.parts(
                hour: Calendar.current.component(.hour, from: moment),
                minute: Calendar.current.component(.minute, from: moment),
                locale: .current,
                timeZone: .current
            )
            let time = parts.period.isEmpty ? parts.time : "\(parts.time) \(parts.period)"
            return String(format: String(localized: "sharing.wake.rowUp"), time)
        case .asleep:
            return String(localized: "sharing.wake.rowAsleep")
        }
    }

    private var parts: ClockFormat.Parts {
        ClockFormat.parts(
            hour: sent.alarm.schedule.hour,
            minute: sent.alarm.schedule.minute,
            locale: .current,
            timeZone: .current
        )
    }
}
