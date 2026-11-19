import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.appAccent) private var appAccent
    let mode: PaywallMode
    var showAchievements: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Wakito")
                    .font(.largeTitle.weight(.bold))
                Text(mode == .renew ? "paywall.renew" : "paywall.subscribe")
                    .font(.title3)
                Text(priceLine)
                    .font(.headline)
                Text("paywall.autorenew")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("paywall.charity")
                    .font(.footnote)
                Button("paywall.achievements") { showAchievements() }
                Button(mode == .renew ? "paywall.renewButton" : "paywall.subscribeButton") {
                    Task { await subscriptions.purchase() }
                }
                .buttonStyle(.borderedProminent)
                .tint(appAccent)
                Button("paywall.restore") {
                    Task { await subscriptions.restore() }
                }
                if let purchaseError = subscriptions.purchaseError {
                    Text(purchaseError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    Link("paywall.terms", destination: SubscriptionLinks.termsOfUse)
                    if let privacy = SubscriptionLinks.privacyPolicy {
                        Link("paywall.privacy", destination: privacy)
                    }
                }
                .font(.footnote)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(.background)
        .accessibilityIdentifier("paywall")
    }

    private var priceLine: String {
        if let product = subscriptions.product {
            let period = product.subscription?.subscriptionPeriod
            let unit = period.map(Self.periodName) ?? String(localized: "paywall.year")
            return "\(product.displayPrice) / \(unit)"
        }
        return String(localized: "paywall.priceFallback")
    }

    private static func periodName(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .year where period.value == 1: String(localized: "paywall.year")
        default: "\(period.value)"
        }
    }
}

enum SubscriptionLinks {
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static var privacyPolicy: URL? {
        let value = AppConfig.privacyPolicyURL
        guard let url = URL(string: value), url.scheme == "https" else { return nil }
        return url
    }
}
