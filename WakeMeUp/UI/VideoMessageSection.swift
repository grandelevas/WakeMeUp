import AVKit
import SwiftUI

struct VideoMessageSection: View {
    @Environment(AppModel.self) private var model
    var videoID: String?
    var onChange: (String?) -> Void
    @State private var capturing = false

    var body: some View {
        Section {
            if videoID == nil {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("video.record") { capturing = true }
                } else {
                    Text("video.camera.unavailable")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if videoID != nil {
                VideoMessagePreview(videoID: videoID, height: 200)
                Button("video.delete", role: .destructive) {
                    if let videoID {
                        model.removeVideo(videoID)
                    }
                    onChange(nil)
                }
            }
        } header: {
            Text("video.title")
        } footer: {
            Text("video.help")
        }
        .fullScreenCover(isPresented: $capturing) {
            CameraVideoPicker(
                onPick: { url in
                    capturing = false
                    Task { await store(url) }
                },
                onCancel: { capturing = false }
            )
            .ignoresSafeArea()
        }
    }

    private var videoURL: URL? {
        guard let videoID else { return nil }
        return VideoFiles.url(id: videoID)
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
    static func image(id: String) -> UIImage? {
        guard VideoMessagePolicy.isVideoID(id), let directory = try? VideoFiles.directory() else { return nil }
        let url = directory.appendingPathComponent("\(id).jpg")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
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
        VideoPlayer(player: player)
            .onAppear { player.play() }
            .onDisappear { player.pause() }
            .accessibilityLabel("video.play")
    }
}
