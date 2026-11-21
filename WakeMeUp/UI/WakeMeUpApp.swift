import BackgroundTasks
import CloudKit
import os
import SwiftUI
import UIKit
import UserNotifications

@main
struct WakeMeUpApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var appearance = AppearanceSettings.load()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(appearance)
                .environment(\.appAccent, appearance.accent.color)
                .tint(appearance.accent.color)
                .preferredColorScheme(appearance.theme.colorScheme)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if AppConfig.activatesCloudKit {
            application.registerForRemoteNotifications()
            RemoteRefresh.register()
            RemoteRefresh.schedule()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ShareSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        ShareAcceptance.enqueue(metadata)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        if let model = await MainActor.run(body: { AppRuntime.model }) {
            await model.refreshRemote()
        }
        return .newData
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if let model = await MainActor.run(body: { AppRuntime.model }) {
            await model.handleNotification(response)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

/// SwiftUI's scene does not call `UIApplicationDelegate.userDidAcceptCloudKitShareWith`.
/// The system "Retrieving" screen waits until this scene method runs.
final class ShareSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            ShareAcceptance.enqueue(metadata)
        }
        for context in connectionOptions.urlContexts {
            ShareAcceptance.enqueue(url: context.url)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        ShareAcceptance.enqueue(cloudKitShareMetadata)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            ShareAcceptance.enqueue(url: context.url)
        }
    }
}

enum ShareAcceptance {
    private static let cloudLog = Logger(subsystem: "com.grandelevas.wakemeup", category: "CloudKit")

    static func enqueue(_ metadata: CKShare.Metadata) {
        let root = metadata.hierarchicalRootRecordID
        cloudLog.error("userDidAcceptCloudKitShareWith root=\(root?.recordName ?? "nil", privacy: .public) owner=\(root?.zoneID.ownerName ?? "nil", privacy: .public)")
        Task { @MainActor in
            await AppRuntime.acceptWhenReady(metadata)
        }
    }

    static func enqueue(url: URL) {
        guard InviteLinkPolicy.isCloudShare(url) else { return }
        Task { @MainActor in
            await AppRuntime.acceptURLWhenReady(url)
        }
    }
}

enum RemoteRefresh {
    static let taskID = "com.grandelevas.wakemeup.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { return }
            let work = Task {
                if let model = await MainActor.run(body: { AppRuntime.model }) {
                    await model.refreshRemote()
                }
            }
            refresh.expirationHandler = { work.cancel() }
            Task {
                _ = await work.value
                refresh.setTaskCompleted(success: !work.isCancelled)
                schedule()
            }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
