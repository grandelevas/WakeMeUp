import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            AlarmListView()
                .tabItem { Label("tab.alarms", systemImage: "alarm.fill") }
                .tag(AppTab.alarms)
            SharingView()
                .tabItem { Label("tab.sharing", systemImage: "person.2.fill") }
                .tag(AppTab.sharing)
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
        .task { await model.start() }
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
