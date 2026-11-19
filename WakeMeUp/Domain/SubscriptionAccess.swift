import Foundation

enum PaywallMode: Equatable {
    /// An active subscription. The app is open.
    case none
    /// No subscription yet and no alarms saved. The app stays on the paywall.
    case subscribe
    /// The subscription lapsed, but alarms already on the phone keep ringing.
    case renew
}

enum PaywallPolicy {
    static func mode(hasActiveEntitlement: Bool, hasExistingAlarms: Bool) -> PaywallMode {
        if hasActiveEntitlement { return .none }
        return hasExistingAlarms ? .renew : .subscribe
    }
}
