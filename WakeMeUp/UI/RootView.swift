import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var whatsNew: ReleaseNote?

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            AlarmListView()
                .tabItem { Label("tab.alarms", systemImage: "alarm.fill") }
                .tag(AppTab.alarms)
            SharingView()
                .tabItem { Label("tab.sharing", systemImage: "person.2.fill") }
                .tag(AppTab.sharing)
            AchievementsView()
                .tabItem { Label("tab.achievements", systemImage: "trophy.fill") }
                .tag(AppTab.achievements)
        }
        .readableWidth()
        .sheet(item: $model.editor) { draft in
            AlarmEditorView(draft: draft)
                .readableWidth()
        }
        .fullScreenCover(isPresented: ringingPresented) {
            if let alarm = model.ringingAlarm {
                RingingView(alarm: alarm)
            }
        }
        .sheet(isPresented: sharePresented) {
            ActivityShareSheet(items: shareItems)
        }
        .alert("error.generic", isPresented: errorPresented) {
            Button("alarms.done", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
        .onOpenURL { model.handle(url: $0) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !model.suppressPermissionBanner else { return }
            Task { await model.refreshRemote() }
        }
        .task { await model.start() }
        .task { presentWhatsNewIfNeeded() }
        .sheet(item: $whatsNew) { note in
            WhatsNewSheet(note: note) {
                ReleaseNotesPrompt.markSeen(currentBuild: currentBuild, defaults: .standard)
                whatsNew = nil
            }
        }
    }

    private var ringingPresented: Binding<Bool> {
        Binding(
            get: { model.ringingAlarmID != nil },
            set: { if !$0 { model.dismissRinging() } }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )
    }

    private var shareItems: [Any] {
        var items: [Any] = []
        if !model.shareMessage.isEmpty {
            items.append(model.shareMessage)
        }
        if let url = model.shareURL {
            items.append(url)
        }
        return items
    }

    private var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    private func presentWhatsNewIfNeeded() {
        guard !model.suppressPermissionBanner else { return }
        let build = currentBuild
        if ReleaseNotesPrompt.shouldShow(currentBuild: build, defaults: .standard) {
            whatsNew = ReleaseNotesDocument.bundled().newestFirst.first
            if whatsNew == nil {
                ReleaseNotesPrompt.markSeen(currentBuild: build, defaults: .standard)
            }
        } else if UserDefaults.standard.string(forKey: ReleaseNotesPrompt.storageKey) == nil {
            ReleaseNotesPrompt.markSeen(currentBuild: build, defaults: .standard)
        }
    }

    private var sharePresented: Binding<Bool> {
        Binding(
            get: { model.shareURL != nil },
            set: { if !$0 { model.shareURL = nil; model.shareMessage = "" } }
        )
    }
}
