import SwiftUI
import UniformTypeIdentifiers

struct AlarmEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AlarmDraft
    @State private var time: Date
    @State private var importing = false
    @State private var trimFile: ImportedAudio?

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

                Section("alarm.sound") {
                    ForEach(SoundCatalog.bundled) { sound in
                        Button {
                            draft.soundID = sound.id
                        } label: {
                            HStack {
                                Text(LocalizedStringKey(sound.localizationKey))
                                Spacer()
                                if draft.soundID == sound.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    ForEach(model.customSounds) { sound in
                        Button {
                            draft.soundID = sound.id
                        } label: {
                            HStack {
                                Text(sound.displayName)
                                Spacer()
                                if draft.soundID == sound.id {
                                    Image(systemName: "checkmark").foregroundStyle(.orange)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    Button("sound.import") { importing = true }
                }

                Section {
                    Toggle("alarm.snooze", isOn: $draft.snoozeEnabled)
                        .tint(.orange)
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
                    Button("alarm.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("alarm.save") {
                        model.save(draft: draft)
                    }
                    .disabled(!draft.songIsValid)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mp3, .wav, .aiff]) { result in
                if case let .success(url) = result {
                    trimFile = ImportedAudio(url: url)
                }
            }
            .sheet(item: $trimFile) { file in
                TrimSoundView(source: file.url) { window, name in
                    Task {
                        if let id = await model.importSound(source: file.url, window: window, name: name) {
                            draft.soundID = id
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("alarm-editor")
    }

    private var repeatSummary: String {
        switch RepeatPatternClassifier.classify(Array(draft.repeatDays)) {
        case .never: String(localized: "repeat.never")
        case .everyDay: String(localized: "repeat.everyDay")
        case .weekdays: String(localized: "repeat.weekdays")
        case .weekends: String(localized: "repeat.weekends")
        case .custom:
            draft.repeatDays.sorted { $0.gregorianIndex < $1.gregorianIndex }
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

struct ImportedAudio: Identifiable {
    let id = UUID()
    let url: URL
}

struct DayPicker: View {
    @Binding var selection: Set<Weekday>

    var body: some View {
        let calendar = Calendar.current
        HStack {
            ForEach(Weekday.ordered(calendar: calendar)) { day in
                let selected = selection.contains(day)
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
                        .background(selected ? Color.orange : Color.secondary.opacity(0.15), in: Circle())
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.rawValue)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
