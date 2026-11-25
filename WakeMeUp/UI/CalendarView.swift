import SwiftUI

struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccent) private var appAccent
    @State private var visibleMonth = Date.now
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var draft: CalendarAlarmDraft?

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    weekdayRow
                    monthGrid
                        .simultaneousGesture(monthSwipe)
                    dayAlarms
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("calendar.title")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draft = CalendarAlarmDraft(day: selectedDay, calendar: calendar)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("calendar.add")
                    .accessibilityIdentifier("add-calendar-alarm")
                }
            }
            .sheet(item: $draft) { draft in
                CalendarAlarmEditor(draft: draft, onSave: { alarm in
                    model.saveCalendarAlarm(alarm)
                }, onDelete: draft.isNew ? nil : {
                    model.deleteCalendarAlarm(draft.id)
                })
            }
        }
        .accessibilityIdentifier("calendar-screen")
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("calendar.previousMonth")
            Spacer()
            Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("calendar.nextMonth")
        }
        .padding(.top, 8)
    }

    private var weekdayRow: some View {
        let symbols = calendar.veryShortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        let ordered = (0..<7).map { symbols[($0 + start) % 7] }
        return HStack {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let cells = CalendarGrid.cells(monthContaining: visibleMonth, calendar: calendar)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
            ForEach(cells) { cell in
                dayButton(cell)
            }
        }
    }

    private func dayButton(_ cell: CalendarGrid.Cell) -> some View {
        let marked = model.calendarAlarms.contains { $0.occurs(on: cell.date, calendar: calendar) }
        let selected = calendar.isDate(cell.date, inSameDayAs: selectedDay)
        return Button {
            selectedDay = calendar.startOfDay(for: cell.date)
            visibleMonth = cell.date
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: cell.date))")
                    .font(.body.weight(selected ? .bold : .regular))
                    .foregroundStyle(cell.inMonth ? Color.primary : Color.secondary)
                Circle()
                    .fill(marked ? appAccent : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(selected ? appAccent.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var dayAlarms: some View {
        let alarms = model.calendarAlarms
            .filter { $0.occurs(on: selectedDay, calendar: calendar) }
            .sorted { ($0.hour, $0.minute, $0.label) < ($1.hour, $1.minute, $1.label) }
        return VStack(alignment: .leading, spacing: 8) {
            Text(selectedDay.formatted(date: .complete, time: .omitted))
                .font(.headline)
            if alarms.isEmpty {
                Text("calendar.empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(alarms) { alarm in
                Button {
                    draft = CalendarAlarmDraft(alarm: alarm, calendar: calendar)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(clock(alarm))
                                .font(.title3.monospacedDigit())
                            Text(alarm.label.isEmpty ? String(localized: "calendar.name") : alarm.label)
                                .font(.subheadline)
                            if let note = alarm.note, !note.isEmpty {
                                Text(note)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Text(LocalizedStringKey(alarm.repeatRule.localizationKey))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !alarm.isEnabled {
                            Text("alarm.off")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("alarm.delete", systemImage: "trash", role: .destructive) {
                        model.deleteCalendarAlarm(alarm.id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func clock(_ alarm: CalendarAlarm) -> String {
        let parts = ClockFormat.parts(hour: alarm.hour, minute: alarm.minute, locale: .current, timeZone: calendar.timeZone)
        return parts.period.isEmpty ? parts.time : "\(parts.time) \(parts.period)"
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: visibleMonth) else { return }
        visibleMonth = next
    }

    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let travel = value.translation.width
                guard abs(travel) > abs(value.translation.height), abs(travel) > 48 else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    shiftMonth(travel < 0 ? 1 : -1)
                }
            }
    }
}

struct CalendarAlarmDraft: Equatable, Identifiable {
    var id: UUID
    var day: Date
    var time: Date
    var repeatRule: CalendarRepeat
    var label: String
    var note: String
    var soundID: String
    var snoozeEnabled: Bool
    var snoozeMinutes: Int
    var isEnabled: Bool
    var isNew: Bool

    init(day: Date, calendar: Calendar) {
        id = UUID()
        self.day = calendar.startOfDay(for: day)
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = 7
        parts.minute = 0
        time = calendar.date(from: parts) ?? day
        repeatRule = .once
        label = ""
        note = ""
        soundID = SoundCatalog.defaultID
        snoozeEnabled = true
        snoozeMinutes = 9
        isEnabled = true
        isNew = true
    }

    init(alarm: CalendarAlarm, calendar: Calendar) {
        id = alarm.id
        var parts = DateComponents()
        parts.year = alarm.year
        parts.month = alarm.month
        parts.day = alarm.day
        day = calendar.date(from: parts) ?? .now
        parts.hour = alarm.hour
        parts.minute = alarm.minute
        time = calendar.date(from: parts) ?? day
        repeatRule = alarm.repeatRule
        label = alarm.label
        note = alarm.note ?? ""
        soundID = alarm.soundID
        snoozeEnabled = alarm.snoozeEnabled
        snoozeMinutes = alarm.snoozeMinutes
        isEnabled = alarm.isEnabled
        isNew = false
    }

    func alarm(calendar: Calendar) -> CalendarAlarm? {
        let dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        guard let year = dayParts.year, let month = dayParts.month, let day = dayParts.day,
              let hour = timeParts.hour, let minute = timeParts.minute else { return nil }
        return CalendarAlarm(
            id: id,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            repeatRule: repeatRule,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            soundID: soundID,
            snoozeEnabled: snoozeEnabled,
            snoozeMinutes: min(30, max(1, snoozeMinutes)),
            isEnabled: isEnabled,
            note: AlarmNote.cleaned(note)
        )
    }
}

struct CalendarAlarmEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CalendarAlarmDraft
    @State private var preview = SoundPreviewPlayer()
    var onSave: (CalendarAlarm) -> Void
    var onDelete: (() -> Void)?

    init(draft: CalendarAlarmDraft, onSave: @escaping (CalendarAlarm) -> Void, onDelete: (() -> Void)? = nil) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("calendar.date", selection: $draft.day, displayedComponents: .date)
                DatePicker("calendar.time", selection: $draft.time, displayedComponents: .hourAndMinute)
                Picker("calendar.repeat", selection: $draft.repeatRule) {
                    ForEach(CalendarRepeat.allCases) { rule in
                        Text(LocalizedStringKey(rule.localizationKey)).tag(rule)
                    }
                }
                TextField("calendar.name", text: $draft.label)
                TextField("alarm.note.placeholder", text: $draft.note, axis: .vertical)
                    .lineLimit(3...6)
                    .onChange(of: draft.note) { _, newValue in
                        if newValue.count > AlarmNote.maxCharacters {
                            draft.note = String(newValue.prefix(AlarmNote.maxCharacters))
                        }
                    }
                Toggle("alarm.snooze", isOn: $draft.snoozeEnabled)
                if draft.snoozeEnabled {
                    Stepper(value: $draft.snoozeMinutes, in: 1...30) {
                        Text(String(format: String(localized: "alarm.snooze.minutes"), draft.snoozeMinutes))
                    }
                }
                SoundChoiceList(soundID: $draft.soundID, preview: preview)
                if let alarm = draft.alarm(calendar: .current),
                   alarm.repeatRule == .once,
                   alarm.nextFire(from: .now, calendar: .current) == nil {
                    Text("calendar.past")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if onDelete != nil {
                    Button("alarm.delete", role: .destructive) {
                        preview.stop()
                        onDelete?()
                        dismiss()
                    }
                }
            }
            .navigationTitle(draft.isNew ? "calendar.add" : "calendar.edit")
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
                        if let alarm = draft.alarm(calendar: .current) {
                            onSave(alarm)
                        }
                        dismiss()
                    }
                    .disabled(pastOnce)
                }
            }
            .onDisappear { preview.stop() }
        }
    }

    private var pastOnce: Bool {
        guard let alarm = draft.alarm(calendar: .current), alarm.repeatRule == .once else { return false }
        return alarm.nextFire(from: .now, calendar: .current) == nil
    }
}
