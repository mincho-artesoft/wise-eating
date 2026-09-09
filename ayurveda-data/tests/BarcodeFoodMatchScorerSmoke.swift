import Foundation

@main
struct BarcodeFoodMatchScorerSmoke {
    private static func candidate(
        _ ordinal: Int,
        _ name: String,
        _ relevance: Double
    ) -> BarcodeFoodMatchCandidate {
        BarcodeFoodMatchCandidate(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", ordinal))!,
            name: name,
            searchRelevance: relevance
        )
    }

    private static func requireMatch(
        product: String,
        candidates: [BarcodeFoodMatchCandidate],
        expected: String
    ) {
        guard let decision = BarcodeFoodMatchScorer.select(
            productName: product,
            candidates: candidates
        ), let winner = candidates.first(where: { $0.id == decision.foodID }) else {
            fatalError("Expected a match for \(product)")
        }
        precondition(winner.name == expected, "\(product) mapped to \(winner.name)")
    }

    static func main() {
        requireMatch(
            product: "Mott's 100% Original Apple Juice 1 L",
            candidates: [
                candidate(1, "Apples, raw", 0.98),
                candidate(2, "Apple juice, canned or bottled, unsweetened", 0.92),
            ],
            expected: "Apple juice, canned or bottled, unsweetened"
        )
        requireMatch(
            product: "Oikos Greek Yogurt Strawberry 150 g",
            candidates: [
                candidate(3, "Strawberries, raw", 0.99),
                candidate(4, "Yogurt, Greek, strawberry, nonfat", 0.94),
            ],
            expected: "Yogurt, Greek, strawberry, nonfat"
        )
        requireMatch(
            product: "Dole Premium Bananas 6 pack",
            candidates: [
                candidate(5, "Bananas, raw", 0.97),
                candidate(6, "Banana chips", 0.90),
            ],
            expected: "Bananas, raw"
        )
        requireMatch(
            product: "Coca-Cola Original 330 ml",
            candidates: [
                candidate(7, "Carbonated beverage, cola, regular", 0.96),
                candidate(8, "Chocolate, milk", 0.85),
            ],
            expected: "Carbonated beverage, cola, regular"
        )
        let unsafe = BarcodeFoodMatchScorer.select(
            productName: "Chicken seasoning",
            candidates: [candidate(9, "Chicken, breast, meat only, raw", 0.99)]
        )
        precondition(unsafe == nil, "Seasoning must not map to raw chicken")

        let unknown = BarcodeFoodMatchScorer.select(
            productName: "Nescafe Gold Blend 200 g",
            candidates: [candidate(10, "Coffee, brewed", 0.99)]
        )
        precondition(unknown == nil, "Brand-only names must not guess a food")
        print("Barcode food matcher smoke tests passed")
    }
}
