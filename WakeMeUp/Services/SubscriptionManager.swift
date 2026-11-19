import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class SubscriptionManager {
    static let productID = "com.grandelevas.wakemeup.yearly"

    var product: Product?
    var isEntitled = false
    var purchaseError: String?

    func start() async {
        await refreshEntitlement()
        await loadProduct()
        Task { await observeTransactions() }
    }

    func loadProduct() async {
        product = try? await Product.products(for: [Self.productID]).first
    }

    func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.productID, transaction.revocationDate == nil {
                entitled = true
            }
        }
        isEntitled = entitled
    }

    func purchase() async {
        purchaseError = nil
        if product == nil { await loadProduct() }
        guard let product else {
            purchaseError = String(localized: "paywall.unavailable")
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                } else {
                    purchaseError = String(localized: "paywall.unverified")
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restore() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !isEntitled {
                purchaseError = String(localized: "paywall.nothingToRestore")
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func observeTransactions() async {
        for await update in Transaction.updates {
            if case .verified(let transaction) = update {
                await transaction.finish()
            }
            await refreshEntitlement()
        }
    }
}
