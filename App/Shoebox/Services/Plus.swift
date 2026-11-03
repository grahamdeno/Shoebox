import Foundation
import StoreKit

/// Shoebox Plus: one non-consumable in-app purchase that adds the email address (SPEC 9; design:
/// docs/design/identity-and-sealed-mail.md, M-1). The phone never decides on its own that someone has Plus:
/// it asks StoreKit, and it sends StoreKit's signed proof (the transaction's JWS) to the relay, which checks it.
@MainActor
enum Plus {
    /// A product id can never be reused or changed once it exists in App Store Connect.
    static let productID = "com.grahamdeno.shoebox.plus"

    /// Plus is offered a week after the first run, never in it (SPEC 9), except in the sandbox (`inSandbox`).
    static let offerAfter: TimeInterval = 7 * 86_400

    /// Builds from TestFlight, App Review and Xcode run in the App Store sandbox. There Plus is offered at once, because a
    /// reviewer or a tester can't wait a week. Customers on the App Store still see it after 7 days. False until checked.
    private(set) static var inSandbox = false

    /// Asks StoreKit which store this build came from. Never asks the person to sign in (that is `refresh`, not used).
    static func checkStore() async {
        guard let result = try? await AppTransaction.shared else { return }
        switch result {
        case .verified(let t), .unverified(let t, _): inSandbox = t.environment != .production
        }
    }

    /// Has this install been open for a week? A phone that already has an address is past it, and so is a review or
    /// TestFlight build.
    static func isOffered(now: Date = Date(), firstOpened: Date? = Prefs.firstOpened, hasAddress: Bool = Prefs.inboxAddress != nil, sandbox: Bool = Plus.inSandbox) -> Bool {
        if hasAddress || sandbox { return true }
        guard let firstOpened else { return false }
        return now.timeIntervalSince(firstOpened) >= offerAfter
    }

    /// Records the first run. An install already in use before this was recorded counts as old.
    static func noteFirstOpen() {
        if Prefs.firstOpened == nil { Prefs.firstOpened = Prefs.onboarded ? .distantPast : Date() }
    }

    static func product() async -> Product? {
        try? await Product.products(for: [productID]).first
    }

    /// The price as the App Store shows it ("$9.99"), or nil if the product can't be loaded.
    static func price() async -> String? {
        await product()?.displayPrice
    }

    /// StoreKit's signed proof of the purchase, or nil when this Apple Account has not bought Plus (or it was refunded).
    /// Only a transaction StoreKit itself has verified counts.
    static func proof() async -> String? {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == productID, transaction.revocationDate == nil else { continue }
            return result.jwsRepresentation
        }
        return nil
    }

    enum Outcome: Equatable {
        case bought
        case cancelled
        case pending          // Ask to Buy, or a payment still going through
        case failed
    }

    static func buy() async -> Outcome {
        guard let product = await product() else { return .failed }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return .failed }
                await transaction.finish()
                return .bought
            case .userCancelled: return .cancelled
            case .pending: return .pending
            @unknown default: return .failed
            }
        } catch {
            return .failed
        }
    }

    /// Settings › Restore purchases: asks the App Store to sync, then looks again.
    static func restore() async -> Bool {
        try? await AppStore.sync()
        return await proof() != nil
    }

    private static var listening = false

    /// A purchase that finishes outside the app (Ask to Buy approved, a purchase made on another device) arrives here.
    static func startListening() {
        guard !listening else { return }
        listening = true
        Task.detached {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
            }
        }
    }
}
