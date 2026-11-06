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

    /// TestFlight and App Review: Shoebox Plus is free, no purchase needed (decided November 5). True only when StoreKit
    /// has verified that this install came from the App Store sandbox; never on the App Store, never from Xcode's local
    /// StoreKit file. The same build promoted to the App Store reads Production, so this turns itself off at launch.
    private(set) static var freeInBeta = false

    /// Asks StoreKit which store this build came from. Never asks the person to sign in (that is `refresh`).
    /// November 5: on a tester's phone `AppTransaction.shared` gave no answer, so Email never showed. The receipt's file
    /// name is the fallback: TestFlight and review builds carry `sandboxReceipt`. It only shows the Email screen; what
    /// the relay accepts still comes from Apple's signed proof.
    static func checkStore() async {
        if receiptSaysSandbox { inSandbox = true }
        guard let result = await appTransaction(refresh: false) else { return }
        switch result {
        case .verified(let t): inSandbox = t.environment != .production; freeInBeta = t.environment == .sandbox
        case .unverified(let t, _): inSandbox = t.environment != .production || receiptSaysSandbox; freeInBeta = false
        }
    }

    /// TestFlight and App Review installs carry a receipt named `sandboxReceipt`; the App Store's is `receipt`.
    static var receiptSaysSandbox: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// The app transaction, tried twice. With `refresh` (only after the person taps Get address) StoreKit is asked to
    /// fetch a fresh one from Apple, which may ask them to sign in to their Apple Account.
    private static func appTransaction(refresh: Bool) async -> VerificationResult<AppTransaction>? {
        if let r = try? await AppTransaction.shared { return r }
        try? await Task.sleep(for: .seconds(1))
        if let r = try? await AppTransaction.shared { return r }
        guard refresh else { return nil }
        return try? await AppTransaction.refresh()
    }

    /// StoreKit's signed app transaction, sent to the relay as proof of a TestFlight or review install. Nil anywhere
    /// else. The relay checks it on its own (Apple's chain, the bundle, Sandbox only) and limits one to five phones.
    static func betaProof(refresh: Bool = false) async -> String? {
        guard let result = await appTransaction(refresh: refresh && inSandbox), case .verified(let t) = result, t.environment == .sandbox else { return nil }
        freeInBeta = true
        return result.jwsRepresentation
    }

    /// What the relay is shown to open an address: a real purchase when there is one, else a tester's install.
    enum Access: Equatable {
        case purchase(String)
        case beta(String)
        case code(String)

        /// The request field it goes in: `purchase`, `beta` or `code`.
        var field: (key: String, value: String) {
            switch self {
            case .purchase(let jws): ("purchase", jws)
            case .beta(let jws): ("beta", jws)
            case .code(let code): ("code", code)
            }
        }
    }

    /// A real purchase first. Then a tester code, when this phone was given one (it needs nothing from Apple and never
    /// asks the tester to sign in). Then the TestFlight install itself.
    static func access(refresh: Bool = false) async -> Access? {
        if let jws = await proof() { return .purchase(jws) }
        if let code = MailboxKeys.testerCode() { return .code(code) }
        if let jws = await betaProof(refresh: refresh) { return .beta(jws) }
        return nil
    }

    /// Has this install been open for a week? A phone that already has an address is past it, and so is a review or
    /// TestFlight build.
    static func isOffered(now: Date = Date(), firstOpened: Date? = Prefs.firstOpened, hasAddress: Bool = Prefs.inboxAddress != nil, sandbox: Bool? = nil) -> Bool {
        // `sandbox` nil means this build's own answer (a default argument can't read a main-actor value).
        if hasAddress || (sandbox ?? inSandbox) { return true }
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

    /// Settings › Restore purchases: asks the App Store to sync, then looks again. A tester always has access.
    static func restore() async -> Bool {
        try? await AppStore.sync()
        return await access() != nil
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
