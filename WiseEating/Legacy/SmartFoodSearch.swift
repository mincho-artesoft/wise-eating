//// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth2/WiseEating/AI/SmartFoodSearch.swift ====
//import Foundation
//import SwiftData
//import FoundationModels
//import os
//
//final class SmartFoodSearch: Sendable {
//
//    // 1. Define a private, Sendable struct to hold only the data needed for searching.
//    private struct SearchableFoodItem: Sendable {
//        let persistentModelID: PersistentIdentifier
//        let name: String
//        let nameNormalized: String
//        let searchTokens: [String]
//    }
//
//    private let container: ModelContainer
//    // 2. The stored property is now an array of the Sendable struct.
//    private let allFoods: [SearchableFoodItem]
//    // NEW: The inverted index. Maps a stemmed token to the array indices of matching foods.
//    private let invertedIndex: [String: [Int]]
//    // NEW: A cache for AI signals. Use NSCache because it's thread-safe and handles memory pressure.
//    private let signalCache = NSCache<NSString, NSData>()
//    
//    private let logger = Logger(subsystem: "com.yourapp.foodsearch", category: "SmartFoodSearch")
//    private let verboseAISearchLogging = true
//
//    init(container: ModelContainer) {
//        self.container = container
//        let ctx = ModelContext(container)
//        let descriptor = FetchDescriptor<FoodItem>()
//        
//        // --- Caching Logic ---
//        let searchableItems: [SearchableFoodItem]
//        do {
//            let fetchedFoods = try ctx.fetch(descriptor)
//            // 3. Map the fetched Model objects to the Sendable struct during initialization.
//            searchableItems = fetchedFoods.map { food in
//                SearchableFoodItem(
//                    persistentModelID: food.persistentModelID,
//                    name: food.name,
//                    nameNormalized: food.nameNormalized,
//                    searchTokens: food.searchTokens
//                )
//            }
//        } catch {
//            searchableItems = []
//            logger.error("Failed to fetch food items during initialization: \(error.localizedDescription)")
//        }
//        self.allFoods = searchableItems
//        
//        // --- Indexing Logic ---
//        var indexBuilder: [String: [Int]] = [:]
//        for (itemIndex, item) in allFoods.enumerated() {
//            let uniqueTokens = Set(item.searchTokens.map(Self.stem))
//            for token in uniqueTokens {
//                indexBuilder[token, default: []].append(itemIndex)
//            }
//        }
//        self.invertedIndex = indexBuilder
//        
//        logger.info("SmartFoodSearch initialized. Cached \(self.allFoods.count) items and built index with \(self.invertedIndex.keys.count) unique tokens.")
//    }
//    
//    // NEW: Helper method to get candidate indices from the inverted index.
//    private func getCandidateIndices(from tokens: Set<String>) -> Set<Int> {
//        guard !tokens.isEmpty else { return [] }
//        
//        var candidateIndices: Set<Int> = Set()
//        
//        // Find all items that match at least one token
//        for token in tokens {
//            if let indices = invertedIndex[token] {
//                candidateIndices.formUnion(indices)
//            }
//        }
//        return candidateIndices
//    }
//
//    // MARK: - AI Schema (Generable) - No changes needed here
//    @available(iOS 26.0, macOS 15.0, *)
//    @Generable
//    struct AISearchSignals: Codable {
//        @Guide(description: "Anchor terms ordered by importance. First headword should be the most central concept, preferring the most basic, common, edible form (e.g., for 'fried chicken breast', headword is 'chicken'). All lowercase.", .count(1...3))
//        let headwords: [String]
//
//        @Guide(description: "Supporting generic terms/phrases ordered by relevance. Include forms, attributes, or contexts implied by the query; exclude brands/concrete items. All lowercase.", .count(0...8))
//        let priorityKeywords: [String]
//
//        @Guide(description: "Lowercase tokens to AVOID. Focus on forms that change the food's nature (e.g., 'powder', 'sauce', 'dressing', 'shake', 'oil', 'flour'). Do NOT ban common states like 'raw', 'cooked', 'fresh', 'frozen', 'canned' unless the query explicitly negates them.", .count(0...8))
//        let bannedKeywords: [String]
//
//        @Guide(description: "Generic lexical variants only. Keys ≤8, each value ≤6 items. All lowercase; deduplicated.", .count(0...8))
//        let synonyms: [SynonymsEntry]
//
//        @Guide(description: "Integer weights −8..+8. Positives boost, negatives penalize. ≤8 entries. Keys lowercase.", .count(0...8))
//        let phraseBoosts: [WeightedPhrase]
//
//        @Guide(description: "Integer weights −8..+8 for tokens/phrases. ≤16 entries. Keys lowercase.", .count(0...16))
//        let tokenWeights: [WeightedToken]
//
//        @Guide(description: "Single ICU/NSRegularExpression pattern to detect negations of relevant terms in candidate text; or null if not useful.")
//        let negationRegex: String?
//    }
//
//    @available(iOS 26.0, macOS 15.0, *)
//    @Generable
//    struct SynonymsEntry: Codable {
//        @Guide(description: "Lowercase phrase or term key for synonyms (generic, non-concrete).")
//        let key: String
//        @Guide(description: "Lowercase variants for the key; 1–6 items.", .count(1...6))
//        let variants: [String]
//    }
//
//    @available(iOS 26.0, macOS 15.0, *)
//    @Generable
//    struct WeightedPhrase: Codable {
//        @Guide(description: "Lowercase phrase to boost or penalize (generic, non-concrete).")
//        let key: String
//        @Guide(description: "Integer weight −8..+8; positive boosts, negative penalizes.")
//        let weight: Int
//    }
//
//    @available(iOS 26.0, macOS 15.0, *)
//    @Generable
//    struct WeightedToken: Codable {
//        @Guide(description: "Lowercase token or phrase (generic, non-concrete).")
//        let key: String
//        @Guide(description: "Integer weight −8..+8; positive boosts, negative penalizes.")
//        let weight: Int
//    }
//    
//    // MARK: - AI Search Logic - No changes needed here
//    @available(iOS 26.0, macOS 15.0, *)
//    private struct SearchSignals: Codable, Sendable {
//        let headwords: [String]
//        let priorityKeywords: [String]
//        let bannedKeywords: [String]
//        let synonyms: [String: [String]]
//        let phraseBoosts: [String: Int]
//        let tokenWeights: [String: Int]
//        let negationRegex: String?
//    }
//
//    @available(iOS 26.0, macOS 15.0, *)
//    private static func validate(_ s: SearchSignals) -> SearchSignals? {
//        func isLowercased(_ text: String) -> Bool { text == text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
//        func clampWeights(_ dict: [String: Int], maxCount: Int) -> [String: Int] {
//            let bounded = dict.prefix(maxCount).reduce(into: [String: Int]()) { acc, kv in
//                let (k, v) = kv
//                guard isLowercased(k) else { return }
//                acc[k] = max(-8, min(8, v))
//            }
//            return bounded
//        }
//
//        let hw = Array(Set(s.headwords.filter { !$0.isEmpty && isLowercased($0) })).prefix(3)
//        guard !hw.isEmpty else { return nil }
//        let pk = Array(Set(s.priorityKeywords.filter { !$0.isEmpty && isLowercased($0) })).prefix(8)
//        let bk = Array(Set(s.bannedKeywords.filter { !$0.isEmpty && isLowercased($0) })).prefix(8)
//        
//        let hwSet = Set(hw)
//        let pkSet = Set(pk)
//        let filteredBK = bk.filter { !hwSet.contains($0) && !pkSet.contains($0) }
//
//        var syn: [String: [String]] = [:]
//        for (k, vals) in s.synonyms.prefix(8) {
//            guard isLowercased(k) else { continue }
//            let vv = Array(Set(vals.filter { !$0.isEmpty && isLowercased($0) })).prefix(6)
//            if !vv.isEmpty { syn[k] = Array(vv) }
//        }
//
//        var pb = clampWeights(s.phraseBoosts, maxCount: 8)
//        var tw = clampWeights(s.tokenWeights, maxCount: 16)
//        
//        for k in hwSet.union(pkSet) {
//            if let w = pb[k], w < 0 { pb[k] = 0 }
//            if let w = tw[k], w < 0 { tw[k] = 0 }
//        }
//        let nr = (s.negationRegex?.isEmpty == true) ? nil : s.negationRegex
//
//        return SearchSignals(
//            headwords: Array(hw),
//            priorityKeywords: Array(pk),
//            bannedKeywords: Array(filteredBK),
//            synonyms: syn,
//            phraseBoosts: pb,
//            tokenWeights: tw,
//            negationRegex: nr
//        )
//    }
//
//    @available(iOS 26.0, macOS 15.0, *)
//    private func generateSignals(for query: String, context: String?) async throws -> SearchSignals? {
//        // --- CHECK 1: Преди скъпата AI операция ---
//        try Task.checkCancellation()
//        
//        // MODIFIED: Implement caching for AI signals
//        let cacheKey = "\(query)|\(context ?? "")" as NSString
//
//        // Check cache first
//        if let cachedData = signalCache.object(forKey: cacheKey) {
//            if let signals = try? JSONDecoder().decode(SearchSignals.self, from: cachedData as Data) {
//                logger.debug("AI Signals cache HIT for query: '\(query)'")
//                return signals
//            }
//        }
//        logger.debug("AI Signals cache MISS for query: '\(query)'")
//        
//        var prompt = """
//Analyze the user query and emit compact, generic lexical search signals. Output only JSON.
//
//Query:
//\(query)
//"""
//        if let ctx = context, !ctx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
//            prompt += "\nAdditional context (optional):\n\(ctx)\n"
//        }
//
//        let options = GenerationOptions(sampling: .random(top: 50), temperature: 0.7)
//
//        do {
//            let session = LanguageModelSession(instructions: Instructions {
//                """
//                You produce only JSON that matches the provided schema. No prose.
//                """
//            })
//            let content = try await session.respond(
//                to: prompt,
//                generating: AISearchSignals.self,
//                includeSchemaInPrompt: true,
//                options: options
//            ).content
//            
//            // --- CHECK 2: Веднага след връщане от await ---
//            try Task.checkCancellation()
//
//            var synDict: [String: [String]] = [:]
//            for e in content.synonyms { synDict[e.key] = e.variants }
//
//            var phraseDict: [String: Int] = [:]
//            for e in content.phraseBoosts { phraseDict[e.key] = e.weight }
//
//            var tokenDict: [String: Int] = [:]
//            for e in content.tokenWeights { tokenDict[e.key] = e.weight }
//
//            let s = SearchSignals(
//                headwords: content.headwords,
//                priorityKeywords: content.priorityKeywords,
//                bannedKeywords: content.bannedKeywords,
//                synonyms: synDict,
//                phraseBoosts: phraseDict,
//                tokenWeights: tokenDict,
//                negationRegex: content.negationRegex
//            )
//
//            // After successfully getting a response and validating it:
//            if let validatedSignals = Self.validate(s) {
//                // Store the result in the cache for next time
//                if let dataToCache = try? JSONEncoder().encode(validatedSignals) {
//                    signalCache.setObject(dataToCache as NSData, forKey: cacheKey)
//                }
//                return validatedSignals
//            }
//            return nil
//        } catch {
//            // Не прекратяваме при CancellationError, просто я хвърляме нагоре
//            if !(error is CancellationError) {
//                logger.error("AI signals generation failed: \(String(describing: error))")
//            }
//            throw error
//        }
//    }
//
//    @available(iOS 26.0, macOS 15.0, *)
//    private func matchesNegation(_ regex: String, in text: String, terms: [String]) -> Bool {
//        guard let re = try? NSRegularExpression(pattern: regex, options: []) else { return false }
//        let t = text
//        let full = NSRange(t.startIndex..<t.endIndex, in: t)
//        
//        if !terms.contains(where: { t.contains($0) }) { return false }
//        return re.firstMatch(in: t, options: [], range: full) != nil
//    }
//
//    @available(iOS 26.0, macOS 15.0, *)
//    private func extractContextTags(from context: String?) -> (headwords: Set<String>, cuisines: Set<String>) {
//        guard let context = context, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return ([], []) }
//        let lower = context.lowercased()
//        
//        var headwords = Set<String>()
//        var cuisines = Set<String>()
//
//        if let reHead = try? NSRegularExpression(pattern: #"headword\s*:\s*\"?([a-zA-Z][a-zA-Z\-\s]+?)\"?(?:,|$|\n)"#, options: []) {
//            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
//            let matches = reHead.matches(in: lower, options: [], range: range)
//            for m in matches {
//                if m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: lower) {
//                    let token = String(lower[r]).trimmingCharacters(in: .whitespacesAndNewlines)
//                    if !token.isEmpty { headwords.insert(Self.stem(token)) }
//                }
//            }
//        }
//        
//        if let reCuisine = try? NSRegularExpression(pattern: #"cuisine\s*:\s*\"?([a-zA-Z][a-zA-Z\-\s]+?)\"?(?:,|$|\n)"#, options: []) {
//            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
//            let matches = reCuisine.matches(in: lower, options: [], range: range)
//            for m in matches {
//                if m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: lower) {
//                    let token = String(lower[r]).trimmingCharacters(in: .whitespacesAndNewlines)
//                    if !token.isEmpty { cuisines.insert(Self.stem(token)) }
//                }
//            }
//        }
//
//        return (headwords, cuisines)
//    }
//
//    // 4. Update methods to accept the Sendable struct.
//    @available(iOS 26.0, *)
//    private func buildTokenStats(_ foods: [SearchableFoodItem]) -> (df: [String: Int], tail: [String: Int], totalDocs: Int) {
//        var df: [String: Int] = [:]
//        var tail: [String: Int] = [:]
//        for f in foods {
//            let toks = f.searchTokens.map(Self.stem)
//            let unique = Set(toks)
//            for t in unique { df[t, default: 0] += 1 }
//            if let last = toks.last { tail[last, default: 0] += 1 }
//        }
//        return (df, tail, max(foods.count, 1))
//    }
//    
//    @available(iOS 26.0, *)
//    private func choosePrimaryHeadword(signals: SearchSignals, query: String, foods: [SearchableFoodItem]) -> String {
//        let qTokens = Self.tokenize(query)
//        let qSet = Set(qTokens)
//        let lowerQuery = query.lowercased()
//
//        let formHeads: Set<String> = [
//            "salad","soup","porridge","pudding","tea","curry","stew","smoothie","bread","sandwich","wrap","bowl","rice"
//        ]
//
//        func stemVariants(_ term: String) -> Set<String> {
//            let t = term.lowercased()
//            if t.hasSuffix("ies") {
//                let base = String(t.dropLast(3))
//                return [Self.stem(t), base + "y", base + "ie"]
//            }
//            return [Self.stem(t), t]
//        }
//
//        let stats = buildTokenStats(foods)
//        let N = max(stats.totalDocs, 1)
//        func df(_ term: String) -> Int { stats.df[Self.stem(term)] ?? 0 }
//        func tail(_ term: String) -> Int { stats.tail[Self.stem(term)] ?? 0 }
//        func idf(_ term: String) -> Double { let d = max(1, df(term)); return log2(Double(N) / Double(d)) }
//        func tailRatio(_ term: String) -> Double { let d = max(1, df(term)); return Double(tail(term)) / Double(d) }
//
//        if !signals.headwords.isEmpty {
//            let headsInQuery = signals.headwords.filter { h in
//                let stems = stemVariants(h)
//                return stems.contains(where: { qSet.contains($0) }) || lowerQuery.contains(h)
//            }
//            let formInQuery = headsInQuery.first(where: { formHeads.contains($0) })
//            if let f = formInQuery { return f }
//        }
//
//        var presentHeads: [String] = []
//        for h in signals.headwords {
//            let stems = stemVariants(h)
//            if stems.contains(where: { qSet.contains($0) }) || lowerQuery.contains(h) {
//                presentHeads.append(h)
//            }
//        }
//        if !presentHeads.isEmpty {
//            var headIndex: [String: Int] = [:]
//            for (i, h) in signals.headwords.enumerated() { headIndex[h] = i }
//            var best = presentHeads.first!
//            var bestScore = Int.min
//            for t in presentHeads {
//                var s = 0
//                let tr = tailRatio(t)
//                if tr >= 0.5 { s += 6 } else if tr >= 0.25 { s += 3 } else if tr <= 0.1 { s -= 2 }
//                s += min(4, Int(idf(t).rounded()))
//                if let idx = headIndex[t] { s += (idx == 0 ? 6 : idx == 1 ? 3 : 1) }
//                if formHeads.contains(t) { s += 6 }
//                if let w = signals.tokenWeights[t] { s += max(-8, min(8, w)) }
//                if let w = signals.phraseBoosts[t] { s += max(-8, min(8, w)) }
//                if s > bestScore { bestScore = s; best = t }
//            }
//            return best
//        }
//
//        var presentPri: [String] = []
//        for p in signals.priorityKeywords {
//            let stems = stemVariants(p)
//            if stems.contains(where: { qSet.contains($0) }) || lowerQuery.contains(p) {
//                presentPri.append(p)
//            }
//        }
//        if !presentPri.isEmpty { return presentPri.first! }
//
//        let candidates = Array(Set(signals.headwords + signals.priorityKeywords))
//        if candidates.isEmpty { return qTokens.last ?? lowerQuery }
//
//        var headIndex: [String: Int] = [:]
//        for (i, h) in signals.headwords.enumerated() { headIndex[h] = i }
//
//        var best = candidates.first!
//        var bestScore = Int.min
//        for t in candidates {
//            var s = 0
//            if qSet.contains(Self.stem(t)) || lowerQuery.contains(t) { s += 6 }
//            if qTokens.last == Self.stem(t) { s += 2 }
//            if let w = signals.tokenWeights[t] { s += max(-8, min(8, w)) }
//            if let w = signals.phraseBoosts[t] { s += max(-8, min(8, w)) }
//            let d = df(t)
//            if d > 0 { s += min(6, Int(log2(Double(d + 1)))) }
//            let tr = tailRatio(t)
//            if d > 0 {
//                if tr >= 0.5 { s += 6 } else if tr >= 0.25 { s += 3 } else if tr <= 0.1 { s -= 2 }
//            }
//            s += min(4, Int(idf(t).rounded()))
//            if let idx = headIndex[t] { s += (idx == 0 ? 6 : idx == 1 ? 3 : 1) }
//            if formHeads.contains(t) { s += 6 }
//            if s > bestScore { bestScore = s; best = t }
//        }
//        return best
//    }
//
//    private struct ScoreComponents {
//        let overlap: Int
//        let phrase: Int
//        let banned: Int
//        let brevity: Int
//        var total: Int { overlap + phrase + banned + brevity }
//    }
//
//    private func formatWeights(_ dict: [String: Int]) -> String {
//        dict.map { "\($0.key):\($0.value)" }.sorted().joined(separator: ", ")
//    }
//    
//    @available(iOS 26.0, *)
//    private func computeScore(
//        item: SearchableFoodItem,
//        rawQuery: String,
//        queryTokens: Set<String>,
//        signals: SearchSignals,
//        primary: String,
//        priStem: String
//    ) -> ScoreComponents {
//        let name = item.nameNormalized
//        let tokens = item.searchTokens.map(Self.stem)
//
//        let overlap = queryTokens.intersection(Set(tokens)).count
//
//        var phraseAccum = 0
//        let hasPrimary = name.contains(primary) || tokens.contains(priStem)
//        let queryHasPrimary = rawQuery.lowercased().contains(primary)
//        if hasPrimary { phraseAccum += 6 } else if queryHasPrimary { phraseAccum -= 6 }
//        for (p, w) in signals.phraseBoosts { if name.contains(p) { phraseAccum += w } }
//        for (t, w) in signals.tokenWeights {
//            if name.contains(t) || tokens.contains(Self.stem(t)) { phraseAccum += w }
//        }
//
//        var bannedPenalty = 0
//        let banned = Set(signals.bannedKeywords)
//        if name.split(separator: " ").contains(where: { banned.contains(String($0)) }) { bannedPenalty -= 6 }
//
//        let brevity = -(tokens.count / 10)
//
//        return ScoreComponents(overlap: overlap, phrase: phraseAccum, banned: bannedPenalty, brevity: brevity)
//    }
//
//    // MARK: - Public Search Method (Apple Intelligence powered)
//    @available(iOS 26.0, macOS 15.0, *)
//    func  _searchFoodsAI(query: String, limit: Int = 50, context: String? = nil) async -> [PersistentIdentifier] {
//        return await searchFoodsAI(query: query, limit: limit, context: context, requiredHeadwords: nil)
//    }
//    
//    @available(iOS 26.0, macOS 15.0, *)
//    func  _searchFoodsAI(query: String, limit: Int = 50, context: String? = nil, requiredHeadwords: [String]? = nil) async -> [PersistentIdentifier] {
//        // --- CHECK 3: В самото начало на основната функция ---
//        do {
//            try Task.checkCancellation()
//        } catch {
//            logger.info("Search cancelled at the very beginning.")
//            return []
//        }
//        
//        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
//        guard !raw.isEmpty else { return [] }
//
//        do {
//            guard let signals = try await generateSignals(for: raw, context: context) else {
//                return searchFoods(query: raw, limit: limit)
//            }
//            
//            // --- CHECK 4: Между основните логически блокове ---
//            try Task.checkCancellation()
//
//            guard !allFoods.isEmpty else { return [] }
//
//            let primary = choosePrimaryHeadword(signals: signals, query: raw, foods: allFoods)
//            let priStem = Self.stem(primary)
//
//            let (contextHeadwords, contextCuisines) = extractContextTags(from: context)
//            let cuisineTokens = Set(contextCuisines.flatMap { Self.tokenize($0) })
//
//            var requiredHeads = Set<String>()
//            if let headwords = requiredHeadwords {
//                for h in headwords {
//                    let s = Self.stem(h.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
//                    if !s.isEmpty { requiredHeads.insert(s) }
//                }
//            }
//            for h in contextHeadwords {
//                if !h.isEmpty { requiredHeads.insert(h) }
//            }
//
//            if verboseAISearchLogging {
//                logger.debug("Extracted Context: headwords=\(contextHeadwords.joined(separator: ",")) cuisines=\(contextCuisines.joined(separator: ","))")
//                if let provided = requiredHeadwords, !provided.isEmpty {
//                    logger.debug("Provided requiredHeadwords=\(provided.joined(separator: ","))")
//                }
//                if !requiredHeads.isEmpty {
//                    logger.debug("Effective requiredHeadwords(stemmed)=\(Array(requiredHeads).joined(separator: ","))")
//                }
//                if let c = context, !c.isEmpty {
//                    logger.debug("Context provided=\(c)")
//                }
//            }
//            
//            var pool: [SearchableFoodItem] = []
//            let ctxTokens = Set(Self.tokenize(context ?? ""))
//
//            if let primaryIndices = invertedIndex[priStem] {
//                let candidates = primaryIndices.map { allFoods[$0] }
//                pool = candidates.filter { f in
//                    let tokens = Set(f.searchTokens.map(Self.stem))
//                    if !requiredHeads.isEmpty && !requiredHeads.contains(where: { req in tokens.contains(req) || f.nameNormalized.contains(req) }) {
//                        return false
//                    }
//                    if ctxTokens.isEmpty && cuisineTokens.isEmpty { return true }
//                    return !ctxTokens.isDisjoint(with: tokens)
//                        || !cuisineTokens.isDisjoint(with: tokens)
//                        || ctxTokens.contains(where: { f.nameNormalized.contains($0) })
//                        || cuisineTokens.contains(where: { f.nameNormalized.contains($0) })
//                }
//            }
//            if verboseAISearchLogging { logger.debug("Pool(primary ' \(primary) ') with context=\(ctxTokens.isEmpty ? "Ø" : Array(ctxTokens).joined(separator: ",")) -> \(pool.count)") }
//            
//            if pool.isEmpty {
//                let priorityTokens = Set(signals.priorityKeywords.map(Self.stem)).union(cuisineTokens)
//                let candidateIndices = getCandidateIndices(from: priorityTokens)
//                let candidates = candidateIndices.map { allFoods[$0] }
//                pool = candidates.filter { f in
//                    if !requiredHeads.isEmpty {
//                        let tokens = Set(f.searchTokens.map(Self.stem))
//                        return requiredHeads.contains { req in tokens.contains(req) || f.nameNormalized.contains(req) }
//                    }
//                    return true
//                }
//                if verboseAISearchLogging { logger.debug("Pool(priorityKeywords)=\(pool.count)") }
//            }
//
//            if pool.isEmpty {
//                let queryTokens = Set(Self.tokenize(raw)).union(cuisineTokens)
//                let candidateIndices = getCandidateIndices(from: queryTokens)
//                let candidates = candidateIndices.map { allFoods[$0] }
//                pool = candidates.filter { f in
//                    if !requiredHeads.isEmpty {
//                        let tokens = Set(f.searchTokens.map(Self.stem))
//                        return requiredHeads.contains { req in tokens.contains(req) || f.nameNormalized.contains(req) }
//                    }
//                    return true
//                }
//                if verboseAISearchLogging { logger.debug("Pool(queryOverlap)=\(pool.count)") }
//            }
//            
//            if pool.isEmpty { return [] }
//
//            let wantsForm = ["salad","soup","porridge","pudding","tea","curry","stew","smoothie"].contains { raw.lowercased().contains($0) }
//            if wantsForm {
//                pool = pool.filter { f in
//                    let n = f.nameNormalized
//                    let isSpice = n.hasPrefix("spices,") || n.hasPrefix("spice,") || n.hasPrefix("herbs,") || n.hasPrefix("herb,")
//                    if isSpice {
//                        if !requiredHeads.isEmpty {
//                            let toks = Set(f.searchTokens.map(Self.stem))
//                            return requiredHeads.contains { req in n.contains(req) || toks.contains(req) }
//                        }
//                        return false
//                    }
//                    return true
//                }
//            }
//
//            var adjPhraseBoosts = signals.phraseBoosts
//            var adjTokenWeights = signals.tokenWeights
//            if let w = adjPhraseBoosts[primary], w < 2 { adjPhraseBoosts[primary] = 2 }
//            else if adjPhraseBoosts[primary] == nil { adjPhraseBoosts[primary] = 2 }
//            if let w = adjTokenWeights[primary], w < 2 { adjTokenWeights[primary] = 2 }
//            else if adjTokenWeights[primary] == nil { adjTokenWeights[primary] = 2 }
//
//            for h in signals.headwords where raw.lowercased().contains(h) {
//                if let w = adjPhraseBoosts[h], w < 2 { adjPhraseBoosts[h] = 2 } else if adjPhraseBoosts[h] == nil { adjPhraseBoosts[h] = 2 }
//                if let w = adjTokenWeights[h], w < 2 { adjTokenWeights[h] = 2 } else if adjTokenWeights[h] == nil { adjTokenWeights[h] = 2 }
//            }
//            
//            let stats = buildTokenStats(allFoods)
//            let N = max(stats.totalDocs, 1)
//            func idf(_ term: String) -> Double {
//                let df = max(1, stats.df[Self.stem(term)] ?? 1)
//                return log2(Double(N) / Double(df))
//            }
//            var finalPhraseBoosts = adjPhraseBoosts
//            var finalTokenWeights = adjTokenWeights
//            for (k, v) in finalTokenWeights {
//                let scaled = Double(v) * max(0.25, min(3.0, idf(k)))
//                finalTokenWeights[k] = max(-8, min(8, Int(scaled.rounded())))
//            }
//            for (k, v) in finalPhraseBoosts {
//                let scaled = Double(v) * max(0.5, min(2.5, idf(k)))
//                finalPhraseBoosts[k] = max(-8, min(8, Int(scaled.rounded())))
//            }
//            let finalSignals = SearchSignals(
//                headwords: signals.headwords,
//                priorityKeywords: signals.priorityKeywords,
//                bannedKeywords: signals.bannedKeywords,
//                synonyms: signals.synonyms,
//                phraseBoosts: finalPhraseBoosts,
//                tokenWeights: finalTokenWeights,
//                negationRegex: signals.negationRegex
//            )
//
//            if verboseAISearchLogging {
//                logger.debug("AI signals headwords=\(signals.headwords.joined(separator: ",")) priority=\(signals.priorityKeywords.joined(separator: ",")) banned=\(signals.bannedKeywords.joined(separator: ","))")
//                logger.debug("AI phraseBoosts(final)=\(self.formatWeights(finalSignals.phraseBoosts)) tokenWeights(final)=\(self.formatWeights(finalSignals.tokenWeights))")
//                logger.debug("Chosen primary=\(primary) (stem=\(priStem)) for query=\(raw)")
//            }
//
//            let negFiltered: [SearchableFoodItem]
//            if let neg = signals.negationRegex, !neg.isEmpty {
//                let terms = signals.headwords + signals.priorityKeywords
//                negFiltered = pool.filter { f in
//                    !matchesNegation(neg, in: f.nameNormalized, terms: terms)
//                }
//            } else {
//                negFiltered = pool
//            }
//            let qTokens = Set(Self.tokenize(raw))
//
//            if wantsForm && negFiltered.isEmpty {
//                let formTokens = ["salad","soup","porridge","pudding","tea","curry","stew","smoothie"]
//                if let form = formTokens.first(where: { raw.lowercased().contains($0) }) {
//                    if let formIndices = invertedIndex[form] {
//                        let fallback = formIndices.map { allFoods[$0] }.filter { f in
//                             !f.nameNormalized.hasPrefix("spices,") && !f.nameNormalized.hasPrefix("spice,") && !f.nameNormalized.hasPrefix("herbs,") && !f.nameNormalized.hasPrefix("herb,")
//                        }
//                        if !fallback.isEmpty {
//                            let rankedFallback = fallback.map { ($0, computeScore(item: $0, rawQuery: raw, queryTokens: qTokens, signals: finalSignals, primary: primary, priStem: priStem)) }
//                                .sorted { (lhs, rhs) in
//                                    if lhs.1.total != rhs.1.total { return lhs.1.total > rhs.1.total }
//                                    return lhs.0.name.localizedCompare(rhs.0.name) == .orderedAscending
//                                }
//                            return Array(rankedFallback.prefix(limit)).map { $0.0.persistentModelID }
//                        }
//                    }
//                }
//            }
//            
//            // --- CHECK 5: Преди потенциално бавните map и sort ---
//            try Task.checkCancellation()
//
//            let scored: [(SearchableFoodItem, ScoreComponents)] = negFiltered.map { item in
//                (item, computeScore(item: item, rawQuery: raw, queryTokens: qTokens, signals: finalSignals, primary: primary, priStem: priStem))
//            }
//            let ranked = scored.sorted { (lhs, rhs) in
//                if lhs.1.total != rhs.1.total { return lhs.1.total > rhs.1.total }
//                return lhs.0.name.localizedCompare(rhs.0.name) == .orderedAscending
//            }
//            
//            // --- CHECK 6: След сортирането и преди финалните проверки ---
//            try Task.checkCancellation()
//
//            if verboseAISearchLogging {
//                let top = ranked.prefix(15)
//                for (idx, entry) in top.enumerated() {
//                    let (f, sc) = entry
//                    logger.debug("#\(idx+1) \(f.name) • total=\(sc.total) [overlap=\(sc.overlap) phrase=\(sc.phrase) banned=\(sc.banned) brevity=\(sc.brevity)]")
//                }
//                if let first = ranked.first?.1.total, let last = ranked.last?.1.total {
//                    logger.debug("Score range: top=\(first) bottom=\(last) • items=\(ranked.count)")
//                }
//            }
//            
//            let requiredTokens: Set<String> = {
//                var t = Set(Self.tokenize(raw))
//                if let c = context, !c.isEmpty { t.formUnion(Set(Self.tokenize(c))) }
//                t.formUnion(cuisineTokens)
//                return t
//            }()
//            let topK = ranked.prefix(10)
//            let maxCover = topK.map { entry -> Int in
//                let toks = Set(entry.0.searchTokens.map(Self.stem))
//                return requiredTokens.intersection(toks).count
//            }.max() ?? 0
//            if verboseAISearchLogging { logger.debug("Satisfaction: requiredTokens=\(Array(requiredTokens).joined(separator: ",")) maxTop10Coverage=\(maxCover)") }
//            if !requiredTokens.isEmpty && maxCover == 0 {
//                logger.debug("No candidate matches required query/context tokens. Returning empty to trigger generation.")
//                return []
//            }
//            if !requiredHeads.isEmpty {
//                let satisfiesHeadword = topK.contains { entry in
//                    let n = entry.0.nameNormalized
//                    let toks = Set(entry.0.searchTokens.map(Self.stem))
//                    return requiredHeads.contains { req in n.contains(req) || toks.contains(req) }
//                }
//                if !satisfiesHeadword {
//                    logger.debug("No top candidates contain required headword(s): \(Array(requiredHeads).joined(separator: ","))). Returning empty to trigger generation.")
//                    return []
//                }
//            }
//            
//            logRanked("AI results for '\(raw)'", ranked: ranked, limit: limit)
//            return Array(ranked.prefix(limit)).map { $0.0.persistentModelID }
//        } catch {
//            if error is CancellationError {
//                logger.info("Search for '\(raw)' was cancelled.")
//            } else {
//                logger.error("An error occurred during AI search for '\(raw)': \(error.localizedDescription)")
//            }
//            return []
//        }
//    }
//
//    // MARK: - Public Search Method (Classic)
//    // MODIFIED: This method is now optimized to use the inverted index.
//    func searchFoods(query: String, limit: Int = 50) -> [PersistentIdentifier] {
//        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
//        guard !raw.isEmpty else { return [] }
//        
//        let queryTokens = Self.tokenize(raw)
//        guard let firstWord = queryTokens.first else { return [] }
//        
//        let expandedQueryTokens = Self.expandPluralVariants(queryTokens)
//        if expandedQueryTokens.isEmpty { return [] }
//
//        guard !allFoods.isEmpty else { return [] }
//        
//        // --- Perfect Match using Inverted Index ---
//        var perfectMatchIndices: Set<Int>?
//        for token in expandedQueryTokens {
//            guard let tokenIndices = invertedIndex[token] else {
//                perfectMatchIndices = nil // A token was not found, so no perfect match is possible
//                break
//            }
//            if perfectMatchIndices == nil {
//                perfectMatchIndices = Set(tokenIndices)
//            } else {
//                perfectMatchIndices?.formIntersection(tokenIndices)
//            }
//        }
//        
//        if let indices = perfectMatchIndices, !indices.isEmpty {
//            let perfectMatchCandidates = indices.map { allFoods[$0] }
//            let sortedResults = scoreAndSort(
//                candidates: perfectMatchCandidates,
//                queryTokens: expandedQueryTokens
//            )
//            logItems("Classic results (perfect match) for '\(raw)'", items: sortedResults, limit: limit)
//            return Array(sortedResults.prefix(limit)).map { $0.persistentModelID }
//        }
//        
//        // --- Fallback using Inverted Index on the first word ---
//        let firstWordStemmed = Self.stem(firstWord)
//        if let fallbackIndices = invertedIndex[firstWordStemmed] {
//            let fallbackCandidates = fallbackIndices.map { allFoods[$0] }
//            let sortedFallbackResults = scoreAndSort(
//                candidates: fallbackCandidates,
//                queryTokens: expandedQueryTokens
//            )
//            logItems("Classic results (fallback) for '\(raw)'", items: sortedFallbackResults, limit: limit)
//            return Array(sortedFallbackResults.prefix(limit)).map { $0.persistentModelID }
//        }
//        
//        return [] // No matches found
//    }
//
//    // MARK: - Sorting (Classic)
//    private func scoreAndSort(
//        candidates: [SearchableFoodItem],
//        queryTokens: [String]
//    ) -> [SearchableFoodItem] {
//        let querySet = Set(queryTokens)
//
//        let sorted = candidates.sorted { (foodA, foodB) in
//            let tokensA = foodA.searchTokens.map(Self.stem)
//            let tokensB = foodB.searchTokens.map(Self.stem)
//            let setA = Set(tokensA)
//            let setB = Set(tokensB)
//            
//            let matchCountA = querySet.intersection(setA).count
//            let matchCountB = querySet.intersection(setB).count
//            if matchCountA != matchCountB {
//                return matchCountA > matchCountB
//            }
//            
//            if tokensA.count != tokensB.count {
//                return tokensA.count < tokensB.count
//            }
//            
//            return foodA.name.localizedCompare(foodB.name) == .orderedAscending
//        }
//        
//        return sorted
//    }
//
//    // MARK: - NLP helpers
//    static func tokenize(_ s: String) -> [String] {
//        return FoodItem.makeTokens(from: s).map(stem).filter { !$0.isEmpty }
//    }
//    
//    static func expandPluralVariants(_ tokens: [String]) -> [String] {
//        var expanded = Set<String>(tokens)
//        for token in tokens {
//            if token.hasSuffix("y") {
//                expanded.insert(String(token.dropLast()) + "ies")
//            } else if token.hasSuffix("s") {
//                expanded.insert(String(token.dropLast()))
//            } else {
//                expanded.insert(token + "s")
//            }
//        }
//        return Array(expanded)
//    }
//    
//    static func stem(_ t: String) -> String {
//        var s = t
//        if s.hasSuffix("ies") { s.removeLast(3); s += "y"; return s }
//        if s.hasSuffix("es")  { s.removeLast(2); return s }
//        if s.hasSuffix("s")   { s.removeLast();  return s }
//        return s
//    }
//
//    // MARK: - Logging
//    private func logItems(_ title: String, items: [SearchableFoodItem], limit: Int) {
//        guard verboseAISearchLogging else { return }
//        let head = "🔎 \(title) • \(min(items.count, limit))/\(items.count) results"
//        logger.debug("\(head, privacy: .public)")
//        for (idx, f) in items.prefix(limit).enumerated() {
//            let line = "#\(idx+1) \(f.name)  • id=\(String(describing: f.persistentModelID))"
//            logger.debug("\(line, privacy: .public)")
//            #if DEBUG
//            print(line)
//            #endif
//        }
//    }
//
//    @available(iOS 26.0, macOS 15.0, *)
//    private func logRanked(_ title: String, ranked: [(SearchableFoodItem, ScoreComponents)], limit: Int) {
//        guard verboseAISearchLogging else { return }
//        let head = "🔎 \(title) • \(min(ranked.count, limit))/\(ranked.count) results"
//        logger.debug("\(head, privacy: .public)")
//        for (idx, entry) in ranked.prefix(limit).enumerated() {
//            let (f, sc) = entry
//            let line = "#\(idx+1) \(f.name)  • id=\(String(describing: f.persistentModelID))  • score=\(sc.total) [overlap=\(sc.overlap) phrase=\(sc.phrase) banned=\(sc.banned) brevity=\(sc.brevity)]"
//            logger.debug("\(line, privacy: .public)")
//            #if DEBUG
//            print(line)
//            #endif
//        }
//    }
//    
//    // MARK: - Public Smart API (fallbacks on older OS + AI availability)
//    func searchFoodsAI(
//        query: String,
//        limit: Int = 50,
//        context: String? = nil
//    ) async -> [PersistentIdentifier] {
//        if #available(iOS 26.0, macOS 15.0, *),
//           GlobalState.aiAvailability == .available {
//            // Apple Intelligence e наличен → ползваме AI търсене
//            return await _searchFoodsAI(
//                query: query,
//                limit: limit,
//                context: context,
//                requiredHeadwords: nil
//            )
//        } else {
//            // OS е стар ИЛИ AI не е available → fallback към класическото търсене
//            logger.debug("AI search unavailable (status=\(String(describing: GlobalState.aiAvailability))); falling back to classic search.")
//            return searchFoods(query: query, limit: limit)
//        }
//    }
//
//    func searchFoodsAI(
//        query: String,
//        limit: Int = 50,
//        context: String? = nil,
//        requiredHeadwords: [String]? = nil
//    ) async -> [PersistentIdentifier] {
//        if #available(iOS 26.0, macOS 15.0, *),
//           GlobalState.aiAvailability == .available {
//            // Apple Intelligence e наличен → ползваме AI търсене с headwords
//            return await _searchFoodsAI(
//                query: query,
//                limit: limit,
//                context: context,
//                requiredHeadwords: requiredHeadwords
//            )
//        } else {
//            // OS е стар ИЛИ AI не е available → fallback към класическото търсене
//            logger.debug("AI search (with headwords) unavailable (status=\(String(describing: GlobalState.aiAvailability))); falling back to classic search.")
//            return searchFoods(query: query, limit: limit)
//        }
//    }
//
//}
