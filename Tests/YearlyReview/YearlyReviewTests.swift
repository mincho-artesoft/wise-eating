import XCTest
import StoreKit
import StoreKitTest
import SwiftUI
@testable import Ayurveda___Asana_Yoga

nonisolated final class YearlyReviewTests: XCTestCase {
    @MainActor func testAnnualPaywalls() async throws {
        let session = try SKTestSession(configurationFileNamed: "Purchases")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let manager = SubscriptionManager.shared
        for _ in 0..<20 {
            await manager.loadProducts()
            if manager.products.count == 6 { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        XCTAssertEqual(manager.products.count, 6)
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        let window = try XCTUnwrap(windows.first(where: \.isKeyWindow))
        let captureOnly = ProcessInfo.processInfo.environment["AYURVEDA_CAPTURE_CATEGORY"]
        for (category, id, name, price) in [
            (SubscriptionCategory.removeAds, SubscriptionProductID.noAdsYearly,"noads","9.99"),
            (.advance, SubscriptionProductID.advancedYearly,"advanced","24.99"),
            (.premium, SubscriptionProductID.premiumYearly,"premium","39.99")
        ] {
            if let captureOnly, captureOnly != name { continue }
            let product = try XCTUnwrap(manager.products.first { $0.id == id })
            XCTAssertEqual(product.price, Decimal(string: price))
            XCTAssertEqual(product.subscription?.subscriptionPeriod.unit, .year)
            XCTAssertEqual(product.subscription?.introductoryOffer?.paymentMode, .freeTrial)
            XCTAssertTrue(manager.eligibleTrialIDs.contains(id))
            EffectManager.shared.currentGlobalAccentColor = .black
            EffectManager.shared.isLightRowTextColor = false
            window.rootViewController = UIHostingController(rootView: ZStack {
                ThemeBackgroundView().ignoresSafeArea()
                SubscriptionView(selectedCategory: .constant(category), pendingUpgradeCategory: .constant(nil))
            })
            try await Task.sleep(for: .seconds(6))
            print("PAYWALL_CAPTURE", name, "lightText", EffectManager.shared.isLightRowTextColor, "accent", EffectManager.shared.currentGlobalAccentColor)
            window.setNeedsLayout()
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ayurveda-\(name)-yearly.png"))
            let attachment = XCTAttachment(image: image); attachment.name="Yearly \(name)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        if captureOnly != nil { return }
        func waitForActive(_ id: String) async throws {
            for _ in 0..<40 {
                await manager.updatePurchasedStatus()
                if manager.purchasedProductIDs.contains(id) { return }
                try await Task.sleep(for: .milliseconds(250))
            }
            for await verification in StoreTransaction.currentEntitlements {
                print("YEARLY_TEST_ENTITLEMENT", verification)
            }
            print("YEARLY_TEST_TRANSACTIONS", session.allTransactions())
            XCTFail("Expected active entitlement: \(id), got \(manager.purchasedProductIDs)")
            throw NSError(domain: "YearlyReviewTests", code: 1)
        }
        let monthly = try XCTUnwrap(manager.products.first { $0.id == SubscriptionProductID.noAds })
        let yearly = try XCTUnwrap(manager.products.first { $0.id == SubscriptionProductID.noAdsYearly })
        await manager.purchase(monthly)
        try await waitForActive(monthly.id)
        XCTAssertTrue(manager.canPurchase(yearly), "Monthly to yearly must be allowed")
        await manager.purchase(yearly)
        // Apple applies same-tier, different-duration crossgrades at renewal.
        let statuses = try await monthly.subscription!.status
        let renewal = try XCTUnwrap(statuses.compactMap { status -> Product.SubscriptionInfo.RenewalInfo? in
            if case .verified(let info) = status.renewalInfo { return info }; return nil
        }.first)
        XCTAssertEqual(renewal.autoRenewPreference, yearly.id)
        try session.forceRenewalOfSubscription(productIdentifier: monthly.id)
        try await waitForActive(yearly.id)
        XCTAssertFalse(manager.canPurchase(yearly), "Already-owned annual plan cannot be purchased twice")
        manager.purchasedProductIDs = []
        try await waitForActive(yearly.id)
        XCTAssertEqual(manager.subscriptionStatus, .removeAds)
    }
}
