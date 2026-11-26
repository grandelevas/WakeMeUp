import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var whatsNew: ReleaseNote?
    @State private var showWelcome = false
    @State private var showErrorDetail = false
    @State private var errorDetail = ""

    var body: some View {
        @Bindable var model = model
        MainTabPager(selection: $model.selectedTab)
        .readableWidth()
        .sheet(item: liveEditor) { draft in
            AlarmEditorView(draft: draft)
                .readableWidth()
        }
        .fullScreenCover(item: demoEditor) { draft in
            AlarmEditorView(draft: draft)
                .readableWidth()
        }
        .fullScreenCover(item: ringingAlarm) { alarm in
            RingingView(alarm: alarm)
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
            model.reconcileRingingWithSystem()
            Task { await model.refreshRemote() }
        }
        .task { await model.start() }
        .task {
            showWelcome = OnboardingStore.shouldShowWelcome(
                demo: model.suppressPermissionBanner,
                defaults: .standard
            )
            if !showWelcome {
                presentWhatsNewIfNeeded()
            }
        }
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeView {
                OnboardingStore.markWelcomeSeen(defaults: .standard)
                showWelcome = false
            }
        }
        .sheet(item: $whatsNew) { note in
            WhatsNewSheet(note: note) {
                ReleaseNotesPrompt.markSeen(currentBuild: currentBuild, defaults: .standard)
                whatsNew = nil
            }
        }
    }

    /// Presents only when there is an alarm to draw. An id with no alarm used to
    /// leave an empty black cover that could not be dismissed.
    /// Demo captures need the editor edge to edge. A sheet would leave the list peeking through.
    private var liveEditor: Binding<AlarmDraft?> {
        Binding(
            get: { LaunchConfiguration.seedDemo ? nil : model.editor },
            set: { model.editor = $0 }
        )
    }

    private var demoEditor: Binding<AlarmDraft?> {
        Binding(
            get: { LaunchConfiguration.seedDemo ? model.editor : nil },
            set: { if $0 == nil { model.editor = nil } }
        )
    }

    private var ringingAlarm: Binding<Alarm?> {
        Binding(
            get: { model.ringingAlarm },
            set: { if $0 == nil { model.dismissRinging() } }
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
        VStack(spacing: 0) {
            GeometryReader { geo in
                let width = geo.size.width.isFinite && geo.size.width > 1 ? geo.size.width : 0
                let height = geo.size.height.isFinite && geo.size.height > 1 ? geo.size.height : 0
                HStack(spacing: 0) {
                    ForEach(AppTab.displayOrder, id: \.self) { tab in
                        page(tab)
                            .frame(width: width, height: height)
                            .accessibilityHidden(tab != selection)
                            .allowsHitTesting(tab == selection)
                    }
                }
                .offset(x: width > 0 ? -CGFloat(selection.tabIndex) * width + edgeDrag : 0)
                .frame(width: width, height: height, alignment: .leading)
                .clipped()
                .simultaneousGesture(edgeSwipe(width: width))
            }
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
                        tabIcon(tab)
                        Text(title(tab))
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
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
        .background {
            Rectangle()
                .fill(.bar)
                .ignoresSafeArea(edges: .bottom)
        }
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

    @ViewBuilder
    private func page(_ tab: AppTab) -> some View {
        switch tab {
        case .nap: NapView()
        case .alarms: AlarmListView()
        case .sharing: SharingView()
        case .calendar: CalendarView()
        case .achievements: AchievementsView()
        }
    }

    @ViewBuilder
    private func tabIcon(_ tab: AppTab) -> some View {
        if tab == .nap {
            Text("😴")
                .font(.system(size: 22))
        } else {
            Image(systemName: symbol(tab))
                .font(.system(size: 22))
        }
    }

    private func symbol(_ tab: AppTab) -> String {
        switch tab {
        case .nap: "moon.zzz.fill"
        case .alarms: "alarm.fill"
        case .sharing: "person.2.fill"
        case .calendar: "calendar"
        case .achievements: "trophy.fill"
        }
    }

    private func title(_ tab: AppTab) -> LocalizedStringKey {
        switch tab {
        case .nap: "tab.nap"
        case .alarms: "tab.alarms"
        case .sharing: "tab.sharing"
        case .calendar: "tab.calendar"
        case .achievements: "tab.achievements"
        }
    }
}
