//import Foundation
//import SwiftData
//import os // Importujemy os, aby używać Loggera
//
//final class SmartFoodSearch_2: Sendable {
//
//    private let container: ModelContainer
//    // Tworzymy dedykowany logger dla tej klasy, co ułatwia filtrowanie logów.
//    private let logger = Logger(subsystem: "com.yourapp.foodsearch", category: "SmartFoodSearch")
//
//    init(container: ModelContainer) { self.container = container }
//
//    // MARK: - Public Search Method
//    func searchFoods(query: String, limit: Int = 50) -> [PersistentIdentifier] {
//        
//        let ctx = ModelContext(container)
//        
//        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
//        guard !raw.isEmpty else {
//            return []
//        }
//        
//        // Wszystkie tokeny już teraz uważane są za "silne" (ważne)
//        let queryTokens = Self.tokenize(raw)
//        guard let firstWord = queryTokens.first else {
//            return []
//        }
//        
//        // Rozszerzamy słowa o możliwe formy liczby mnogiej
//        let expandedQueryTokens = Self.expandPluralVariants(queryTokens)
//        if expandedQueryTokens.isEmpty {
//            return []
//        }
//
//        let descriptor = FetchDescriptor<FoodItem>()
//        guard let allCandidates = try? ctx.fetch(descriptor), !allCandidates.isEmpty else {
//            return []
//        }
//        
//        // --- PODEJŚCIE: WYSZUKIWANIE ETAPOWE ---
//        
//        // KROK 1: Spróbuj znaleźć kandydatów, którzy zawierają WSZYSTKIE słowa z zapytania.
//        let querySet = Set(expandedQueryTokens)
//        let perfectMatchCandidates = allCandidates.filter { food in
//            let candidateSet = Set(food.searchTokens2.map(Self.stem))
//            return querySet.isSubset(of: candidateSet)
//        }
//        
//        // Jeśli mamy "idealne" dopasowania, pracujemy tylko z nimi.
//        if !perfectMatchCandidates.isEmpty {
//            let sortedResults = scoreAndSort(
//                candidates: perfectMatchCandidates,
//                queryTokens: expandedQueryTokens
//            )
//            let finalIDs = Array(sortedResults.prefix(limit)).map { $0.persistentModelID }
//            return finalIDs
//        }
//        
//        // KROK 2: Jeśli nie ma idealnych dopasowań, przechodzimy do planu awaryjnego.
//        // Tutaj wymagamy, aby tylko PIERWSZE słowo było obecne.
//        let fallbackCandidates = allCandidates.filter { food in
//            let candidateSet = Set(food.searchTokens2.map(Self.stem))
//            let firstWordStemmed = Self.stem(firstWord)
//            return candidateSet.contains(firstWordStemmed) || food.nameNormalized.contains(firstWordStemmed)
//        }
//        
//        
//        let sortedFallbackResults = scoreAndSort(
//            candidates: fallbackCandidates,
//            queryTokens: expandedQueryTokens
//        )
//        
//        let finalIDs = Array(sortedFallbackResults.prefix(limit)).map { $0.persistentModelID }
//        return finalIDs
//    }
//
//    // MARK: - Sorting
//    private func scoreAndSort(
//        candidates: [FoodItem],
//        queryTokens: [String]
//    ) -> [FoodItem] {
//        let querySet = Set(queryTokens)
//
//        // Klasyfikujemy kandydatów według kilku prostych zasad w kolejności ważności:
//        let sorted = candidates.sorted { (foodA, foodB) in
//            let tokensA = foodA.searchTokens2.map(Self.stem)
//            let tokensB = foodB.searchTokens2.map(Self.stem)
//            let setA = Set(tokensA)
//            let setB = Set(tokensB)
//            
//            // 1. Priorytet dla tego, który pasuje do większej liczby słów z zapytania
//            let matchCountA = querySet.intersection(setA).count
//            let matchCountB = querySet.intersection(setB).count
//            if matchCountA != matchCountB {
//                return matchCountA > matchCountB
//            }
//            
//            // 2. Priorytet dla krótszej nazwy (mniej zbędnych słów)
//            if tokensA.count != tokensB.count {
//                return tokensA.count < tokensB.count
//            }
//            
//            // 3. Porządek alfabetyczny jako ostatnie kryterium
//            return foodA.name.localizedCompare(foodB.name) == .orderedAscending
//        }
//        
//        return sorted
//    }
//
//    // MARK: - NLP helpers
//    static func tokenize(_ s: String) -> [String] {
//        return FoodItem.makeTokens2(from: s).map(stem).filter { !$0.isEmpty }
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
//}
//
