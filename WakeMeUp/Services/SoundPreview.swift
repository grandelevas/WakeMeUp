import AVFoundation
import Foundation

enum SoundPreviewPolicy {
    static let maximumDuration: TimeInterval = 10
    /// Loud enough to hear with the silent switch on, without playing at full scale.
    static let volume: Float = 0.8

    /// How long a preview should run. A requested trim range wins over the file length, and both are capped.
    static func length(fileDuration: TimeInterval, requested: TimeInterval?, cap: TimeInterval = maximumDuration) -> TimeInterval {
        let span = requested ?? fileDuration
        guard span.isFinite, span > 0 else { return 0 }
        return min(cap, span)
    }
}

@MainActor
final class SoundPreviewPlayer {
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?
    private var releaseAccess: (() -> Void)?
    private(set) var playingID: String?

    func isPlaying(_ id: String) -> Bool {
        playingID == id && player?.isPlaying == true
    }

    func play(
        id: String,
        url: URL,
        start: TimeInterval = 0,
        length: TimeInterval? = nil,
        securityScoped: Bool = false,
        cap: TimeInterval = SoundPreviewPolicy.maximumDuration
    ) {
        stop()
        let accessing = securityScoped && url.startAccessingSecurityScopedResource()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            let available = max(0, player.duration - max(0, start))
            let playLength = SoundPreviewPolicy.length(fileDuration: available, requested: length, cap: cap)
            guard playLength > 0 else {
                if accessing { url.stopAccessingSecurityScopedResource() }
                return
            }
            player.volume = SoundPreviewPolicy.volume
            player.currentTime = min(max(0, start), max(0, player.duration))
            player.prepareToPlay()
            guard player.play() else {
                if accessing { url.stopAccessingSecurityScopedResource() }
                return
            }
            self.player = player
            playingID = id
            if accessing {
                releaseAccess = { url.stopAccessingSecurityScopedResource() }
            }
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(playLength))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        player = nil
        playingID = nil
        releaseAccess?()
        releaseAccess = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
