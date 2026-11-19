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
                .readableWidth()
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

struct ImportedAudio: Identifiable {
    let id = UUID()
    let url: URL
}

struct DayPicker: View {
    @Binding var selection: Set<Weekday>

    var body: some View {
        let calendar = Calendar.current
        VStack(alignment: .leading, spacing: 10) {
            ChipFlow(spacing: 8) {
                ForEach(RepeatPreset.allCases, id: \.self) { preset in
                    let selected = RepeatPatternClassifier.selectedPreset(selection) == preset
                    Button {
                        selection = RepeatPatternClassifier.toggle(preset, in: selection)
                    } label: {
                        Text(title(preset))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selected ? Color.orange : Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("repeat-\(presetIdentifier(preset))")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func title(_ preset: RepeatPreset) -> LocalizedStringKey {
        switch preset {
        case .everyDay: "repeat.everyDay"
        case .weekdays: "repeat.weekdays"
        case .weekends: "repeat.weekends"
        }
    }

    private func presetIdentifier(_ preset: RepeatPreset) -> String {
        switch preset {
        case .everyDay: "every-day"
        case .weekdays: "weekdays"
        case .weekends: "weekend"
        }
    }
}

/// Lays chips in rows when the form is narrower than all three labels.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        let wrapped = rows(maxWidth: width, subviews: subviews)
        let height = wrapped.reduce(CGFloat(0)) { partial, row in
            partial + (row.map(\.size.height).max() ?? 0)
        } + spacing * CGFloat(max(wrapped.count - 1, 0))
        let used = wrapped.map { row in
            row.map(\.size.width).reduce(0, +) + spacing * CGFloat(max(row.count - 1, 0))
        }.max() ?? 0
        return CGSize(width: min(used, width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            let rowHeight = row.map(\.size.height).max() ?? 0
            for item in row {
                item.view.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private struct Item {
        let view: LayoutSubview
        let size: CGSize
    }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [[Item]] {
        var rows: [[Item]] = [[]]
        var rowWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            let item = Item(view: view, size: size)
            let next = rowWidth == 0 ? size.width : rowWidth + spacing + size.width
            if next > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([item])
                rowWidth = size.width
            } else {
                rows[rows.count - 1].append(item)
                rowWidth = next
            }
        }
        return rows
    }
}
