import Foundation

enum OnboardingStore {
    static let welcomeKey = "wakito.onboarding.welcomeSeen"
    static let groupTipKey = "wakito.onboarding.groupTipSeen"
    static let voiceTipKey = "wakito.onboarding.voiceTipSeen"

    static func shouldShowWelcome(demo: Bool, defaults: UserDefaults) -> Bool {
        !demo && !defaults.bool(forKey: welcomeKey)
    }

    static func markWelcomeSeen(defaults: UserDefaults) {
        defaults.set(true, forKey: welcomeKey)
    }

    static func shouldShowGroupTip(demo: Bool, defaults: UserDefaults) -> Bool {
        !demo && !defaults.bool(forKey: groupTipKey)
    }

    static func markGroupTipSeen(defaults: UserDefaults) {
        defaults.set(true, forKey: groupTipKey)
    }

    static func shouldShowVoiceTip(demo: Bool, defaults: UserDefaults) -> Bool {
        !demo && !defaults.bool(forKey: voiceTipKey)
    }

    static func markVoiceTipSeen(defaults: UserDefaults) {
        defaults.set(true, forKey: voiceTipKey)
    }

    /// The group tip waits until the welcome has already been skipped or finished.
    /// It does not appear in the same step as the welcome cards.
    static func shouldOfferGroupTip(demo: Bool, defaults: UserDefaults) -> Bool {
        shouldShowGroupTip(demo: demo, defaults: defaults)
            && !shouldShowWelcome(demo: demo, defaults: defaults)
    }
}
