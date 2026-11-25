import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(\.appAccent) private var appAccent

    var body: some View {
        Form {
            Section {
                Text("settings.tagline")
                    .font(.title3.weight(.semibold))
                Text(version)
                    .foregroundStyle(.secondary)
                NavigationLink("settings.history") {
                    ReleaseNotesView()
                }
            }
            appearanceSection
            Section("nap.length") {
                Stepper(
                    value: Binding(
                        get: { model.napMinutes },
                        set: { model.setNapMinutes($0) }
                    ),
                    in: NapSettings.minimumMinutes...NapSettings.maximumMinutes,
                    step: NapSettings.stepMinutes
                ) {
                    Text(String(format: String(localized: "nap.minutes"), model.napMinutes))
                }
                Text("nap.length.help")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("settings.alarmAccess") {
                LabeledContent("settings.alarmAccess", value: accessText)
                if model.authorization == .denied {
                    Text("settings.systemAlarm.fallback")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("settings.open") {
                        openSystemSettings()
                    }
                } else if model.authorization != .authorized {
                    Button("settings.allow") {
                        Task { await model.allowAlarms() }
                    }
                }
                if let failure = model.scheduleFailure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

    @ViewBuilder
    private var appearanceSection: some View {
        Section("settings.appearance") {
            Picker("settings.appearance.theme", selection: Binding(
                get: { appearance.theme },
                set: { theme in
                    appearance.theme = theme
                    appearance.persist()
                }
            )) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 8) {
                Text("settings.appearance.accent")
                    .font(.subheadline)
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AppAccent.allCases) { accent in
                        Button {
                            appearance.accent = accent
                            appearance.persist()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 28, height: 28)
                                if appearance.accent == accent {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(accent.title))
                        .accessibilityAddTraits(appearance.accent == accent ? .isSelected : AccessibilityTraits())
                    }
                }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("settings.appearance.icon")
                    .font(.subheadline)
                HStack(spacing: 12) {
                    ForEach(AppIconChoice.allCases) { icon in
                        Button {
                            appearance.chooseIcon(icon)
                        } label: {
                            VStack(spacing: 4) {
                                Image(icon.preview)
                                    .resizable()
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay {
                                        if appearance.icon == icon {
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(appAccent, lineWidth: 3)
                                        }
                                    }
                                Text(icon.title)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(icon.title))
                    }
                }
                if let iconMessage = appearance.iconMessage {
                    Text(iconMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var accessText: String {
        switch model.authorization {
        case .authorized: String(localized: "settings.systemAlarm.on")
        case .denied: String(localized: "settings.systemAlarm.denied")
        case .notDetermined: String(localized: "settings.systemAlarm.ask")
        case .unknown: String(localized: "settings.alarmAccess.unknown")
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
