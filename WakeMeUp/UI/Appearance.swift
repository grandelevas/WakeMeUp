import SwiftUI
import UIKit

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "settings.appearance.system"
        case .light: "settings.appearance.light"
        case .dark: "settings.appearance.dark"
        }
    }
}

enum AppAccent: String, CaseIterable, Identifiable {
    case orange
    case blue
    case green
    case purple
    case pink
    case red
    case teal
    case indigo

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .orange: Color(red: 1.0, green: 0.478, blue: 0.0)
        case .blue: Color(red: 0.0, green: 0.478, blue: 1.0)
        case .green: Color(red: 0.204, green: 0.780, blue: 0.349)
        case .purple: Color(red: 0.686, green: 0.322, blue: 0.871)
        case .pink: Color(red: 1.0, green: 0.176, blue: 0.333)
        case .red: Color(red: 1.0, green: 0.231, blue: 0.188)
        case .teal: Color(red: 0.188, green: 0.690, blue: 0.780)
        case .indigo: Color(red: 0.345, green: 0.337, blue: 0.839)
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .orange: "settings.appearance.orange"
        case .blue: "settings.appearance.blue"
        case .green: "settings.appearance.green"
        case .purple: "settings.appearance.purple"
        case .pink: "settings.appearance.pink"
        case .red: "settings.appearance.red"
        case .teal: "settings.appearance.teal"
        case .indigo: "settings.appearance.indigo"
        }
    }
}

enum AppIconChoice: String, CaseIterable, Identifiable {
    case primary
    case dark
    case minimal
    case color

    var id: String { rawValue }

    /// Name passed to `UIApplication.setAlternateIconName`. Nil is the primary icon.
    var alternateName: String? {
        switch self {
        case .primary: nil
        case .dark: "Dark"
        case .minimal: "Minimal"
        case .color: "Color"
        }
    }

    var preview: String {
        switch self {
        case .primary: "IconPreviewPrimary"
        case .dark: "IconPreviewDark"
        case .minimal: "IconPreviewMinimal"
        case .color: "IconPreviewColor"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .primary: "settings.appearance.icon.primary"
        case .dark: "settings.appearance.icon.dark"
        case .minimal: "settings.appearance.icon.minimal"
        case .color: "settings.appearance.icon.color"
        }
    }

    static func matching(alternateName: String?) -> AppIconChoice {
        allCases.first { $0.alternateName == alternateName } ?? .primary
    }
}

struct AppearanceRecord: Equatable {
    var theme: AppTheme
    var accent: AppAccent
    var icon: AppIconChoice

    static let `default` = AppearanceRecord(theme: .system, accent: .orange, icon: .primary)

    static func load(from defaults: UserDefaults) -> AppearanceRecord {
        AppearanceRecord(
            theme: AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system,
            accent: AppAccent(rawValue: defaults.string(forKey: Keys.accent) ?? "") ?? .orange,
            icon: AppIconChoice(rawValue: defaults.string(forKey: Keys.icon) ?? "") ?? .primary
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(theme.rawValue, forKey: Keys.theme)
        defaults.set(accent.rawValue, forKey: Keys.accent)
        defaults.set(icon.rawValue, forKey: Keys.icon)
    }
}

enum AppearanceKeys {
    static let theme = "wakito.appearance.theme"
    static let accent = "wakito.appearance.accent"
    static let icon = "wakito.appearance.icon"
}

private enum Keys {
    static let theme = AppearanceKeys.theme
    static let accent = AppearanceKeys.accent
    static let icon = AppearanceKeys.icon
}

private struct AppAccentKey: EnvironmentKey {
    static let defaultValue: Color = AppAccent.orange.color
}

extension EnvironmentValues {
    var appAccent: Color {
        get { self[AppAccentKey.self] }
        set { self[AppAccentKey.self] = newValue }
    }
}

@MainActor
@Observable
final class AppearanceSettings {
    var theme: AppTheme
    var accent: AppAccent
    var icon: AppIconChoice
    var iconMessage: String?

    init(record: AppearanceRecord) {
        theme = record.theme
        accent = record.accent
        icon = record.icon
    }

    static func load() -> AppearanceSettings {
        var record = AppearanceRecord.load(from: .standard)
        if LaunchConfiguration.seedDemo {
            record.theme = .light
        }
        return AppearanceSettings(record: record)
    }

    func persist() {
        let record = AppearanceRecord(theme: theme, accent: accent, icon: icon)
        record.save(to: .standard)
        if let group = UserDefaults(suiteName: AppConfig.appGroupID) {
            record.save(to: group)
        }
    }

    func chooseIcon(_ choice: AppIconChoice) {
        guard UIApplication.shared.supportsAlternateIcons else {
            iconMessage = String(localized: "settings.appearance.icon.unavailable")
            return
        }
        UIApplication.shared.setAlternateIconName(choice.alternateName) { error in
            Task { @MainActor in
                if let error {
                    self.iconMessage = error.localizedDescription
                    return
                }
                self.icon = choice
                self.iconMessage = nil
                self.persist()
            }
        }
    }

    static var storedAccent: AppAccent {
        AppearanceRecord.load(from: .standard).accent
    }
}
