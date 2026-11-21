import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var whatsNew: ReleaseNote?
    @State private var showErrorDetail = false
    @State private var errorDetail = ""

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
        .background {
            Color.clear
                .alert("sharing.wakeNow", isPresented: noticePresented) {
                    Button("alarms.done", role: .cancel) {}
                } message: {
                    Text(model.statusNotice ?? "")
                }
        }
        .alert("error.generic", isPresented: errorPresented) {
            if model.presentedError?.detail.isEmpty == false {
                Button("sharing.error.details") {
                    errorDetail = model.presentedError?.detail ?? ""
                    showErrorDetail = true
                }
            }
            Button("alarms.done", role: .cancel) {}
        } message: {
            Text(model.presentedError?.summary ?? "")
        }
        .sheet(isPresented: $showErrorDetail) {
            NavigationStack {
                ScrollView {
                    Text(errorDetail)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("sharing.error.details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("alarms.done") { showErrorDetail = false }
                    }
                }
            }
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

    private var noticePresented: Binding<Bool> {
        Binding(
            get: { model.statusNotice != nil },
            set: { if !$0 { model.statusNotice = nil } }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.presentedError != nil },
            set: { if !$0 { model.presentedError = nil } }
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
