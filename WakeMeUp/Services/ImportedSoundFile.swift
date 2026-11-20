import Foundation

enum ImportedSoundFile {
    /// Copies a picked file, including one that still lives in iCloud, into a local temporary folder.
    /// Security-scoped access is started here and ended before the local URL is returned.
    static func makeLocalCopy(of url: URL) async throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try copyCoordinated(from: url))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func remove(_ url: URL) {
        let folder = url.deletingLastPathComponent()
        if folder.lastPathComponent.hasPrefix("wakito-sound-") {
            try? FileManager.default.removeItem(at: folder)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func copyCoordinated(from url: URL) throws -> URL {
        var coordinationError: NSError?
        var copyError: Error?
        var copied: URL?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: url,
            options: .forUploading,
            error: &coordinationError
        ) { coordinated in
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("wakito-sound-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = coordinated.lastPathComponent.isEmpty ? "sound" : coordinated.lastPathComponent
                let target = folder.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: coordinated, to: target)
                copied = target
            } catch {
                try? FileManager.default.removeItem(at: folder)
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        guard let copied else { throw AudioTrimError.unreadable }
        return copied
    }
}
