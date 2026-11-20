import SwiftUI

struct SoundChoiceList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccent) private var appAccent
    @Binding var soundID: String
    var preview: SoundPreviewPlayer
    var showsImport: Bool = false
    var onImport: () -> Void = {}

    var body: some View {
        Section("sound.author.section") {
            ForEach(SoundCatalog.author) { sound in
                row(id: sound.id, title: Text(LocalizedStringKey(sound.localizationKey)))
            }
        }
        Section("alarm.sound") {
            ForEach(SoundCatalog.bundled) { sound in
                row(id: sound.id, title: Text(LocalizedStringKey(sound.localizationKey)))
            }
            ForEach(model.customSounds) { sound in
                row(id: sound.id, title: Text(sound.displayName))
            }
            if showsImport {
                Button("sound.import", action: onImport)
            }
        }
    }

    private func row(id: String, title: Text) -> some View {
        Button {
            choose(id)
        } label: {
            HStack {
                title
                Spacer()
                if soundID == id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(appAccent)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func choose(_ id: String) {
        if soundID == id, preview.isPlaying(id) {
            preview.stop()
            return
        }
        soundID = id
        guard let url = SoundFiles.previewURL(for: id, customSounds: model.customSounds) else {
            preview.stop()
            return
        }
        preview.play(id: id, url: url)
    }
}

struct SoundPickerSheet: View {
    var title: LocalizedStringKey = "alarms.changeSound"
    var onUse: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var soundID = SoundCatalog.defaultID
    @State private var preview = SoundPreviewPlayer()
    @State private var importing = false
    @State private var trimFile: ImportedAudio?

    var body: some View {
        NavigationStack {
            Form {
                SoundChoiceList(soundID: $soundID, preview: preview, showsImport: true) {
                    importing = true
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("alarm.cancel") {
                        preview.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("alarms.done") {
                        preview.stop()
                        onUse(soundID)
                        dismiss()
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mp3, .wav, .aiff]) { result in
                if case let .success(url) = result {
                    trimFile = ImportedAudio(url: url)
                }
            }
            .sheet(item: $trimFile) { file in
                TrimSoundView(source: file.url) { window, name in
                    Task {
                        if let id = await model.importSound(source: file.url, window: window, name: name) {
                            soundID = id
                            if let url = SoundFiles.previewURL(for: id, customSounds: model.customSounds) {
                                preview.play(id: id, url: url)
                            }
                        }
                    }
                }
            }
            .onDisappear { preview.stop() }
        }
    }
}
