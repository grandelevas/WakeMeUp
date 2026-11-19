import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingAchievements = false

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
        .overlay {
            if paywallMode != .none, model.ringingAlarmID == nil {
                PaywallView(mode: paywallMode) { showingAchievements = true }
            }
        }
        .sheet(isPresented: $showingAchievements) {
            NavigationStack {
                AchievementsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("alarms.done") { showingAchievements = false }
                        }
                    }
            }
        }
        .sheet(item: $model.editor) { draft in
            AlarmEditorView(draft: draft)
                .readableWidth()
        }
        .fullScreenCover(isPresented: ringingPresented) {
            if let alarm = model.ringingAlarm {
                RingingView(alarm: alarm)
            }
        }
        .sheet(item: $model.preparedShare) { prepared in
            CloudShareSheet(share: prepared.share, containerID: prepared.containerID)
        }
        .sheet(isPresented: sharePresented) {
            if let url = model.shareURL {
                ActivityShareSheet(items: [url])
            }
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
    }

    private var paywallMode: PaywallMode {
        if LaunchConfiguration.seedDemo { return .none }
        return PaywallPolicy.mode(
            hasActiveEntitlement: subscriptions.isEntitled,
            hasExistingAlarms: !model.library.alarms.isEmpty
        )
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

    private var sharePresented: Binding<Bool> {
        Binding(
            get: { model.shareURL != nil },
            set: { if !$0 { model.shareURL = nil } }
        )
    }
}
