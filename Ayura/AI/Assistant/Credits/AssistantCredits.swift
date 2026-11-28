import StoreKit
import SwiftUI

/// Product ids for AI credits, prepared for App Store Connect (not created
/// there yet). The server's catalogue (server/assistant-backend/src/config.ts)
/// lists the same ids and the credits each grants.
enum AssistantCreditProductID {
    /// Consumable packs.
    static let small = "ayurveda.asana.yoga.credits.small"
    static let large = "ayurveda.asana.yoga.credits.large"
    static let packs = [small, large]
    /// The existing Premium plans also include monthly credits (server side).
    static let subscriptionsWithCredits = [SubscriptionProductID.premium, SubscriptionProductID.premiumYearly]
}

/// Buys credit packs and reports every credit-bearing transaction to our
/// backend, which verifies it with Apple and adds the credits once.
@MainActor
final class AssistantCreditsStore: ObservableObject {
    static let shared = AssistantCreditsStore()

    @Published private(set) var packs: [Product] = []
    @Published private(set) var isBuying = false
    @Published var message: String?

    func load() async {
        guard packs.isEmpty else { return }
        packs = ((try? await Product.products(for: AssistantCreditProductID.packs)) ?? [])
            .sorted { $0.price < $1.price }
    }

    func buy(_ product: Product) async {
        isBuying = true
        defer { isBuying = false }
        do {
            let backend = AssistantBackendClient.shared
            try await backend.ensureRegistered()
            var options: Set<Product.PurchaseOption> = []
            if let token = backend.appAccountToken { options.insert(.appAccountToken(token)) }
            switch try await product.purchase(options: options) {
            case let .success(verification):
                guard case let .verified(transaction) = verification else {
                    message = String(localized: "The purchase could not be verified.")
                    return
                }
                // Credits are added on our server; only then is the purchase finished,
                // so an interrupted report is retried from Transaction.updates.
                try await backend.recordTransaction(verification.jwsRepresentation)
                await transaction.finish()
                message = String(localized: "Credits added.")
            case .pending:
                message = String(localized: "The purchase is waiting for approval.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Called by `SubscriptionManager` for every transaction update before it is
    /// finished. Returns false when a credit pack could not be reported yet, so
    /// the transaction stays unfinished and comes back later.
    static func report(productID: String, jws: String) async -> Bool {
        let isPack = AssistantCreditProductID.packs.contains(productID)
        let isPlan = AssistantCreditProductID.subscriptionsWithCredits.contains(productID)
        guard isPack || isPlan else { return true }
        let sent = await recordOnMain(jws)
        // A plan is still a plan when the credit report fails; a pack waits.
        return isPack ? sent : true
    }

    private static func recordOnMain(_ jws: String) async -> Bool {
        guard AssistantBackendClient.isConfigured else { return false }
        return (try? await AssistantBackendClient.shared.recordTransaction(jws)) != nil
    }
}

/// Credits for the online assistant: the balance, what they pay for, the packs.
struct AssistantCreditsView: View {
    @ObservedObject private var store = AssistantCreditsStore.shared
    @ObservedObject private var backend = AssistantBackendClient.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Balance")
                        Spacer()
                        AssistantCreditsBadge(credits: backend.wallet?.credits)
                    }
                } footer: {
                    Text("Credits pay for the online assistant (OpenAI): voice conversations, plans, recipes and reading photos. The on-device assistant stays free.")
                }

                Section {
                    if store.packs.isEmpty {
                        Text("Credit packs are not available yet.").foregroundStyle(.secondary)
                    }
                    ForEach(store.packs, id: \.id) { product in
                        Button {
                            Task { await store.buy(product) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(product.displayName)
                                    Text(product.description).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(product.displayPrice).bold()
                            }
                        }
                        .disabled(store.isBuying)
                    }
                } header: {
                    Text("Credit packs")
                } footer: {
                    Text("One-time purchases. The Premium plan also includes credits every month.")
                }

                if let message = store.message {
                    Section { Text(message) }
                }
            }
            .navigationTitle(Text("AI credits"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Close") }
                }
            }
            .task {
                await store.load()
                _ = try? await backend.refreshWallet()
            }
        }
    }
}

/// The plan screen's line about AI credits, shown when the online assistant exists.
struct AssistantCreditsPaywallSection: View {
    @ObservedObject private var backend = AssistantBackendClient.shared
    @State private var showCredits = false

    var body: some View {
        if AssistantBackendClient.isOpenAIAvailable {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI assistant credits").font(.subheadline.weight(.semibold))
                    Text("For voice, plans and photos with the online assistant.").font(.caption).opacity(0.8)
                }
                Spacer()
                Button { showCredits = true } label: {
                    AssistantCreditsBadge(credits: backend.wallet?.credits)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .glassCardStyle(cornerRadius: 20)
            .task { _ = try? await backend.refreshWallet() }
            .sheet(isPresented: $showCredits) { AssistantCreditsView() }
        }
    }
}
