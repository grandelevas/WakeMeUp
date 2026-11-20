import SwiftUI

struct GroupListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccent) private var appAccent
    @State private var name = ""
    @State private var symbol = "folder"
    @State private var pendingDelete: AlarmGroup?

    var body: some View {
        List {
            Section("groups.add") {
                TextField("groups.name", text: $name)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(GroupSymbols.all, id: \.self) { item in
                            Button {
                                symbol = item
                            } label: {
                                Image(systemName: item)
                                    .frame(width: 40, height: 40)
                                    .background(symbol == item ? appAccent.opacity(0.25) : Color.clear, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item)
                        }
                    }
                }
                Button("groups.create") {
                    model.createGroup(name: name, symbol: symbol)
                    name = ""
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if model.library.groups.isEmpty {
                ContentUnavailableView("groups.empty", systemImage: "folder", description: Text("groups.add"))
            } else {
                ForEach(model.library.groups) { group in
                    HStack {
                        NavigationLink {
                            GroupEditorView(groupID: group.id)
                        } label: {
                            Label(group.name, systemImage: group.symbol)
                        }
                        Toggle(isOn: Binding(
                            get: { group.isEnabled },
                            set: { _ in model.toggle(groupID: group.id) }
                        )) {
                            Text(group.name)
                        }
                        .labelsHidden()
                    }
                    .swipeActions {
                        Button("groups.delete", role: .destructive) {
                            pendingDelete = group
                        }
                    }
                }
            }
        }
        .navigationTitle("groups.title")
        .accessibilityIdentifier("group-list")
        .confirmationDialog("groups.delete", isPresented: deletePresented, titleVisibility: .visible) {
            Button("groups.delete", role: .destructive) {
                if let pendingDelete {
                    model.deleteGroup(id: pendingDelete.id)
                }
                pendingDelete = nil
            }
            Button("alarm.cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("groups.delete.confirm")
        }
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }
}

private enum GroupSymbols {
    static let all = ["folder", "briefcase", "sun.max", "moon.stars", "figure.run", "book", "heart", "alarm"]
}

struct GroupEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccent) private var appAccent
    @Environment(\.dismiss) private var dismiss
    let groupID: UUID
    @State private var name = ""
    @State private var symbol = "folder"
    @State private var confirmDelete = false
    @State private var changingGroupSound = false

    var body: some View {
        Form {
            Section("groups.name") {
                TextField("groups.name", text: $name)
            }
            Section("groups.symbol") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(GroupSymbols.all, id: \.self) { item in
                            Button {
                                symbol = item
                            } label: {
                                Image(systemName: item)
                                    .frame(width: 40, height: 40)
                                    .background(symbol == item ? appAccent.opacity(0.25) : Color.clear, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item)
                        }
                    }
                }
            }
            if model.library.group(groupID) != nil {
                Section {
                    Toggle("groups.enabled", isOn: Binding(
                        get: { model.library.group(groupID)?.isEnabled ?? false },
                        set: { _ in model.toggle(groupID: groupID) }
                    ))
                }
                Section("groups.alarms") {
                    let members = model.library.alarms(in: groupID)
                    if members.isEmpty {
                        Text("groups.alarms.empty").foregroundStyle(.secondary)
                    }
                    ForEach(members) { alarm in
                        Button {
                            model.editor = AlarmDraft(alarm: alarm)
                        } label: {
                            alarmLine(alarm)
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            model.moveAlarm(members[index].id, to: nil)
                        }
                    }
                }
                Section("groups.addAlarm") {
                    let others = model.library.alarms.filter { $0.groupID != groupID }
                    if others.isEmpty {
                        Text("groups.addAlarm.none").foregroundStyle(.secondary)
                    }
                    ForEach(others) { alarm in
                        Button {
                            model.moveAlarm(alarm.id, to: groupID)
                        } label: {
                            alarmLine(alarm)
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section {
                    Button("groups.changeSound") { changingGroupSound = true }
                        .disabled(model.library.alarms(in: groupID).isEmpty)
                    Button("groups.delete", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle("groups.edit")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let group = model.library.group(groupID) {
                name = group.name
                symbol = group.symbol
            }
        }
        .onDisappear {
            model.updateGroup(id: groupID, name: name, symbol: symbol)
        }
        .sheet(isPresented: $changingGroupSound) {
            SoundPickerSheet(title: "groups.changeSound") { soundID in
                model.setSound(soundID, forGroup: groupID)
            }
        }
        .alert("groups.delete", isPresented: $confirmDelete) {
            Button("groups.delete", role: .destructive) {
                model.deleteGroup(id: groupID)
                dismiss()
            }
            Button("alarm.cancel", role: .cancel) {}
        } message: {
            Text("groups.delete.confirm")
        }
        .accessibilityIdentifier("group-editor")
    }

    private func alarmLine(_ alarm: Alarm) -> some View {
        let parts = ClockFormat.parts(
            hour: alarm.schedule.hour,
            minute: alarm.schedule.minute,
            locale: .current,
            timeZone: .current
        )
        let label = alarm.label.isEmpty ? String(localized: "alarm.defaultLabel") : alarm.label
        let time = parts.period.isEmpty ? parts.time : "\(parts.time) \(parts.period)"
        return HStack {
            Text(time).monospacedDigit()
            Text(label)
            Spacer()
        }
    }
}
