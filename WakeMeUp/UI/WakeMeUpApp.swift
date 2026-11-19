import BackgroundTasks
import CloudKit
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

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task {
            guard let model = await MainActor.run(body: { AppRuntime.model }) else { return }
            await model.acceptCloudShare(metadata)
        }
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
