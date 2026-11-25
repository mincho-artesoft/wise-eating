import XCTest
import SwiftData
@testable import Ayurveda___Asana_Yoga

/// Runs every query in `golden_queries.json` through the real search engine on
/// the real bundled catalogue and writes what came back. Nothing is asserted
/// here about the results: `tools/search-golden/compare.py` compares the output
/// with the committed baseline and with the expectations in the query file.
///
/// The folder comes from the environment (see `tools/search-golden/remote.sh`):
///   SEARCH_GOLDEN_DIR/golden_queries.json   input
///   SEARCH_GOLDEN_DIR/out/actual.json       results (deterministic)
///   SEARCH_GOLDEN_DIR/out/timing.json       latency (varies run to run)
nonisolated final class FoodSearchGoldenTests: XCTestCase {
    private struct Query: Decodable {
        let q: String
        let cat: String
    }

    private struct Row: Encodable {
        let q: String
        let cat: String
        let total: Int
        let top: [String]
        let text: [String]
        let negative: [String]
        let goals: [String]
        let ph: String?
        let ageMonths: Double?
        let allergens: [String]
        let facets: [String]
        let withoutPhExcluded: Int
    }

    private struct Timing: Encodable {
        let q: String
        let cat: String
        let medianMs: Double
    }

    private struct TimingReport: Encodable {
        let foods: Int
        let indexLoadMs: Double
        let runsPerQuery: Int
        let p50Ms: Double
        let p95Ms: Double
        let maxMs: Double
        let queries: [Timing]
    }

    @MainActor func testGoldenQueries() async throws {
        guard let dir = ProcessInfo.processInfo.environment["SEARCH_GOLDEN_DIR"] else {
            throw XCTSkip("SEARCH_GOLDEN_DIR is not set")
        }
        let root = URL(fileURLWithPath: dir)
        let queries = try JSONDecoder().decode(
            [Query].self,
            from: Data(contentsOf: root.appendingPathComponent("golden_queries.json"))
        )

        // The host app unpacks the catalogue on first launch; wait for it.
        var context: ModelContext?
        for _ in 0..<1200 {
            if let ready = GlobalState.modelContext { context = ready; break }
            try await Task.sleep(for: .milliseconds(500))
        }
        let container = try XCTUnwrap(context, "the database never became ready").container

        // SEARCH_NAME_FIRST=0 runs the same queries with the name-first flag off.
        let nameFirst = ProcessInfo.processInfo.environment["SEARCH_NAME_FIRST"] != "0"
        SearchFeatureFlags.nameFirst = nameFirst

        let engine = SmartFoodSearch3(container: container)
        let loadStart = CFAbsoluteTimeGetCurrent()
        let loaded = await engine.prepareForSearch()
        let indexLoadMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
        XCTAssertTrue(loaded, "the search index did not load")
        let foods = SearchIndexStore.shared.compactFoods.count

        // Fixed, so the snapshot does not depend on when the test runs.
        let clock = AyurvedaSearchTemporalContext(season: "hemanta", period: "midday")
        let runs = 5

        var rows: [Row] = []
        var timings: [Timing] = []
        for query in queries {
            let first = await engine.searchDiagnostics(query: query.q, temporalContext: clock)
            var samples: [Double] = []
            for _ in 0..<runs {
                let start = CFAbsoluteTimeGetCurrent()
                let again = await engine.searchDiagnostics(query: query.q, temporalContext: clock)
                samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
                if again.resultIDs != first.resultIDs {
                    XCTFail("unstable result order for '\(query.q)'")
                }
            }
            samples.sort()
            timings.append(Timing(q: query.q, cat: query.cat, medianMs: samples[runs / 2]))

            let intent = first.intent
            rows.append(Row(
                q: query.q,
                cat: query.cat,
                total: first.resultIDs.count,
                top: first.topNames,
                text: intent.textTokens.sorted(),
                negative: intent.negativeTokens.sorted(),
                goals: intent.nutrientGoals.map { "\($0.nutrient):\($0.constraint)" },
                ph: intent.phConstraint.map { "\($0)" },
                ageMonths: intent.targetConsumerAge,
                allergens: intent.allergenExclusions.map { "\($0)" }.sorted()
                    + (intent.excludeAllAllergens ? ["*"] : []),
                facets: intent.ayurvedaFacetConstraints.map { "\($0)" },
                withoutPhExcluded: first.foodsWithoutPhExcluded
            ))
        }

        let sorted = timings.map(\.medianMs).sorted()
        func percentile(_ p: Double) -> Double {
            sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
        }
        let report = TimingReport(
            foods: foods,
            indexLoadMs: indexLoadMs,
            runsPerQuery: runs,
            p50Ms: percentile(0.50),
            p95Ms: percentile(0.95),
            maxMs: sorted.last ?? 0,
            queries: timings
        )

        let out = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(rows).write(to: out.appendingPathComponent("actual.json"))
        try encoder.encode(report).write(to: out.appendingPathComponent("timing.json"))
        print("SEARCH_GOLDEN|nameFirst=\(nameFirst)|queries=\(rows.count)|foods=\(foods)|loadMs=\(Int(indexLoadMs))|p50=\(report.p50Ms)|p95=\(report.p95Ms)")
    }

    /// The binary search index must give back exactly the index it was made
    /// from; its size and decode time are written next to the search results.
    /// Named to run after the golden queries, which time the first index load.
    @MainActor func testIndexBinaryRoundTrip() async throws {
        guard let dir = ProcessInfo.processInfo.environment["SEARCH_GOLDEN_DIR"] else {
            throw XCTSkip("SEARCH_GOLDEN_DIR is not set")
        }
        var context: ModelContext?
        for _ in 0..<1200 {
            if let ready = GlobalState.modelContext { context = ready; break }
            try await Task.sleep(for: .milliseconds(500))
        }
        let container = try XCTUnwrap(context, "the database never became ready").container
        let loaded = await SmartFoodSearch3(container: container).prepareForSearch()
        XCTAssertTrue(loaded, "the search index did not load")

        let report = try SearchIndexStore.shared.binaryCodecReport()
        XCTAssertTrue(report.roundTripIsExact, "the binary index does not decode to what was encoded")
        XCTAssertGreaterThan(report.foods, 10_000)

        let out = URL(fileURLWithPath: dir).appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: out.appendingPathComponent("binary.json"))
        print("SEARCH_BINARY|exact=\(report.roundTripIsExact)|json=\(report.jsonBytes)|binary=\(report.binaryBytes)|jsonLoadMs=\(Int(report.jsonDecodeMs + report.jsonToMemoryMs))|binaryDecodeMs=\(Int(report.binaryDecodeMs))")
    }
}
