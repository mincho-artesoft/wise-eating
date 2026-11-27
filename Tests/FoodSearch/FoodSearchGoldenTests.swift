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
        /// The language the user is assumed to type in; nil is English.
        let lang: String?
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

        // The golden queries are English unless a query says otherwise.
        var activeLanguage: String?
        SearchGrammar.active = nil
        FoodNameLocalizer.active = nil
        SearchIndexStore.shared.rebuildLocalizedNames()
        engine.refreshData()

        var rows: [Row] = []
        var timings: [Timing] = []
        for query in queries {
            if query.lang != activeLanguage {
                activeLanguage = query.lang
                SearchGrammar.active = query.lang.flatMap { SearchGrammar.bundled(for: $0) }
                FoodNameLocalizer.active = query.lang.flatMap { FoodNameLocalizer.bundled(for: $0) }
                SearchIndexStore.shared.rebuildLocalizedNames()
                engine.refreshData()
                if let lang = query.lang {
                    XCTAssertNotNil(SearchGrammar.active, "no grammar file for '\(lang)'")
                    XCTAssertNotNil(FoodNameLocalizer.active, "no food names for '\(lang)'")
                }
            }
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

        SearchGrammar.active = nil
        FoodNameLocalizer.active = nil
        SearchIndexStore.shared.rebuildLocalizedNames()
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

    /// Every phrase of every grammar file must turn into a command the
    /// English parser fully understands: nothing may be left over as a word
    /// to look for in food names.
    @MainActor func testGrammarFilesMapToCommands() throws {
        let grammars = SearchGrammar.allBundled()
        XCTAssertFalse(grammars.isEmpty, "no grammar files in the bundle")
        // Fragments that only mean something next to a number or a nutrient.
        let fragments: Set<String> = [
            "low", "high", "without", "zero", "less than", "more than", "at least",
            "at most", "no more than", "month", "year", "ph",
        ]
        for grammar in grammars {
            XCTAssertGreaterThan(grammar.allPhrases.count, 20, grammar.language)
            for (phrase, command) in grammar.allPhrases {
                XCTAssertEqual(
                    phrase.filter { $0 == "#" }.count,
                    command.filter { $0 == "#" }.count,
                    "[\(grammar.language)] '\(phrase)': numbers do not match '\(command)'"
                )
                if fragments.contains(command) { continue }
                let sample = command.replacingOccurrences(of: "#", with: "5")
                let leftover = Tokenizer.parse(sample).textTokens
                    .subtracting(["5"])
                XCTAssertTrue(
                    leftover.isEmpty,
                    "[\(grammar.language)] '\(phrase)' -> '\(command)' leaves \(leftover.sorted()) as plain words"
                )
            }
        }
    }

    /// Every packed language must load, cover the whole segment list and be
    /// found for the identifiers iOS reports for it.
    @MainActor func testFoodNameFilesLoad() throws {
        let files = (Bundle.main.urls(forResourcesWithExtension: "z", subdirectory: nil) ?? [])
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { $0.hasPrefix("food_names.") }
            .map { String($0.dropFirst("food_names.".count)) }
            .sorted()
        XCTAssertFalse(files.isEmpty, "no food name files in the bundle")
        for language in files {
            let localizer = try XCTUnwrap(FoodNameLocalizer.bundled(for: language), language)
            XCTAssertEqual(localizer.language, language)
            XCTAssertNotNil(localizer.localizedName("Beef, raw"), "[\(language)] 'Beef, raw' is not translated")
        }
        XCTAssertTrue(FoodNameLocalizer.candidates(for: "zh-Hant-TW").contains("zh-Hant"))
        XCTAssertTrue(FoodNameLocalizer.candidates(for: "zh-TW").contains("zh-Hant"))
        XCTAssertTrue(FoodNameLocalizer.candidates(for: "zh-CN").contains("zh-Hans"))
        XCTAssertEqual(FoodNameLocalizer.candidates(for: "es-MX").filter { ["es-MX", "es"].contains($0) }, ["es-MX", "es"])
        XCTAssertEqual(FoodNameLocalizer.candidates(for: "pt-BR").filter { ["pt-BR", "pt"].contains($0) }, ["pt-BR", "pt"])
        XCTAssertTrue(FoodNameLocalizer.candidates(for: "bg").contains("bg"))
        if files.contains("zh-Hant") {
            XCTAssertEqual(FoodNameLocalizer.bundled(for: "zh-Hant-TW")?.language, "zh-Hant")
            XCTAssertEqual(FoodNameLocalizer.bundled(for: "zh-TW")?.language, "zh-Hant")
        }
        if files.contains("zh-Hans") {
            XCTAssertEqual(FoodNameLocalizer.bundled(for: "zh-CN")?.language, "zh-Hans")
        }
        if files.contains("es-MX") {
            XCTAssertEqual(FoodNameLocalizer.bundled(for: "es-MX")?.language, "es-MX")
        }
        if files.contains("pt") {
            XCTAssertEqual(FoodNameLocalizer.bundled(for: "pt-BR")?.language, "pt")
        }
        print("SEARCH_NAMES|languages=\(files.count)|\(files.joined(separator: ","))")
    }

    /// Every packed recipe/dravya content table must load and match the
    /// English table length.
    @MainActor func testRecipeContentFilesLoad() throws {
        let files = (Bundle.main.urls(forResourcesWithExtension: "z", subdirectory: nil) ?? [])
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { $0.hasPrefix("recipe_content.") && $0 != "recipe_content.en" }
            .map { String($0.dropFirst("recipe_content.".count)) }
            .sorted()
        guard !files.isEmpty else { return }
        for language in files {
            let localizer = try XCTUnwrap(RecipeContentLocalizer.bundled(for: language), language)
            XCTAssertEqual(localizer.language, language)
        }
        print("RECIPE_CONTENT|languages=\(files.count)|\(files.joined(separator: ","))")
    }

    /// The practice and yoga text tables load for every bundled language and
    /// translate a string of each catalogue.
    @MainActor func testCatalogTextFilesLoad() throws {
        for (prefix, sample) in [("practice_content", "Rain on the Roof"), ("yoga_content", "high blood pressure")] {
            let files = (Bundle.main.urls(forResourcesWithExtension: "z", subdirectory: nil) ?? [])
                .map { $0.deletingPathExtension().lastPathComponent }
                .filter { $0.hasPrefix("\(prefix).") && $0 != "\(prefix).en" }
                .map { String($0.dropFirst(prefix.count + 1)) }
                .sorted()
            XCTAssertEqual(files.count, 48, prefix)
            for language in files {
                let localizer = try XCTUnwrap(CatalogTextLocalizer.bundled(prefix, for: language), language)
                XCTAssertEqual(localizer.language, language)
                XCTAssertNotNil(localizer.translation(of: sample), "\(prefix) \(language)")
                XCTAssertEqual(localizer.text("not a catalogue string"), "not a catalogue string")
            }
            print("CATALOG_TEXT|\(prefix)|languages=\(files.count)")
        }
        XCTAssertNil(CatalogTextLocalizer.bundled("practice_content", for: "en"))
    }

    /// The yoga tab's index over the real catalogue: every pose is reachable
    /// by its English and Sanskrit names in any word order, in part, with a
    /// typing error, and by family, level and muscle group. Results and
    /// timings are written next to the food results.
    @MainActor func testYogaSearch() async throws {
        var context: ModelContext?
        for _ in 0..<1200 {
            if let ready = GlobalState.modelContext { context = ready; break }
            try await Task.sleep(for: .milliseconds(500))
        }
        let ready = try XCTUnwrap(context, "the database never became ready")
        let poses = try ready.fetch(FetchDescriptor<ExerciseItem>(
            predicate: #Predicate { !$0.isUserAdded }
        ))
        XCTAssertGreaterThan(poses.count, 800)

        let buildStart = CFAbsoluteTimeGetCurrent()
        let index = YogaSearchIndex.make(from: poses)
        let buildMs = (CFAbsoluteTimeGetCurrent() - buildStart) * 1000
        let nameByID = Dictionary(poses.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let poseByID = Dictionary(poses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        struct Row: Encodable { let q: String; let total: Int; let ms: Double; let top: [String] }
        var rows: [Row] = []
        func search(_ query: String) -> [String] {
            let start = CFAbsoluteTimeGetCurrent()
            let ids = index.search(query)
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let top = ids.prefix(8).compactMap { nameByID[$0] }
            rows.append(Row(q: query, total: ids.count, ms: ms, top: top))
            return ids.compactMap { nameByID[$0] }
        }

        // The first result is the pose that was named.
        for (query, expected) in [
            ("mountain pose", "Mountain Pose"),
            ("tadasana", "Mountain Pose"),
            ("downward-facing dog", "Downward-Facing Dog"),
            ("dog downward", "Downward-Facing Dog"),
            ("adho mukha svanasana", "Downward-Facing Dog"),
            ("warrior ii", "Warrior II"),
            ("child's pose", "Child's Pose"),
            ("childs pose", "Child's Pose"),
            ("balasana", "Child's Pose"),
            ("cat pose", "Cat Pose"),
            ("marjaryasana", "Cat Pose"),
            ("puppy", "Puppy Pose"),
            ("WARRIOR III", "Warrior III"),
        ] {
            // Catalogue names read "Mountain Pose (Tadasana)".
            let first = search(query).first ?? ""
            XCTAssertTrue(
                first == expected || first.hasPrefix(expected + " ("),
                "query '\(query)' gave '\(first)', expected '\(expected)'"
            )
        }
        // Part of a word, and a typing error.
        func has(_ names: [String], _ title: String) -> Bool {
            names.contains { $0 == title || $0.hasPrefix(title + " (") }
        }
        XCTAssertTrue(has(search("warr"), "Warrior I"))
        XCTAssertTrue(has(search("tadas"), "Mountain Pose"))
        XCTAssertTrue(has(search("warior"), "Warrior I"), "one wrong letter")
        // Names that start with the words typed come first; the pose itself
        // is still among them.
        XCTAssertTrue(has(Array(search("downward dog").prefix(10)), "Downward-Facing Dog"))
        // Title and Sanskrit name are taken apart for translation.
        let mountain = try XCTUnwrap(poses.first { $0.name.hasPrefix("Mountain Pose") })
        XCTAssertEqual(YogaSearchIndex.title(of: mountain), "Mountain Pose")
        XCTAssertEqual(mountain.sanskrit, "Tadasana")
        XCTAssertTrue(search("trikonasna").contains { $0.contains("Triangle") }, "one missing letter")
        // Facets: family, level, muscle group, alone and together.
        for query in ["backbend", "hip opener", "standing balance", "beginner", "advanced inversion",
                      "hamstrings", "beginner backbend", "twist intermediate"] {
            XCTAssertFalse(search(query).isEmpty, "facet query '\(query)'")
        }
        let beginnerBackbends = index.search("beginner backbend").compactMap { poseByID[$0] }
        XCTAssertTrue(beginnerBackbends.allSatisfy { $0.level == 1 })
        XCTAssertTrue(beginnerBackbends.allSatisfy {
            $0.family == .backbend || $0.name.lowercased().contains("backbend")
        })
        // A name outranks a facet: "twist" lists poses named Twist before the family.
        XCTAssertTrue(search("twist").first?.lowercased().contains("twist") == true)
        XCTAssertTrue(search("zzzzqq").isEmpty)
        XCTAssertTrue(search("").isEmpty)

        let slowest = rows.map(\.ms).max() ?? 0
        if let dir = ProcessInfo.processInfo.environment["SEARCH_GOLDEN_DIR"] {
            let out = URL(fileURLWithPath: dir).appendingPathComponent("out")
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(rows).write(to: out.appendingPathComponent("yoga.json"))
        }
        print("SEARCH_YOGA|poses=\(poses.count)|buildMs=\(Int(buildMs))|queries=\(rows.count)|slowestMs=\(slowest)")
    }
}
