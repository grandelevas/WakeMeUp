import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var whatsNew: ReleaseNote?
    @State private var showErrorDetail = false
    @State private var errorDetail = ""

    var body: some View {
        @Bindable var model = model
        MainTabPager(selection: $model.selectedTab)
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

private struct MainTabPager: View {
    @Environment(\.appAccent) private var appAccent
    @Binding var selection: AppTab
    @State private var edgeDrag: CGFloat = 0
    @State private var trackingEdge = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width.isFinite ? geo.size.width : 0
            let height = geo.size.height.isFinite ? geo.size.height : 0
            HStack(spacing: 0) {
                AlarmListView().frame(width: width, height: height)
                SharingView().frame(width: width, height: height)
                AchievementsView().frame(width: width, height: height)
            }
            .offset(x: -CGFloat(selection.tabIndex) * width + edgeDrag)
            .frame(width: width, height: height, alignment: .leading)
            .clipped()
            .simultaneousGesture(edgeSwipe(width: width))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.displayOrder, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: symbol(tab))
                            .font(.system(size: 22))
                        Text(title(tab))
                            .font(.caption2)
                    }
                    .foregroundStyle(selection == tab ? appAccent : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .background(.bar)
    }

    private func edgeSwipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                let atEdge = value.startLocation.x <= TabEdgeSwipe.edgeInset
                    || value.startLocation.x >= width - TabEdgeSwipe.edgeInset
                if !trackingEdge {
                    guard atEdge else { return }
                    trackingEdge = true
                }
                edgeDrag = rubberBand(value.translation.width, width: width)
            }
            .onEnded { value in
                guard trackingEdge else { return }
                let direction = TabEdgeSwipe.direction(
                    startX: value.startLocation.x,
                    translationX: value.translation.width,
                    translationY: value.translation.height,
                    width: width
                )
                trackingEdge = false
                withAnimation(.easeInOut(duration: 0.28)) {
                    edgeDrag = 0
                    if let direction {
                        selection = selection.shifted(direction)
                    }
                }
            }
    }

    private func rubberBand(_ translation: CGFloat, width: CGFloat) -> CGFloat {
        let index = selection.tabIndex
        let last = AppTab.displayOrder.count - 1
        if index == 0, translation > 0 { return translation * 0.25 }
        if index == last, translation < 0 { return translation * 0.25 }
        let limit = width * 0.85
        return min(max(translation, -limit), limit)
    }

    private func symbol(_ tab: AppTab) -> String {
        switch tab {
        case .alarms: "alarm.fill"
        case .sharing: "person.2.fill"
        case .achievements: "trophy.fill"
        }
    }

    private func title(_ tab: AppTab) -> LocalizedStringKey {
        switch tab {
        case .alarms: "tab.alarms"
        case .sharing: "tab.sharing"
        case .achievements: "tab.achievements"
        }
    }
}
