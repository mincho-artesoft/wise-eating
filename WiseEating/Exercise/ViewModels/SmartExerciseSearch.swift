// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth2/WiseEating/AI/SmartExerciseSearch.swift ====
import Foundation
import SwiftData
import FoundationModels
import os

// MARK: - SmartExerciseSearch (inverted-index + AI signals + cached snapshot)

final class SmartExerciseSearch: Sendable {

    // 1) Минимален, Sendable снимък за търсене (никакви Model/Context вътре)
    private struct SearchableExerciseItem: Sendable {
        let persistentModelID: PersistentIdentifier
        let name: String
        let nameNormalized: String
        let searchTokens: [String]
    }

    // 2) DI контейнер (ползва се само в init за fetch)
    private let container: ModelContainer

    // 3) Кеширани данни за търсене
    private let allExercises: [SearchableExerciseItem]
    private let invertedIndex: [String: [Int]]          // stemmedToken -> [indices in allExercises]
    private let signalCache = NSCache<NSString, NSData>() // AI signals cache

    private let logger = Logger(subsystem: "com.yourapp.exercise", category: "SmartExerciseSearch")
    private let verboseAISearchLogging = true

    // MARK: - Init: fetch -> map -> index
    init(container: ModelContainer) {
        self.container = container

        let ctx = ModelContext(container)
        let descriptor = FetchDescriptor<ExerciseItem>()

        let snapshot: [SearchableExerciseItem]
        do {
            let fetched = try ctx.fetch(descriptor)
            snapshot = fetched.map { ex in
                SearchableExerciseItem(
                    persistentModelID: ex.persistentModelID,
                    name: ex.name,
                    nameNormalized: ex.nameNormalized,
                    searchTokens: ex.searchTokens
                )
            }
        } catch {
            snapshot = []
//            logger.error("Failed to fetch exercise items during initialization: \(error.localizedDescription)")
        }
        self.allExercises = snapshot

        var indexBuilder: [String: [Int]] = [:]
        for (idx, item) in snapshot.enumerated() {
            let uniqueStemmed = Set(item.searchTokens.map(Self.stem))
            for tok in uniqueStemmed {
                indexBuilder[tok, default: []].append(idx)
            }
        }
        self.invertedIndex = indexBuilder

//        logger.info("SmartExerciseSearch initialized. Cached \(self.allExercises.count) items and built index with \(self.invertedIndex.keys.count) unique tokens.")
    }

    // Бързо вадене на candidate indices по множество токени (union, не intersection)
    private func getCandidateIndices(from tokens: Set<String>) -> Set<Int> {
        guard !tokens.isEmpty else { return [] }
        var out: Set<Int> = []
        for t in tokens {
            if let ids = invertedIndex[t] { out.formUnion(ids) }
        }
        return out
    }

    // MARK: - AI Schema (Generable)
    @available(iOS 26.0, macOS 15.0, *)
    @Generable
    struct AISearchSignals: Codable {
        @Guide(description: "Anchor terms ordered by importance. Central exercise concept (e.g., 'squat', 'push-up', 'workout'). Lowercase.", .count(1...3))
        let headwords: [String]

        @Guide(description: "Supporting generic terms (equipment, body parts, style: 'dumbbell', 'barbell', 'bodyweight', 'mobility', 'hiit', 'strength', 'cardio'). No brands. Lowercase.", .count(0...8))
        let priorityKeywords: [String]

        @Guide(description: "Tokens to avoid (e.g., 'tips', 'article', 'guide' when you want concrete exercises). Lowercase.", .count(0...8))
        let bannedKeywords: [String]

        @Guide(description: "Generic lexical variants. Keys ≤8, values ≤6. Lowercase.", .count(0...8))
        let synonyms: [SynonymsEntry]

        @Guide(description: "Phrase weights −8..+8. ≤8 entries.")
        let phraseBoosts: [WeightedPhrase]

        @Guide(description: "Token/phrase weights −8..+8. ≤16 entries.")
        let tokenWeights: [WeightedToken]

        @Guide(description: "Optional regex for negations; or null.")
        let negationRegex: String?
    }

    @available(iOS 26.0, macOS 15.0, *)
    @Generable
    struct SynonymsEntry: Codable {
        let key: String
        @Guide(description: "1–6 lowercase variants", .count(1...6))
        let variants: [String]
    }

    @available(iOS 26.0, macOS 15.0, *)
    @Generable
    struct WeightedPhrase: Codable { let key: String; let weight: Int }

    @available(iOS 26.0, macOS 15.0, *)
    @Generable
    struct WeightedToken: Codable { let key: String; let weight: Int }

    // Вътрешно представяне на сигналите (по-комфортно за работа)
    @available(iOS 26.0, macOS 15.0, *)
    private struct SearchSignals: Codable, Sendable {
        let headwords: [String]
        let priorityKeywords: [String]
        let bannedKeywords: [String]
        let synonyms: [String: [String]]
        let phraseBoosts: [String: Int]
        let tokenWeights: [String: Int]
        let negationRegex: String?
    }

    @available(iOS 26.0, macOS 15.0, *)
    private static func validate(_ s: SearchSignals) -> SearchSignals? {
        func isLower(_ t: String) -> Bool { t == t.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        func clamp(_ d: [String:Int], _ n: Int) -> [String:Int] {
            d.prefix(n).reduce(into: [:]) { acc, kv in
                let (k, v) = kv; guard isLower(k) else { return }
                acc[k] = max(-8, min(8, v))
            }
        }
        let hw = Array(Set(s.headwords.filter { !$0.isEmpty && isLower($0) })).prefix(3)
        guard !hw.isEmpty else { return nil }
        let pk = Array(Set(s.priorityKeywords.filter { !$0.isEmpty && isLower($0) })).prefix(8)
        let bk = Array(Set(s.bannedKeywords.filter { !$0.isEmpty && isLower($0) })).prefix(8)

        var syn: [String:[String]] = [:]
        for (k, vs) in s.synonyms.prefix(8) {
            guard isLower(k) else { continue }
            let vv = Array(Set(vs.filter { !$0.isEmpty && isLower($0) })).prefix(6)
            if !vv.isEmpty { syn[k] = Array(vv) }
        }

        return SearchSignals(
            headwords: Array(hw),
            priorityKeywords: Array(pk),
            bannedKeywords: Array(bk),
            synonyms: syn,
            phraseBoosts: clamp(s.phraseBoosts, 8),
            tokenWeights: clamp(s.tokenWeights, 16),
            negationRegex: (s.negationRegex?.isEmpty == true) ? nil : s.negationRegex
        )
    }

    // MARK: - AI signals generation + caching
    @available(iOS 26.0, macOS 15.0, *)
    private func generateSignals(for query: String, context: String?) async throws -> SearchSignals? {
        try Task.checkCancellation()
        
        let cacheKey = "\(query)|\(context ?? "")" as NSString
        if let cached = signalCache.object(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode(SearchSignals.self, from: cached as Data) {
//            logger.debug("AI Signals cache HIT for query: '\(query)'")
            return decoded
        }
//        logger.debug("AI Signals cache MISS for query: '\(query)'")

        var prompt = """
Analyze the user query about exercises/workouts and emit compact, generic lexical search signals. Output only JSON.

Query:
\(query)
"""
        if let c = context, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += "\nAdditional context (optional):\n\(c)\n"
        }

        let options = GenerationOptions(sampling: .random(top: 50), temperature: 0.7)
        do {
            let session = LanguageModelSession(instructions: Instructions { "Return ONLY JSON per schema." })
            let content = try await session.respond(
                to: prompt,
                generating: AISearchSignals.self,
                includeSchemaInPrompt: true,
                options: options
            ).content
            
            try Task.checkCancellation()

            var syn: [String:[String]] = [:]; content.synonyms.forEach { syn[$0.key] = $0.variants }
            var phrases: [String:Int] = [:]; content.phraseBoosts.forEach { phrases[$0.key] = $0.weight }
            var tokens:  [String:Int] = [:]; content.tokenWeights.forEach { tokens[$0.key]  = $0.weight }

            let s = SearchSignals(
                headwords: content.headwords,
                priorityKeywords: content.priorityKeywords,
                bannedKeywords: content.bannedKeywords,
                synonyms: syn,
                phraseBoosts: phrases,
                tokenWeights: tokens,
                negationRegex: content.negationRegex
            )
            if let validated = Self.validate(s),
               let data = try? JSONEncoder().encode(validated) {
                signalCache.setObject(data as NSData, forKey: cacheKey)
                return validated
            }
            return nil
        } catch {
            if !(error is CancellationError) {
//                logger.error("AI signals failed: \(String(describing: error))")
            }
            throw error
        }
    }

    // MARK: - NLP helpers (shared with Food)
    static func stem(_ t: String) -> String {
        var s = t
        if s.hasSuffix("ies") { s.removeLast(3); s += "y"; return s }
        if s.hasSuffix("es")  { s.removeLast(2); return s }
        if s.hasSuffix("s")   { s.removeLast();  return s }
        return s
    }

    static func tokenize(_ s: String) -> [String] {
        // Важно: използва твоя токенизатор от ExerciseItem
        return ExerciseItem.makeTokens(from: s).map(stem).filter { !$0.isEmpty }
    }

    static func expandPluralVariants(_ tokens: [String]) -> [String] {
        var expanded = Set<String>(tokens)
        for t in tokens {
            if t.hasSuffix("y") { expanded.insert(String(t.dropLast()) + "ies") }
            else if t.hasSuffix("s") { expanded.insert(String(t.dropLast())) }
            else { expanded.insert(t + "s") }
        }
        return Array(expanded)
    }

    // MARK: - Stats & primary headword
    @available(iOS 26.0, *)
    private func buildTokenStats(_ items: [SearchableExerciseItem]) -> (df:[String:Int], tail:[String:Int], total:Int) {
        var df:[String:Int] = [:], tail:[String:Int] = [:]
        for it in items {
            let toks = it.searchTokens.map(Self.stem)
            let uniq = Set(toks)
            uniq.forEach { df[$0, default:0] += 1 }
            if let last = toks.last { tail[last, default:0] += 1 }
        }
        return (df, tail, max(items.count, 1))
    }

    @available(iOS 26.0, *)
    private func choosePrimaryHeadword(signals: SearchSignals, query: String, items: [SearchableExerciseItem]) -> String {
        let formHeads: Set<String> = [
            "workout","exercise","routine","program","circuit","set",
            "hiit","tabata","yoga","pilates","cardio","strength",
            "mobility","stretch","warmup","cooldown"
        ]
        let qTokens = Self.tokenize(query)
        let qSet = Set(qTokens)
        let lower = query.lowercased()
        func inQuery(_ h: String) -> Bool { qSet.contains(Self.stem(h)) || lower.contains(h) }

        let stats = buildTokenStats(items)
        let N = max(stats.total,1)
        func df(_ t:String)->Int { stats.df[Self.stem(t)] ?? 0 }
        func tailR(_ t:String)->Double {
            let d = max(1, df(t)); return Double(stats.tail[Self.stem(t)] ?? 0) / Double(d)
        }
        func idf(_ t:String)->Double { let d = max(1, df(t)); return log2(Double(N)/Double(d)) }

        if let form = signals.headwords.first(where: { formHeads.contains($0) && inQuery($0) }) {
            return form
        }
        let present = signals.headwords.filter { inQuery($0) }
        if !present.isEmpty {
            var idx:[String:Int] = [:]; for (i,h) in signals.headwords.enumerated(){ idx[h] = i }
            var best = present.first!, bestScore = Int.min
            for t in present {
                var s = 0
                let tr = tailR(t); if tr >= 0.5 { s += 6 } else if tr >= 0.25 { s += 3 } else if tr <= 0.1 { s -= 2 }
                s += min(4, Int(idf(t).rounded()))
                if let i = idx[t] { s += (i == 0 ? 6 : i == 1 ? 3 : 1) }
                if formHeads.contains(t) { s += 6 }
                if let w = signals.tokenWeights[t] { s += max(-8, min(8, w)) }
                if let w = signals.phraseBoosts[t] { s += max(-8, min(8, w)) }
                if s > bestScore { bestScore = s; best = t }
            }
            return best
        }
        let candidates = Array(Set(signals.headwords + signals.priorityKeywords))
        return candidates.first ?? (qTokens.last ?? lower)
    }

    // MARK: - Scoring
    private struct ScoreComponents { let overlap:Int; let phrase:Int; let banned:Int; let brevity:Int; var total:Int { overlap+phrase+banned+brevity } }

    @available(iOS 26.0, *)
    private func computeScore(
        item: SearchableExerciseItem,
        rawQuery: String,
        queryTokens: Set<String>,
        signals: SearchSignals,
        primary: String,
        priStem: String
    ) -> ScoreComponents {
        let name = item.nameNormalized
        let tokens = item.searchTokens.map(Self.stem)

        let overlap = queryTokens.intersection(Set(tokens)).count

        var phraseAccum = 0
        let hasPrimary = name.contains(primary) || tokens.contains(priStem)
        let queryHasPrimary = rawQuery.lowercased().contains(primary)
        if hasPrimary { phraseAccum += 6 } else if queryHasPrimary { phraseAccum -= 6 }
        for (p,w) in signals.phraseBoosts { if name.contains(p) { phraseAccum += w } }
        for (t,w) in signals.tokenWeights {
            if name.contains(t) || tokens.contains(Self.stem(t)) { phraseAccum += w }
        }

        var bannedPenalty = 0
        let banned = Set(signals.bannedKeywords)
        if name.split(separator: " ").contains(where: { banned.contains(String($0)) }) { bannedPenalty -= 6 }

        let brevity = -(tokens.count / 10)

        return ScoreComponents(overlap: overlap, phrase: phraseAccum, banned: bannedPenalty, brevity: brevity)
    }

    // MARK: - Negation helper
    @available(iOS 26.0, macOS 15.0, *)
    private func matchesNegation(_ regex: String, in text: String, terms: [String]) -> Bool {
        guard let re = try? NSRegularExpression(pattern: regex, options: []) else { return false }
        let t = text
        let full = NSRange(t.startIndex..<t.endIndex, in: t)
        if !terms.contains(where: { t.contains($0) }) { return false }
        return re.firstMatch(in: t, options: [], range: full) != nil
    }

    // MARK: - Public API (AI-powered)
    @available(iOS 26.0, macOS 15.0, *)
    func searchExercisesAI(
        query: String,
        limit: Int = 50,
        context: String? = nil,
        requiredHeadwords: [String]? = nil
    ) async -> [PersistentIdentifier] {
        do {
            try Task.checkCancellation()
        } catch {
            logger.info("Search cancelled at the very beginning.")
            return []
        }
        
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }

        do {
            guard let signals = try await generateSignals(for: raw, context: context) else {
                return searchExercises(query: raw, limit: limit) // fallback
            }
            try Task.checkCancellation()
            
            guard !allExercises.isEmpty else { return [] }

            // primary
            let primary = choosePrimaryHeadword(signals: signals, query: raw, items: allExercises)
            let priStem = Self.stem(primary)

            // context tokens
            let ctxTokens = Set(Self.tokenize(context ?? ""))

            // required heads (from param, already stemmed)
            var requiredHeads = Set<String>()
            if let headwords = requiredHeadwords {
                for h in headwords {
                    let s = Self.stem(h.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                    if !s.isEmpty { requiredHeads.insert(s) }
                }
            }
            
            try Task.checkCancellation()

            // ---------- Candidate Pool via inverted index ----------
            var pool: [SearchableExerciseItem] = []

            // Strategy 1: primary headword
            if let primaryIndices = invertedIndex[priStem] {
                let candidates = primaryIndices.map { allExercises[$0] }
                pool = candidates.filter { e in
                    let tokens = Set(e.searchTokens.map(Self.stem))
                    if !requiredHeads.isEmpty && !requiredHeads.contains(where: { req in tokens.contains(req) || e.nameNormalized.contains(req) }) {
                        return false
                    }
                    if ctxTokens.isEmpty { return true }
                    return !ctxTokens.isDisjoint(with: tokens) || ctxTokens.contains(where: { e.nameNormalized.contains($0) })
                }
            }
            
            try Task.checkCancellation()

            // Strategy 2: priority keywords
            if pool.isEmpty {
                let priTokens = Set(signals.priorityKeywords.map(Self.stem))
                let candidateIndices = getCandidateIndices(from: priTokens.union(ctxTokens))
                let candidates = candidateIndices.map { allExercises[$0] }
                pool = candidates.filter { e in
                    if !requiredHeads.isEmpty {
                        let toks = Set(e.searchTokens.map(Self.stem))
                        return requiredHeads.contains { req in toks.contains(req) || e.nameNormalized.contains(req) }
                    }
                    return true
                }
            }
            
            try Task.checkCancellation()

            // Strategy 3: general query overlap
            if pool.isEmpty {
                let queryTokens = Set(Self.tokenize(raw))
                let candidateIndices = getCandidateIndices(from: queryTokens.union(ctxTokens))
                let candidates = candidateIndices.map { allExercises[$0] }
                pool = candidates.filter { e in
                    if !requiredHeads.isEmpty {
                        let toks = Set(e.searchTokens.map(Self.stem))
                        return requiredHeads.contains { req in toks.contains(req) || e.nameNormalized.contains(req) }
                    }
                    return true
                }
            }
            
            try Task.checkCancellation()

            guard !pool.isEmpty else { return [] }

            // ---------- Adjust signals (ensure primary boosted) + IDF scaling ----------
            var adjPhrase = signals.phraseBoosts
            var adjToken  = signals.tokenWeights
            if let w = adjPhrase[primary], w < 2 { adjPhrase[primary] = 2 } else if adjPhrase[primary] == nil { adjPhrase[primary] = 2 }
            if let w = adjToken[primary],  w < 2 { adjToken[primary]  = 2 } else if adjToken[primary]  == nil { adjToken[primary]  = 2 }
            for h in signals.headwords where raw.lowercased().contains(h) {
                if let w = adjPhrase[h], w < 2 { adjPhrase[h] = 2 } else if adjPhrase[h] == nil { adjPhrase[h] = 2 }
                if let w = adjToken[h],  w < 2 { adjToken[h]  = 2 } else if adjToken[h]  == nil { adjToken[h]  = 2 }
            }

            let stats = buildTokenStats(allExercises) // IDF върху целия корпус
            let N = max(stats.total, 1)
            func idf(_ t:String)->Double { let d = max(1, stats.df[Self.stem(t)] ?? 1); return log2(Double(N)/Double(d)) }
            var finalPhrase = adjPhrase
            var finalToken  = adjToken
            for (k,v) in finalToken  { finalToken[k]  = max(-8, min(8, Int((Double(v) * max(0.25, min(3.0, idf(k)))).rounded()))) }
            for (k,v) in finalPhrase { finalPhrase[k] = max(-8, min(8, Int((Double(v) * max(0.5 , min(2.5, idf(k)))).rounded()))) }

            let finalSignals = SearchSignals(
                headwords: signals.headwords,
                priorityKeywords: signals.priorityKeywords,
                bannedKeywords: signals.bannedKeywords,
                synonyms: signals.synonyms,
                phraseBoosts: finalPhrase,
                tokenWeights: finalToken,
                negationRegex: signals.negationRegex
            )

            // ---------- Negation filter ----------
            let negFiltered: [SearchableExerciseItem]
            if let neg = finalSignals.negationRegex, !neg.isEmpty {
                let terms = signals.headwords + signals.priorityKeywords
                negFiltered = pool.filter { e in
                    !matchesNegation(neg, in: e.nameNormalized, terms: terms)
                }
            } else {
                negFiltered = pool
            }
            
            try Task.checkCancellation()

            // ---------- Rank ----------
            let qTokens = Set(Self.tokenize(raw))
            let scored: [(SearchableExerciseItem, ScoreComponents)] = negFiltered.map { e in
                (e, computeScore(item: e, rawQuery: raw, queryTokens: qTokens, signals: finalSignals, primary: primary, priStem: priStem))
            }
            let ranked = scored.sorted {
                if $0.1.total != $1.1.total { return $0.1.total > $1.1.total }
                return $0.0.name.localizedCompare($1.0.name) == .orderedAscending
            }
            
            try Task.checkCancellation()

            // ---------- Satisfaction checks ----------
            let requiredTokens: Set<String> = {
                var t = Set(Self.tokenize(raw))
                if let c = context, !c.isEmpty { t.formUnion(Set(Self.tokenize(c))) }
                return t
            }()
            let topK = ranked.prefix(10)
            let maxCover = topK.map { entry -> Int in
                let toks = Set(entry.0.searchTokens.map(Self.stem))
                return requiredTokens.intersection(toks).count
            }.max() ?? 0
            if !requiredTokens.isEmpty && maxCover == 0 {
                return []
            }
            if !requiredHeads.isEmpty {
                let satisfiesReq = topK.contains { entry in
                    let n = entry.0.nameNormalized
                    let toks = Set(entry.0.searchTokens.map(Self.stem))
                    return requiredHeads.contains { req in n.contains(req) || toks.contains(req) }
                }
                if !satisfiesReq {
                    return []
                }
            }

            return Array(ranked.prefix(limit)).map { $0.0.persistentModelID }
        } catch {
            if error is CancellationError {
                logger.info("Search for '\(raw)' was cancelled.")
            } else {
                logger.error("An error occurred during AI search for '\(raw)': \(error.localizedDescription)")
            }
            return []
        }
    }

    // MARK: - Classic search (optimized via inverted index)
    func searchExercises(query: String, limit: Int = 50) -> [PersistentIdentifier] {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }

        let queryTokens = Self.tokenize(raw)
        guard let firstWord = queryTokens.first else { return [] }

        let expanded = Self.expandPluralVariants(queryTokens)
        guard !expanded.isEmpty else { return [] }
        guard !allExercises.isEmpty else { return [] }

        // Perfect match = intersection на индексите за всички токени
        var perfectMatch: Set<Int>?
        for tok in expanded {
            guard let ids = invertedIndex[tok] else {
                perfectMatch = nil
                break
            }
            if perfectMatch == nil { perfectMatch = Set(ids) }
            else { perfectMatch?.formIntersection(ids) }
        }
        if let indices = perfectMatch, !indices.isEmpty {
            let candidates = indices.map { allExercises[$0] }
            let sorted = scoreAndSort(candidates: candidates, queryTokens: expanded)
            logItems("Classic (perfect) '\(raw)'", items: sorted, limit: limit)
            return Array(sorted.prefix(limit)).map { $0.persistentModelID }
        }

        // Fallback: първата дума
        let firstStem = Self.stem(firstWord)
        if let fallbackIdx = invertedIndex[firstStem] {
            let candidates = fallbackIdx.map { allExercises[$0] }
            let sorted = scoreAndSort(candidates: candidates, queryTokens: expanded)
            logItems("Classic (fallback) '\(raw)'", items: sorted, limit: limit)
            return Array(sorted.prefix(limit)).map { $0.persistentModelID }
        }

        return []
    }

    // MARK: - Classic ranking
    private func scoreAndSort(
        candidates: [SearchableExerciseItem],
        queryTokens: [String]
    ) -> [SearchableExerciseItem] {
        let qSet = Set(queryTokens)
        return candidates.sorted { a, b in
            let ta = a.searchTokens.map(Self.stem)
            let tb = b.searchTokens.map(Self.stem)
            let sa = Set(ta), sb = Set(tb)

            let ca = qSet.intersection(sa).count
            let cb = qSet.intersection(sb).count
            if ca != cb { return ca > cb }

            if ta.count != tb.count { return ta.count < tb.count }

            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Logging helpers
    private func formatWeights(_ dict: [String: Int]) -> String {
        dict.map { "\($0.key):\($0.value)" }.sorted().joined(separator: ", ")
    }

    private func logItems(_ title: String, items: [SearchableExerciseItem], limit: Int) {
        guard verboseAISearchLogging else { return }
        let head = "🔎 \(title) • \(min(items.count, limit))/\(items.count) results"
//        logger.debug("\(head, privacy: .public)")
        for (idx, e) in items.prefix(limit).enumerated() {
            let line = "#\(idx+1) \(e.name)  • id=\(String(describing: e.persistentModelID))"
//            logger.debug("\(line, privacy: .public)")
            #if DEBUG
//            print(line)
            #endif
        }
    }

    @available(iOS 26.0, macOS 15.0, *)
    private func logRanked(_ title: String, ranked: [(SearchableExerciseItem, ScoreComponents)], limit: Int) {
        guard verboseAISearchLogging else { return }
        let head = "🔎 \(title) • \(min(ranked.count, limit))/\(ranked.count) results"
//        logger.debug("\(head, privacy: .public)")
        for (idx, entry) in ranked.prefix(limit).enumerated() {
            let (e, sc) = entry
//            let line = "#\(idx+1) \(e.name)  • id=\(String(describing: e.persistentModelID))  • score=\(sc.total) [overlap=\(sc.overlap) phrase=\(sc.phrase) banned=\(sc.banned) brevity=\(sc.brevity)]"
//            logger.debug("\(line, privacy: .public)")
            #if DEBUG
//            print(line)
            #endif
        }
    }
}
