import Observation
import StoreKit
import UIKit

/// The one purchase: Big Birdhouse, bought once, restorable (Jackson: option A,
/// Inbox chirp-2-0-revenue, then "softer", chirp-2-0-revenue-shape;
/// docs/proposals/revenue-2.0.md). What it adds is ChirpCore `BigBirdhouse`:
/// birdhouses you start past 4 birds, and every bird color and chirp. Joiners
/// never pay, and carrying others' messages is free for everyone.
///
/// Ported from Crease Cracker's Store (the studio's shape for one unlock).
@MainActor
@Observable
final class Store {
    static let productID = "com.jacksonmsanger.chirpchirp.bigflock"

    enum Status: Equatable {
        case idle, loading, purchasing, restoring
        case failed(String)
        case restored
    }

    enum Words {
        static let unavailable = "The App Store is not answering. Try again in a minute."
        static let unverified = "The App Store could not confirm the purchase. You have not been charged twice; try Restore."
        static let failed = "The purchase did not go through. Nothing was charged."
        static let nothingToRestore = "No Big Birdhouse purchase was found for this Apple Account."
    }

    private(set) var product: Product?
    private(set) var owns = false
    private(set) var status: Status = .idle
    /// The App Store has answered at least once (owned or not).
    private(set) var checked = false
    /// `-bigBirdhouse` pretends the purchase is made (UI tests and screenshots).
    @ObservationIgnored var forceOwned = ProcessInfo.processInfo.arguments.contains("-bigBirdhouse")

    @ObservationIgnored private var updates: Task<Void, Never>?

    var unlocked: Bool { owns || forceOwned }

    /// Reads what is owned and listens for changes. Shows nothing and asks
    /// nothing; the product's price is fetched only to show it.
    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task {
            await refresh()
            await loadProduct()
        }
    }

    func loadProduct() async {
        guard product == nil else { return }
        status = .loading
        do {
            product = try await Product.products(for: [Self.productID]).first
            status = product == nil ? .failed(Words.unavailable) : .idle
        } catch {
            status = .failed(Words.unavailable)
        }
    }

    func buy() async {
        if product == nil { await loadProduct() }
        guard let product else {
            status = .failed(Words.unavailable)
            return
        }
        status = .purchasing
        do {
            // In the app's window scene: iOS 27 logs "could not get
            // confirmation scene ID" for a bare purchase() (Crease Cracker).
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            let result = if let scene { try await product.purchase(confirmIn: scene) } else { try await product.purchase() }
            switch result {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refresh()
                // The verified purchase is proof enough: the entitlement list
                // can lag a purchase just made.
                if transaction.productID == Self.productID, transaction.revocationDate == nil { owns = true }
                status = .idle
            case .success(.unverified):
                status = .failed(Words.unverified)
            case .pending, .userCancelled:
                status = .idle
            @unknown default:
                status = .idle
            }
        } catch {
            status = .failed(Words.failed)
        }
    }

    func restore() async {
        status = .restoring
        do {
            try await AppStore.sync()
            await refresh()
            status = owns ? .restored : .failed(Words.nothingToRestore)
        } catch {
            // Backing out of the sign in sheet lands here too.
            status = .idle
        }
    }

    /// What the App Store says this person owns. A refund takes it away.
    func refresh() async {
        var found = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                found = true
            }
        }
        if !found, let latest = await Transaction.latest(for: Self.productID),
           case .verified(let transaction) = latest, transaction.revocationDate == nil {
            found = true
        }
        owns = found
        checked = true
    }
}
