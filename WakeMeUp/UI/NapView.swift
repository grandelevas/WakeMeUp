import SwiftUI

struct NapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccent) private var appAccent

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Text(String(format: String(localized: "nap.minutes"), model.napMinutes))
                            .font(.title2.weight(.semibold))
                        Text("nap.length.help")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 36)

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

                    VStack(spacing: 6) {
                        Text("nap.start")
                            .font(.headline)
                        if let fire = model.activeNapFireDate {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let left = NapCountdown.remaining(until: fire, now: context.date)
                                Text(NapCountdown.clock(left))
                                    .font(.system(size: 56, weight: .thin, design: .rounded))
                                    .monospacedDigit()
                            }
                            Text(String(format: String(localized: "nap.running"), fire.formatted(date: .omitted, time: .shortened)))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let failure = model.scheduleFailure, !failure.isEmpty {
                            Text(failure)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }

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
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("nap.title")
        }
        .accessibilityIdentifier("nap-screen")
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
