import SwiftUI

struct AlarmEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AlarmDraft
    @State private var time: Date
    @State private var importing = false
    @State private var preview = SoundPreviewPlayer()

    init(draft: AlarmDraft) {
        _draft = State(initialValue: draft)
        _time = State(initialValue: Self.date(hour: draft.hour, minute: draft.minute))
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("alarm.label", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .onChange(of: time) { _, newValue in
                        let calendar = Calendar.current
                        draft.hour = calendar.component(.hour, from: newValue)
                        draft.minute = calendar.component(.minute, from: newValue)
                    }

                Section("alarm.repeat") {
                    DayPicker(selection: $draft.repeatDays)
                    Text(repeatSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("alarm.label") {
                    TextField("alarm.defaultLabel", text: $draft.label)
                }

                Section("alarm.note") {
                    TextField("alarm.note.placeholder", text: $draft.note, axis: .vertical)
                        .lineLimit(3...5)
                        .onChange(of: draft.note) { _, newValue in
                            if newValue.count > AlarmNote.maxCharacters {
                                draft.note = String(newValue.prefix(AlarmNote.maxCharacters))
                            }
                        }
                    Text("alarm.note.help")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                SoundChoiceList(soundID: $draft.soundID, preview: preview, showsImport: true) {
                    importing = true
                }

                Section {
                    Toggle("alarm.snooze", isOn: $draft.snoozeEnabled)
                    if draft.snoozeEnabled {
                        Stepper(value: $draft.snoozeMinutes, in: 1...30) {
                            Text(String(format: String(localized: "alarm.snooze.minutes"), draft.snoozeMinutes))
                        }
                    }
                }

                Section("alarm.group") {
                    Picker("alarm.group", selection: $draft.groupID) {
                        Text("alarm.noneGroup").tag(UUID?.none)
                        ForEach(model.library.groups) { group in
                            Text(group.name).tag(Optional(group.id))
                        }
                    }
                    if let groupID = draft.groupID, model.library.group(groupID)?.isEnabled == false {
                        Text("alarm.groupOff")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("alarm.song.placeholder", text: $draft.songText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    if !draft.songIsValid {
                        Text("song.invalid")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("alarm.song")
                } footer: {
                    Text("alarm.song.help")
                }

                if !draft.isNew {
                    Section {
                        Button("alarm.delete", role: .destructive) {
                            preview.stop()
                            model.delete(alarmID: draft.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(draft.isNew ? "editor.title.new" : "editor.title.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("alarm.cancel") {
                        preview.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("alarm.save") {
                        preview.stop()
                        model.save(draft: draft)
                    }
                    .disabled(!draft.songIsValid)
                }
            }
            .soundFileImporter(isPresented: $importing) { id in
                draft.soundID = id
                playPreview(of: id)
            }
            .onDisappear { preview.stop() }
        }
        .accessibilityIdentifier("alarm-editor")
    }

    private func playPreview(of id: String) {
        guard let url = SoundFiles.previewURL(for: id, customSounds: model.customSounds) else {
            preview.stop()
            return
        }
        preview.play(id: id, url: url)
    }

    private var repeatSummary: String {
        switch RepeatPatternClassifier.classify(Array(draft.repeatDays)) {
        case .never: String(localized: "repeat.never")
        case .everyDay: String(localized: "repeat.everyDay")
        case .weekdays: String(localized: "repeat.weekdays")
        case .weekends: String(localized: "repeat.weekends")
        case .custom:
            Weekday.sorted(draft.repeatDays, calendar: .current)
                .map { $0.veryShortSymbol(calendar: .current) }
                .joined(separator: " ")
        }
    }

    private static func date(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? .now
    }
}

struct DayPicker: View {
    @Binding var selection: Set<Weekday>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(RepeatPreset.allCases, id: \.self) { preset in
                    RepeatPresetChip(preset: preset, selection: $selection)
                }
            }
            WeekdayCircles(selection: $selection)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RepeatPresetChip: View {
    @Environment(\.appAccent) private var appAccent
    let preset: RepeatPreset
    @Binding var selection: Set<Weekday>

    private var selected: Bool {
        RepeatPatternClassifier.selectedPreset(selection) == preset
    }

    var body: some View {
        Button {
            selection = RepeatPatternClassifier.toggle(preset, in: selection)
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(fill, in: Capsule())
                .foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(traits)
    }

    private var title: LocalizedStringKey {
        switch preset {
        case .everyDay: "repeat.everyDay"
        case .weekdays: "repeat.weekdays"
        case .weekends: "repeat.weekends"
        }
    }

    private var identifier: String {
        switch preset {
        case .everyDay: "repeat-every-day"
        case .weekdays: "repeat-weekdays"
        case .weekends: "repeat-weekend"
        }
    }

    private var fill: Color {
        selected ? appAccent : Color.secondary.opacity(0.15)
    }

    private var foreground: Color {
        selected ? .white : .primary
    }

    private var traits: AccessibilityTraits {
        selected ? .isSelected : []
    }
}

private struct WeekdayCircles: View {
    @Binding var selection: Set<Weekday>

    var body: some View {
        let calendar = Calendar.current
        HStack {
            ForEach(Weekday.ordered(calendar: calendar)) { day in
                WeekdayCircle(day: day, calendar: calendar, selection: $selection)
            }
        }
    }
}

private struct WeekdayCircle: View {
    @Environment(\.appAccent) private var appAccent
    let day: Weekday
    let calendar: Calendar
    @Binding var selection: Set<Weekday>

    private var selected: Bool {
        selection.contains(day)
    }

    var body: some View {
        Button {
            if selected {
                selection.remove(day)
            } else {
                selection.insert(day)
            }
        } label: {
            Text(day.veryShortSymbol(calendar: calendar))
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(fill, in: Circle())
                .foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.rawValue)
    }

    private var fill: Color {
        selected ? appAccent : Color.secondary.opacity(0.15)
    }

    private var foreground: Color {
        selected ? .white : .primary
    }
}

