import AVFoundation
import Foundation
import UIKit
import UniformTypeIdentifiers

enum VideoInstallError: Error, Equatable {
    case unreadable
    case tooLarge
}

enum VideoFiles {
    static func directory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("Videos", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func url(id: String) -> URL? {
        guard VideoMessagePolicy.isVideoID(id), let directory = try? directory() else { return nil }
        let url = directory.appendingPathComponent("\(id).\(VideoMessagePolicy.fileExtension)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func install(from source: URL, id: String) async throws -> String {
        guard VideoMessagePolicy.isVideoID(id) else { throw VideoInstallError.unreadable }
        let destination = try directory().appendingPathComponent("\(id).\(VideoMessagePolicy.fileExtension)")
        try await VideoCompressor.export(source: source, to: destination)
        guard VideoMessagePolicy.fits(byteCount: VideoFileCheck.byteCount(at: destination)) else {
            try? FileManager.default.removeItem(at: destination)
            throw VideoInstallError.tooLarge
        }
        return id
    }

    static func remove(id: String) {
        guard let url = url(id: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

enum VideoCompressor {
    static func export(source: URL, to destination: URL) async throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try await export(source: source, to: destination, preset: AVAssetExportPresetMediumQuality)
        if VideoFileCheck.byteCount(at: destination) > VideoMessagePolicy.maxBytes {
            try? FileManager.default.removeItem(at: destination)
            try await export(source: source, to: destination, preset: AVAssetExportPresetLowQuality)
        }
        guard VideoFileCheck.byteCount(at: destination) > 0 else { throw VideoInstallError.unreadable }
    }

    private static func export(source: URL, to destination: URL, preset: String) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw VideoInstallError.unreadable
        }
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { throw VideoInstallError.unreadable }
        let limited = VideoMessagePolicy.clamped(seconds)
        session.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: max(0.1, limited), preferredTimescale: 600)
        )
        try await session.export(to: destination, as: .mp4)
    }
}

struct CameraVideoPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoMaximumDuration = VideoMessagePolicy.maxSeconds
        picker.videoQuality = .typeMedium
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let url = info[.mediaURL] as? URL else {
                onCancel()
                return
            }
            onPick(url)
        }
    }
}
