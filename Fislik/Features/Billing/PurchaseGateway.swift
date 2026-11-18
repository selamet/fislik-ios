import Foundation
import StoreKit

/// A transaction signed by the App Store, plus the way to mark it finished.
struct SignedTransaction: Sendable {
    /// StoreKit 2 JWS; the API verifies it itself.
    let jws: String
    let finish: @Sendable () async -> Void
}

enum StorePurchaseResult: Sendable {
    case purchased(SignedTransaction)
    /// Waiting for approval (Ask to Buy, SCA); arrives later through `updates()`.
    case pending
    case cancelled
}

enum PurchaseError: Error, Equatable {
    case productUnavailable
    /// StoreKit could not verify the transaction on the device.
    case unverified
}

/// The App Store, behind a seam so the purchase logic can be tested.
protocol PurchaseGateway: Sendable {
    /// Localized display prices of the products the App Store knows.
    func prices(for productIds: [String]) async -> [String: String]
    func purchase(productId: String) async throws -> StorePurchaseResult
    /// Subscriptions the signed-in Apple account currently holds.
    func entitlements() async -> [SignedTransaction]
    /// Forces a refresh from the App Store ("Restore purchases").
    func sync() async throws
    /// Transactions that complete outside a purchase call.
    func updates() -> AsyncStream<SignedTransaction>
}

struct AppStoreGateway: PurchaseGateway {
    func prices(for productIds: [String]) async -> [String: String] {
        guard !productIds.isEmpty, let products = try? await Product.products(for: productIds) else { return [:] }
        return Dictionary(products.map { ($0.id, $0.displayPrice) }, uniquingKeysWith: { first, _ in first })
    }

    func purchase(productId: String) async throws -> StorePurchaseResult {
        guard let product = try await Product.products(for: [productId]).first else {
            throw PurchaseError.productUnavailable
        }
        switch try await product.purchase() {
        case .success(let verification):
            guard let signed = Self.signed(verification) else { throw PurchaseError.unverified }
            return .purchased(signed)
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func entitlements() async -> [SignedTransaction] {
        var result: [SignedTransaction] = []
        for await verification in Transaction.currentEntitlements {
            if let signed = Self.signed(verification) { result.append(signed) }
        }
        return result
    }

    func sync() async throws {
        try await AppStore.sync()
    }

    func updates() -> AsyncStream<SignedTransaction> {
        AsyncStream { continuation in
            let task = Task {
                for await verification in Transaction.updates {
                    if let signed = Self.signed(verification) { continuation.yield(signed) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func signed(_ verification: VerificationResult<Transaction>) -> SignedTransaction? {
        guard case .verified(let transaction) = verification, transaction.productType == .autoRenewable else {
            return nil
        }
        return SignedTransaction(jws: verification.jwsRepresentation) { await transaction.finish() }
    }
}
