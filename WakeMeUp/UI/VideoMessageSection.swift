import AVKit
import SwiftUI

struct VideoMessageSection: View {
    @Environment(AppModel.self) private var model
    var videoID: String?
    var onChange: (String?) -> Void
    @State private var playing = false

    var body: some View {
        Section {
            if videoID == nil {
                Text("video.empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("video.record") { record() }
                    .accessibilityIdentifier("record-video")
                } else {
                    Text("video.camera.unavailable")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let videoID {
                if playing, let url = VideoFiles.url(id: videoID) {
                    VideoMessagePlayer(url: url)
                        .frame(height: 200)
                } else {
                    Button {
                        playing = true
                    } label: {
                        VideoMessagePreview(videoID: videoID, height: 200)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("video.play")
                    Button("video.play") { playing = true }
                        .accessibilityIdentifier("play-video")
                }
                Button("video.recordAgain") { record() }
                Button("video.delete", role: .destructive) {
                    model.removeVideo(videoID)
                    playing = false
                    onChange(nil)
                }
            }
        } header: {
            Text("video.title")
        } footer: {
            Text("video.help")
        }
    }

    private func record() {
        model.videoCaptureActive = true
        CameraVideoCapture.present(
            onPick: { url in
                model.videoCaptureActive = false
                Task { await store(url) }
            },
            onCancel: { model.videoCaptureActive = false }
        )
    }

    private func store(_ url: URL) async {
        if let previous = videoID {
            model.removeVideo(previous)
        }
        if let id = await model.installVideo(from: url) {
            onChange(id)
        }
    }
}

struct VideoMessagePreview: View {
    var videoID: String?
    var height: CGFloat = 200

    var body: some View {
        if let videoID, let image = VideoPoster.image(id: videoID) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
                .overlay {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 56))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.35))
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("video.play")
        } else if let url = videoURL {
            VideoMessagePlayer(url: url)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var videoURL: URL? {
        guard let videoID else { return nil }
        return VideoFiles.url(id: videoID)
    }
}

enum VideoPoster {
    static func fileURL(id: String) -> URL? {
        guard VideoMessagePolicy.isVideoID(id), let directory = try? VideoFiles.directory() else { return nil }
        return directory.appendingPathComponent("\(id).jpg")
    }

    static func image(id: String) -> UIImage? {
        guard let url = fileURL(id: id), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func write(from video: URL, id: String) {
        let asset = AVURLAsset(url: video)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let time = CMTime(seconds: 0.2, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil),
              let url = fileURL(id: id),
              let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.82) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

struct VideoMessagePlayer: View {
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VideoPlayer(player: player)
            Button {
                replay()
            } label: {
                Label("video.replay", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(12)
            .accessibilityIdentifier("replay-video")
        }
        .onAppear { start() }
        .onDisappear { player.pause() }
        .accessibilityLabel("video.play")
    }

    private func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
        player.play()
    }

    private func replay() {
        player.seek(to: .zero)
        player.play()
    }
}
