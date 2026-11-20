import AVFoundation
import Foundation
import Observation

enum VoiceClipPolicy {
    /// Short enough to ride along with a CloudKit asset and still ring as an alarm.
    static let maxSeconds: TimeInterval = 20

    static func clamped(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return min(seconds, maxSeconds)
    }

    static func soundID(installed: Bool, voiceID: String?) -> String {
        if installed, let voiceID, !voiceID.isEmpty { return voiceID }
        return SoundCatalog.defaultID
    }
}

enum VoiceFiles {
    static func install(from source: URL, soundID: String) throws -> CustomSound {
        let directory = try SoundFiles.librarySoundsDirectory()
        let filename = "\(soundID).caf"
        let destination = directory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return CustomSound(id: soundID, displayName: String(localized: "sound.voice"), filename: filename)
    }
}

@MainActor
@Observable
final class VoiceClipRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var stopTask: Task<Void, Never>?
    private(set) var fileURL: URL?
    private(set) var isRecording = false

    func record() throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wakito-voice-\(UUID().uuidString).caf")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.record(forDuration: VoiceClipPolicy.maxSeconds)
        self.recorder = recorder
        fileURL = url
        isRecording = true
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(VoiceClipPolicy.maxSeconds))
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
    }

    func discard() {
        stop()
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
    }
}
