import SwiftUI

struct BulkAlarmEditor: View {
    @Environment(\.dismiss) private var dismiss
    let seed: Alarm
    var onApply: (BulkAlarmPatch) -> Void
    @State private var time: Date
    @State private var hour: Int
    @State private var minute: Int
    @State private var repeatDays: Set<Weekday>
    @State private var soundID: String
    @State private var snoozeEnabled: Bool
    @State private var snoozeMinutes: Int
    @State private var label: String
    @State private var applyLabel = false
    @State private var preview = SoundPreviewPlayer()

    init(seed: Alarm, onApply: @escaping (BulkAlarmPatch) -> Void) {
        self.seed = seed
        self.onApply = onApply
        let calendar = Calendar.current
        let hour = seed.schedule.hour
        let minute = seed.schedule.minute
        _hour = State(initialValue: hour)
        _minute = State(initialValue: minute)
        _repeatDays = State(initialValue: Set(seed.schedule.repeatDays))
        _soundID = State(initialValue: seed.soundID)
        _snoozeEnabled = State(initialValue: seed.snoozeEnabled)
        _snoozeMinutes = State(initialValue: seed.snoozeMinutes)
        _label = State(initialValue: seed.label)
        _time = State(initialValue: Self.date(hour: hour, minute: minute, calendar: calendar))
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
                        hour = calendar.component(.hour, from: newValue)
                        minute = calendar.component(.minute, from: newValue)
                    }

                Section("alarm.repeat") {
                    DayPicker(selection: $repeatDays)
                }

                Section {
                    Toggle("alarms.bulk.applyLabel", isOn: $applyLabel)
                    if applyLabel {
                        TextField("alarm.defaultLabel", text: $label)
                    }
                }

                Section {
                    Toggle("alarm.snooze", isOn: $snoozeEnabled)
                    if snoozeEnabled {
                        Stepper(value: $snoozeMinutes, in: 1...30) {
                            Text(String(format: String(localized: "alarm.snooze.minutes"), snoozeMinutes))
                        }
                    }
                }

                SoundChoiceList(soundID: $soundID, preview: preview, showsImport: false)
            }
            .navigationTitle("alarms.bulk.title")
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
                        onApply(BulkAlarmPatch(
                            hour: hour,
                            minute: minute,
                            repeatDays: repeatDays,
                            soundID: soundID,
                            snoozeEnabled: snoozeEnabled,
                            snoozeMinutes: snoozeMinutes,
                            label: label,
                            applyLabel: applyLabel
                        ))
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("alarms.bulk.help")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
            .onDisappear { preview.stop() }
        }
        .accessibilityIdentifier("bulk-alarm-editor")
    }

    private static func date(hour: Int, minute: Int, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: .now)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? .now
    }
}
