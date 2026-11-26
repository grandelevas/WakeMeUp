import AVFoundation
import SwiftUI

struct VoiceRecorderPanel: View {
    var recorder: VoiceClipRecorder
    var preview: SoundPreviewPlayer
    var savedURL: URL? = nil
    var help: LocalizedStringKey
    var voiceTipPresented: Binding<Bool> = .constant(false)
    var onUse: (URL) -> Void
    var onClear: () -> Void

    private var clipURL: URL? {
        if let url = recorder.fileURL, VoiceFileCheck.isStoredAAC(url) { return url }
        return savedURL
    }

    private var playID: String {
        clipURL?.lastPathComponent ?? "voice-draft"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(help)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if recorder.permissionDenied {
                Text("sharing.voice.denied")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if recorder.isRecording {
                recordingRow
                Button("sharing.voice.stop") { recorder.stop() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
            } else if let url = clipURL {
                Text(durationLabel(for: url))
                    .font(.subheadline)
                Button(preview.isPlaying(playID) ? "sharing.voice.pause" : "sharing.voice.play") {
                    if preview.isPlaying(playID) {
                        preview.stop()
                    } else {
                        preview.play(id: playID, url: url, cap: VoiceClipPolicy.maxSeconds)
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("voice-play")
                Button("sharing.voice.rerecord") {
                    preview.stop()
                    onClear()
                    Task { await recorder.start() }
                }
                .buttonStyle(.borderless)
                Button("sharing.voice.delete") {
                    preview.stop()
                    onClear()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            } else {
                Text("voice.empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("sharing.voice.record") {
                    Task { await recorder.start() }
                }
                .buttonStyle(.borderless)
                .popover(isPresented: voiceTipPresented) {
                    OnboardingTip(
                        title: "onboarding.tip.voice.title",
                        message: "onboarding.tip.voice.body"
                    ) {
                        OnboardingStore.markVoiceTipSeen(defaults: .standard)
                        voiceTipPresented.wrappedValue = false
                    }
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
        .onChange(of: recorder.isRecording) { _, recording in
            guard !recording, let url = recorder.fileURL, VoiceFileCheck.isStoredAAC(url) else { return }
            onUse(url)
        }
    }

    private var recordingRow: some View {
        HStack(spacing: 8) {
            RecordingDot()
            Text("sharing.voice.recording")
            Spacer()
            Text("\(VoiceClipPolicy.clock(recorder.elapsed)) / \(VoiceClipPolicy.clock(VoiceClipPolicy.maxSeconds))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("voice-recording")
    }

    private func durationLabel(for url: URL) -> String {
        let seconds = recorder.duration ?? Self.fileDuration(url)
        return String(format: String(localized: "sharing.voice.duration"), VoiceClipPolicy.clock(seconds))
    }

    private static func fileDuration(_ url: URL) -> TimeInterval {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return 0 }
        return VoiceClipPolicy.clamped(player.duration)
    }
}

private struct RecordingDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 12, height: 12)
            .opacity(pulse ? 0.3 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .accessibilityLabel(Text("sharing.voice.recording"))
    }
}
