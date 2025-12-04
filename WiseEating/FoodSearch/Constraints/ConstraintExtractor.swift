import Foundation

/// Thin facade over NumberRangeExtractor + NumberRangeParser.
/// Turns raw query text into normalized DietaryConstraint objects.
enum ConstraintExtractor {
    @MainActor private static let extractor = NumberRangeExtractor()
    @MainActor private static let parser = NumberRangeParser()
    
    /// Parse the user query into a flat list of DietaryConstraint entries.
    /// Each entry represents a single logical comparison:
    ///   - subject: normalized nutrient / diet / allergen / pH label
    ///   - comparison: <, <=, >, >=, =, !=
    ///   - value / value2: numeric values, if present
    ///   - unit: "mg", "g", "kg", "%", etc., if present
    @MainActor static func extract(from query: String) -> [DietaryConstraint] {
        let candidates = extractor.extract(from: query)
        return candidates.flatMap { parser.parse(candidate: $0) }
    }
}
