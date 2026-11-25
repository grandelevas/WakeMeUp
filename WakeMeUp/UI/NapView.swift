import SwiftUI

struct NapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccent) private var appAccent

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    lengthPicker
                        .padding(.top, 24)

                    if let fire = model.activeNapFireDate {
                        running(until: fire)
                    } else {
                        startButton
                    }

                    if let failure = model.scheduleFailure, !failure.isEmpty, model.activeNapFireDate == nil {
                        Text(failure)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    tips
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("nap.title")
        }
        .accessibilityIdentifier("nap-screen")
    }

    private var lengthPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("nap.length")
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(NapSettings.presets, id: \.self) { minutes in
                    Button {
                        model.setNapMinutes(minutes)
                    } label: {
                        Text(String(format: String(localized: "nap.minutes"), minutes))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(model.napMinutes == minutes ? Color.white : Color.primary)
                            .background(
                                model.napMinutes == minutes ? appAccent : Color.secondary.opacity(0.15),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.activeNapFireDate != nil)
                    .accessibilityIdentifier("nap-preset-\(minutes)")
                }
            }
            Stepper(
                value: Binding(
                    get: { model.napMinutes },
                    set: { model.setNapMinutes($0) }
                ),
                in: NapSettings.minimumMinutes...NapSettings.maximumMinutes,
                step: NapSettings.stepMinutes
            ) {
                Text(String(format: String(localized: "nap.customMinutes"), model.napMinutes))
            }
            .disabled(model.activeNapFireDate != nil)
        }
    }

    private var startButton: some View {
        VStack(spacing: 8) {
            Button {
                Task { await model.startNap() }
            } label: {
                Text("😴")
                    .font(.system(size: 128))
                    .frame(width: 220, height: 220)
                    .background(appAccent.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("nap.start")
            .accessibilityIdentifier("start-nap")
            Text("nap.start")
                .font(.headline)
        }
    }

    private func running(until fire: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = NapCountdown.remaining(until: fire, now: context.date)
            VStack(spacing: 16) {
                Text("😴")
                    .font(.system(size: 72))
                Text(NapCountdown.clock(left))
                    .font(.system(size: 72, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .accessibilityIdentifier("nap-countdown")
                Text(String(format: String(localized: "nap.running"), fire.formatted(date: .omitted, time: .shortened)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("nap.cancel") {
                    Task { await model.cancelNap() }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("cancel-nap")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("nap.tips.title")
                .font(.headline)
            tip("nap.tips.length")
            tip("nap.tips.late")
            tip("nap.tips.place")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.bar, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func tip(_ key: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(key)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
