import SwiftUI

struct ReleaseNotesView: View {
    var notes: ReleaseNotesDocument = .bundled()
    var languageCode: String = Locale.current.language.languageCode?.identifier ?? "en"

    var body: some View {
        List {
            ForEach(notes.newestFirst) { note in
                Section {
                    ForEach(note.bullets(for: languageCode), id: \.self) { line in
                        Text(line)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.heading)
                        Text(note.date.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }
        }
        .navigationTitle("settings.history")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WhatsNewSheet: View {
    var note: ReleaseNote
    var languageCode: String = Locale.current.language.languageCode?.identifier ?? "en"
    var dismiss: () -> Void

    var body: some View {
        NavigationStack {
            List(note.bullets(for: languageCode), id: \.self) { line in
                Text(line)
            }
            .navigationTitle("settings.whatsNew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("alarms.done", action: dismiss)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
