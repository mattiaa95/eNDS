//
//  PurchaseManager.swift
//  eNDS
//
//  Ported from iGBA (GBA-Emu repo,
//  App/SwiftUI/Common/PurchaseManager/PurchaseManager.swift). StoreKit 2
//  product loading + purchase/restore, unchanged apart from eNDS's own
//  product IDs. Owns the revocation-safe entitlement bookkeeping alongside
//  `EntitlementManager` (see that file's header for the bug this guards).
//

import Foundation
import StoreKit

@MainActor
class PurchaseManager: ObservableObject {

    private let productIds: [String]
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs = Set<String>()
    private var transactionListenerTask: Task<Void, Never>?

    public let entitlementManager: EntitlementManager

    init(entitlementManager: EntitlementManager) {
        self.entitlementManager = entitlementManager
        self.productIds = EntitlementManager.productIDs

        Task {
            await self.loadProducts()
            await self.updatePurchasedProducts()
        }

        listenForTransactionUpdates()
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: productIds)
            self.products = storeProducts
        } catch {
            #if DEBUG
            print("Failed to load products: \(error)")
            #endif
        }
    }

    /// Returns the raw StoreKit result so callers can tell `.pending`
    /// (Ask to Buy) apart from a cancel — both used to be silent.
    @discardableResult
    func purchase(_ product: Product) async throws -> Product.PurchaseResult {
        let result = try await product.purchase()
        if case .success(let verification) = result {
            switch verification {
            case .verified(let transaction):
                await self.handlePurchasedTransaction(transaction)
            case .unverified(_, let error):
                throw error
            }
        }
        return result
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await self.updatePurchasedProducts()
    }

    func fetchProduct(withId id: String) async -> Product? {
        return products.first { $0.id == id }
    }

    private func updatePurchasedProducts() async {
        var verifiedIDs = Set<String>()
        var sawAnyTransaction = false
        for await result in Transaction.currentEntitlements {
            // Un reembolso deja la transaccion en `currentEntitlements` con la fecha
            // de revocacion puesta: sin esto, quien pidio la devolucion conserva Pro.
            if case .verified(let revocationCheck) = result,
               revocationCheck.revocationDate != nil { continue }
            sawAnyTransaction = true
            switch result {
            case .verified(let transaction):
                if transaction.revocationDate == nil {
                    verifiedIDs.insert(transaction.productID)
                }
            case .unverified(_, let error):
                NSLog("[PurchaseManager] Unverified entitlement: %@", error.localizedDescription)
            }
        }

        // Same rule as EntitlementManager.refreshEntitlements: an empty result
        // can mean "never paid" or "could not reach the App Store", and the two
        // must not be treated alike. Never revoke PRO on silence — only on a
        // readable answer that genuinely lacks a live entitlement (a lapsed or
        // refunded transaction that `latest(for:)` can still show us counts).
        if !sawAnyTransaction && self.entitlementManager.hasPro,
           await EntitlementManager.hasLapsedTransaction() == false {
            return
        }

        self.purchasedProductIDs = verifiedIDs
        self.entitlementManager.updateProStatus(isPro: !verifiedIDs.isEmpty)
    }

    private func handlePurchasedTransaction(_ transaction: StoreKit.Transaction) async {
        self.purchasedProductIDs.insert(transaction.productID)
        self.entitlementManager.updateProStatus(isPro: true)
        await transaction.finish()
    }

    private func listenForTransactionUpdates() {
        transactionListenerTask = Task {
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    if transaction.revocationDate != nil {
                        self.purchasedProductIDs.remove(transaction.productID)
                        self.entitlementManager.updateProStatus(isPro: !self.purchasedProductIDs.isEmpty)
                        await transaction.finish()
                    } else {
                        await self.handlePurchasedTransaction(transaction)
                    }
                case .unverified(let transaction, _):
                    await transaction.finish()
                }
            }
        }
    }
}
