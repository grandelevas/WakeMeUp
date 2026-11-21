import AVFoundation
import Foundation
import Observation
import UIKit

enum VoiceClipPolicy {
    /// Short enough to ride along with a CloudKit asset and still ring as an alarm.
    static let maxSeconds: TimeInterval = 20

    static func clamped(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return min(seconds, maxSeconds)
    }

    /// `0:00` style, capped at the recording limit.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(clamped(seconds).rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    static func soundID(installed: Bool, voiceID: String?) -> String {
        if installed, let voiceID, !voiceID.isEmpty { return voiceID }
        return SoundCatalog.defaultID
    }
}

enum VoiceRecordingFormat {
    static let fileExtension = "m4a"

    static func settings() -> [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 64_000
        ]
    }
}

enum VoiceAudioRoute {
    static func recording() -> (category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions) {
        (.playAndRecord, [.defaultToSpeaker])
    }

    static func preview() -> (category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions) {
        (.playback, [.defaultToSpeaker])
    }

    static func applyRecording() throws {
        let route = recording()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(route.category, mode: .default, options: route.options)
        try session.setActive(true)
    }

    /// Playback through the speaker. `defaultToSpeaker` is requested first so a session
    /// left in the record route does not stay on the earpiece.
    static func applyPreview() throws {
        let route = preview()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(route.category, mode: .default, options: route.options)
        } catch {
            try session.setCategory(.playback, mode: .default, options: [])
        }
        try? session.overrideOutputAudioPort(.speaker)
        try session.setActive(true)
    }
}

enum MicrophoneAccess: Equatable {
    case undetermined
    case granted
    case denied

    static func map(_ permission: AVAudioApplication.recordPermission) -> MicrophoneAccess {
        switch permission {
        case .undetermined: .undetermined
        case .granted: .granted
        case .denied: .denied
        @unknown default: .denied
        }
    }
}

enum VoiceFileError: Error, Equatable {
    case empty
    case unusable
}

enum VoiceFileCheck {
    static func byteCount(at url: URL) -> Int {
        let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return size?.intValue ?? 0
    }

    static func isAACContainer(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == VoiceRecordingFormat.fileExtension { return true }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 12), data.count >= 8 else { return false }
        return data[4..<8] == Data("ftyp".utf8)
    }

    static func isStoredAAC(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == VoiceRecordingFormat.fileExtension
            && isAACContainer(url)
            && byteCount(at: url) > 0
    }
}

enum VoiceFiles {
    static func relativeFilename(soundID: String) -> String {
        "\(stem(soundID)).\(VoiceRecordingFormat.fileExtension)"
    }

    /// AlarmKit and notification sounds play the CAF written next to the m4a.
    static func ringingFilename(stored filename: String) -> String {
        let name = (filename as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == VoiceRecordingFormat.fileExtension {
            return ((name as NSString).deletingPathExtension as NSString).appendingPathExtension("caf") ?? name
        }
        return name
    }

    /// Only the file name is kept. An absolute path from a previous launch is not reused.
    static func url(relativeFilename: String, in directory: URL) -> URL {
        let name = (relativeFilename as NSString).lastPathComponent
        return directory.appendingPathComponent(name)
    }

    static func install(from source: URL, soundID: String) throws -> CustomSound {
        let directory = try SoundFiles.librarySoundsDirectory()
        if VoiceFileCheck.isAACContainer(source) {
            let filename = relativeFilename(soundID: soundID)
            let destination = url(relativeFilename: filename, in: directory)
            try copyReplacing(source, to: destination)
            let ringing = url(relativeFilename: ringingFilename(stored: filename), in: directory)
            try writeAlarmCAF(from: destination, to: ringing)
            guard VoiceFileCheck.isStoredAAC(destination), VoiceFileCheck.byteCount(at: ringing) > 0 else {
                throw VoiceFileError.unusable
            }
            return CustomSound(id: soundID, displayName: String(localized: "sound.voice"), filename: filename)
        }
        let ext = source.pathExtension.lowercased()
        let filename = "\(stem(soundID)).\(ext.isEmpty ? "caf" : ext)"
        let destination = url(relativeFilename: filename, in: directory)
        try copyReplacing(source, to: destination)
        guard VoiceFileCheck.byteCount(at: destination) > 0 else { throw VoiceFileError.empty }
        return CustomSound(id: soundID, displayName: String(localized: "sound.voice"), filename: filename)
    }

    static func remove(relativeFilename: String) {
        guard let directory = try? SoundFiles.librarySoundsDirectory() else { return }
        let stored = url(relativeFilename: relativeFilename, in: directory)
        try? FileManager.default.removeItem(at: stored)
        let ringing = url(relativeFilename: ringingFilename(stored: relativeFilename), in: directory)
        if ringing.path != stored.path {
            try? FileManager.default.removeItem(at: ringing)
        }
    }

    private static func stem(_ soundID: String) -> String {
        let base = (soundID as NSString).lastPathComponent
        let stem = (base as NSString).deletingPathExtension
        return stem.isEmpty ? "voice" : stem
    }

    private static func copyReplacing(_ source: URL, to destination: URL) throws {
        if source.standardizedFileURL.path == destination.standardizedFileURL.path { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    /// 16-bit PCM CAF. AlarmKit and notification sounds do not play m4a.
    static func writeAlarmCAF(from source: URL, to destination: URL) throws {
        let input = try AVAudioFile(forReading: source)
        guard input.length > 0 else { throw VoiceFileError.empty }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: input.processingFormat,
            frameCapacity: AVAudioFrameCount(input.length)
        ) else { throw VoiceFileError.unusable }
        try input.read(into: buffer)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: input.processingFormat.sampleRate,
            AVNumberOfChannelsKey: Int(input.processingFormat.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = try AVAudioFile(
            forWriting: destination,
            settings: settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        if buffer.format == output.processingFormat {
            try output.write(from: buffer)
            return
        }
        guard let converter = AVAudioConverter(from: buffer.format, to: output.processingFormat) else {
            throw VoiceFileError.unusable
        }
        let ratio = output.processingFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(max(1, (ratio * Double(buffer.frameLength)).rounded(.up)))
        guard let converted = AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: capacity) else {
            throw VoiceFileError.unusable
        }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, statusOut in
            if consumed {
                statusOut.pointee = .endOfStream
                return nil
            }
            consumed = true
            statusOut.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil else { throw VoiceFileError.unusable }
        try output.write(from: converted)
    }
}

@MainActor
@Observable
final class VoiceClipRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var clock: Task<Void, Never>?
    private(set) var relativeFilename: String?
    private(set) var isRecording = false
    private(set) var permissionDenied = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval?

    var fileURL: URL? {
        guard let relativeFilename, let directory = try? SoundFiles.librarySoundsDirectory() else { return nil }
        return VoiceFiles.url(relativeFilename: relativeFilename, in: directory)
    }

    func start() async {
        if isRecording { return }
        let current = MicrophoneAccess.map(AVAudioApplication.shared.recordPermission)
        let allowed: Bool
        if current == .undetermined {
            allowed = await AVAudioApplication.requestRecordPermission()
        } else {
            allowed = current == .granted
        }
        guard allowed else {
            permissionDenied = true
            return
        }
        permissionDenied = false
        do {
            try begin()
        } catch {
            discard()
            permissionDenied = false
        }
    }

    func stop() {
        guard isRecording else { return }
        let current = recorder?.currentTime ?? elapsed
        elapsed = VoiceClipPolicy.clamped(current)
        isRecording = false
        clock?.cancel()
        clock = nil
        recorder?.stop()
        recorder = nil
        if let url = fileURL, VoiceFileCheck.isStoredAAC(url) {
            if let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 {
                duration = VoiceClipPolicy.clamped(player.duration)
            } else {
                duration = elapsed
            }
        } else {
            duration = nil
            relativeFilename = nil
        }
        haptic()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func discard() {
        let url = fileURL
        relativeFilename = nil
        duration = nil
        elapsed = 0
        permissionDenied = false
        stop()
        if let url {
            try? FileManager.default.removeItem(at: url)
            let ringing = url.deletingPathExtension().appendingPathExtension("caf")
            try? FileManager.default.removeItem(at: ringing)
        }
    }

    private func begin() throws {
        stop()
        try VoiceAudioRoute.applyRecording()
        let soundID = "voice-\(UUID().uuidString)"
        let filename = VoiceFiles.relativeFilename(soundID: soundID)
        let directory = try SoundFiles.librarySoundsDirectory()
        let url = VoiceFiles.url(relativeFilename: filename, in: directory)
        let recorder = try AVAudioRecorder(url: url, settings: VoiceRecordingFormat.settings())
        recorder.delegate = self
        guard recorder.prepareToRecord(), recorder.record(forDuration: VoiceClipPolicy.maxSeconds) else {
            try? FileManager.default.removeItem(at: url)
            throw VoiceFileError.unusable
        }
        self.recorder = recorder
        relativeFilename = filename
        elapsed = 0
        duration = nil
        isRecording = true
        haptic()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.isRecording else { return }
                let current = self.recorder?.currentTime ?? self.elapsed
                self.elapsed = VoiceClipPolicy.clamped(current)
                if self.elapsed >= VoiceClipPolicy.maxSeconds {
                    self.stop()
                    return
                }
            }
        }
    }

    private func haptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.isRecording else { return }
            if flag {
                self.stop()
            } else {
                self.discard()
            }
        }
    }
}
