import SwiftUI

struct TrimSoundView: View {
    @Environment(\.dismiss) private var dismiss
    let source: URL
    var onUse: (TrimWindow, String) -> Void

    @State private var duration: TimeInterval = 0
    @State private var start: Double = 0
    @State private var end: Double = 30
    @State private var name: String
    @State private var preview = SoundPreviewPlayer()
    @State private var failed = false

    init(source: URL, onUse: @escaping (TrimWindow, String) -> Void) {
        self.source = source
        self.onUse = onUse
        _name = State(initialValue: source.deletingPathExtension().lastPathComponent)
    }

    var body: some View {
        NavigationStack {
            Form {
                if failed {
                    Text("error.generic")
                } else if duration > 0 {
                    Text("sound.trim.help")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("sound.custom", text: $name)
                    VStack(alignment: .leading) {
                        Text("\(String(localized: "sound.start")) \(format(start))")
                        Slider(value: $start, in: 0...max(duration, 0.1))
                    }
                    VStack(alignment: .leading) {
                        Text("\(String(localized: "sound.end")) \(format(end))")
                        Slider(value: $end, in: 0...max(duration, 0.1))
                    }
                    Text(format(max(0, end - start)))
                        .font(.title2.monospacedDigit())
                    Button("sound.preview") { playTrimPreview() }
                    Button("sound.use") { useSelection() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("sound.importTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("alarm.cancel") { dismiss() }
                }
            }
            .task { await load() }
            .onChange(of: start) { _, _ in
                if preview.isPlaying("trim") { preview.stop() }
            }
            .onChange(of: end) { _, _ in
                if preview.isPlaying("trim") { preview.stop() }
            }
            .onDisappear { preview.stop() }
        }
    }

    private func load() async {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        do {
            let seconds = try await AudioTrimmer.duration(of: source)
            duration = seconds
            end = min(seconds, TrimWindow.maximumDuration)
        } catch {
            failed = true
        }
    }

    private func playTrimPreview() {
        if preview.isPlaying("trim") {
            preview.stop()
            return
        }
        let window = TrimWindow(start: start, end: end).clamped(to: duration)
            ?? TrimWindow(start: start, end: min(duration, start + TrimWindow.maximumDuration))
        preview.play(
            id: "trim",
            url: source,
            start: window.start,
            length: window.duration,
            securityScoped: true
        )
    }

    private func useSelection() {
        let window = TrimWindow(start: start, end: end).clamped(to: duration) ?? TrimWindow(start: 0, end: min(duration, 30))
        onUse(window, name.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }

    private func format(_ value: TimeInterval) -> String {
        let total = Int(value.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
