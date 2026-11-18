import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Text("settings.tagline")
                    .font(.title3.weight(.semibold))
                Text(version)
                    .foregroundStyle(.secondary)
            }
            Section("settings.alarmAccess") {
                LabeledContent("settings.alarmAccess", value: accessText)
                if model.authorization != .authorized {
                    Button("settings.allow") {
                        Task { await model.allowAlarms() }
                    }
                    Button("settings.open") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            Section {
                LabeledContent(
                    "settings.notifications",
                    value: model.notificationAllowed ? String(localized: "settings.alarmAccess.authorized") : String(localized: "settings.alarmAccess.denied")
                )
                Text("settings.notifications.help")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("settings.backend") {
                Text(model.usesCloudKit ? "settings.backend.cloudkit" : "settings.backend.preview")
            }
            Section("settings.about") {
                Text("settings.about.body")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("settings.privacy") {
                Text("settings.privacy.body")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("settings.title")
        .accessibilityIdentifier("settings-screen")
    }

    private var accessText: String {
        switch model.authorization {
        case .authorized: String(localized: "settings.alarmAccess.authorized")
        case .denied: String(localized: "settings.alarmAccess.denied")
        case .notDetermined: String(localized: "settings.alarmAccess.notDetermined")
        case .unknown: String(localized: "settings.alarmAccess.unknown")
        }
    }

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(String(localized: "settings.version")) \(short) (\(build))"
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
