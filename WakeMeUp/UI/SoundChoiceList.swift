import SwiftUI

struct SoundChoiceList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccent) private var appAccent
    @Binding var soundID: String
    var preview: SoundPreviewPlayer
    var showsImport: Bool = false
    var onImport: () -> Void = {}
    @State private var renaming: CustomSound?
    @State private var renameText = ""

    var body: some View {
        Section("alarm.sound") {
            ForEach(SoundCatalog.bundled) { sound in
                row(id: sound.id, title: Text(LocalizedStringKey(sound.localizationKey)), custom: nil)
            }
        }
        .alert("sound.rename", isPresented: renamePresented) {
            TextField("sound.rename.placeholder", text: $renameText)
            Button("alarm.save") {
                if let renaming {
                    model.renameCustomSound(renaming.id, to: renameText)
                }
                self.renaming = nil
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("alarm.cancel", role: .cancel) { renaming = nil }
        }
        if !voiceRecordings.isEmpty {
            Section("sound.voice.mine") {
                ForEach(voiceRecordings) { sound in
                    row(id: sound.id, title: Text(sound.displayName), custom: sound)
                }
            }
        }
        if showsImport || !importedSounds.isEmpty {
            Section("sound.mine") {
                ForEach(importedSounds) { sound in
                    row(id: sound.id, title: Text(sound.displayName), custom: sound)
                }
                if showsImport {
                    Button("sound.import", action: onImport)
                }
            }
        }
    }

    private var voiceRecordings: [CustomSound] {
        model.customSounds.filter { SoundLibraryEdit.isVoiceRecording($0.id) }
    }

    private var importedSounds: [CustomSound] {
        model.customSounds.filter { !SoundLibraryEdit.isVoiceRecording($0.id) }
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func row(id: String, title: Text, custom: CustomSound?) -> some View {
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
        .contextMenu {
            if let custom {
                Button("sound.rename", systemImage: "pencil") {
                    renameText = custom.displayName
                    renaming = custom
                }
                Button("sound.delete", systemImage: "trash", role: .destructive) {
                    delete(custom)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let custom {
                Button("sound.delete", role: .destructive) {
                    delete(custom)
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let custom {
                Button("sound.rename") {
                    renameText = custom.displayName
                    renaming = custom
                }
                .tint(.indigo)
            }
        }
    }

    private func delete(_ sound: CustomSound) {
        if soundID == sound.id {
            soundID = SoundCatalog.defaultID
        }
        if preview.isPlaying(sound.id) {
            preview.stop()
        }
        model.deleteCustomSound(sound.id)
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
            .soundFileImporter(isPresented: $importing) { id in
                soundID = id
                if let url = SoundFiles.previewURL(for: id, customSounds: model.customSounds) {
                    preview.play(id: id, url: url)
                }
            }
            .onDisappear { preview.stop() }
        }
    }
}
