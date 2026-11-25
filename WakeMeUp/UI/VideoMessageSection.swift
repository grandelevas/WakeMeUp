import AVKit
import SwiftUI

struct VideoMessageSection: View {
    @Environment(AppModel.self) private var model
    var videoID: String?
    var onChange: (String?) -> Void
    @State private var capturing = false

    var body: some View {
        Section {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("video.record") { capturing = true }
            } else {
                Text("video.camera.unavailable")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let url = videoURL {
                VideoMessagePlayer(url: url)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
