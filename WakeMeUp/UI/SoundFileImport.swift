import SwiftUI
import UniformTypeIdentifiers

struct ImportedAudio: Identifiable {
    let id = UUID()
    let url: URL
}

extension UTType {
    static let wakitoSoundImport: [UTType] = [.audio, .mp3, .wav, .aiff, .mpeg4Audio]
}

private struct SoundFileImportModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    var onImported: (String) -> Void

    @State private var copying = false
    @State private var unreadable = false
    @State private var trimFile: ImportedAudio?
    @State private var retainUntilImportFinishes = false

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: UTType.wakitoSoundImport) { result in
                switch result {
                case let .success(url):
                    copying = true
                    Task {
                        defer { copying = false }
                        do {
                            let local = try await ImportedSoundFile.makeLocalCopy(of: url)
                            dismissedCopy = local
                            retainUntilImportFinishes = false
                            trimFile = ImportedAudio(url: local)
                        } catch {
                            unreadable = true
                        }
                    }
                case .failure:
                    unreadable = true
                }
            }
            .overlay {
                if copying {
                    ProgressView("sound.importing")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("sound.importTitle", isPresented: $unreadable) {
                Button("alarm.cancel", role: .cancel) {}
            } message: {
                Text("sound.unreadable")
            }
            .sheet(item: $trimFile, onDismiss: {
                guard let url = dismissedCopy else { return }
                if retainUntilImportFinishes {
                    retainUntilImportFinishes = false
                    return
                }
                ImportedSoundFile.remove(url)
                dismissedCopy = nil
            }) { file in
                TrimSoundView(source: file.url) { window, name in
                    let url = file.url
                    dismissedCopy = url
                    retainUntilImportFinishes = true
                    Task {
                        defer { ImportedSoundFile.remove(url) }
                        if let id = await model.importSound(source: url, window: window, name: name) {
                            onImported(id)
                        }
                    }
                }
                .readableWidth()
            }
    }

    @State private var dismissedCopy: URL?
}

extension View {
    func soundFileImporter(isPresented: Binding<Bool>, onImported: @escaping (String) -> Void) -> some View {
        modifier(SoundFileImportModifier(isPresented: isPresented, onImported: onImported))
    }
}
