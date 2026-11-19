import SwiftUI

struct RingingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccent) private var appAccent
    let alarm: Alarm

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "alarm.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(appAccent)
                Text(parts.time)
                    .font(.system(size: 84, weight: .thin))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                if !parts.period.isEmpty {
                    Text(parts.period)
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Text(alarm.label.isEmpty ? String(localized: "alarm.defaultLabel") : alarm.label)
                    .font(.title2)
                    .foregroundStyle(.white)
                if let name = alarm.origin.senderName {
                    Text(String(format: String(localized: "sharing.remoteFrom"), name))
                        .foregroundStyle(appAccent)
                }
                Spacer()
                if alarm.songLink != nil {
                    Button {
                        Task { await model.playSong(of: alarm) }
                    } label: {
                        Label("song.play", systemImage: "music.note")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("play-song")
                    Text("ringing.note")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.7))
                }
                HStack(spacing: 16) {
                    if alarm.snoozeEnabled {
                        Button {
                            Task { await model.snoozeRinging() }
                        } label: {
                            Text("ringing.snooze")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .controlSize(.large)
                    }
                    Button {
                        Task { await model.stopRinging() }
                    } label: {
                        Text("song.stop")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("stop-alarm")
                }
            }
            .padding(24)
        }
        .accessibilityIdentifier("ringing-screen")
    }

    private var parts: ClockFormat.Parts {
        ClockFormat.parts(
            hour: alarm.schedule.hour,
            minute: alarm.schedule.minute,
            locale: .current,
            timeZone: .current
        )
    }
}
