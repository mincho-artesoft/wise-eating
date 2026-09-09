import Foundation

struct ConstraintQueryBoundary: Sendable {
    let tokens: [String]
    private let tokenSet: Set<String>

    init(_ query: String) {
        let parsedTokens = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        tokens = parsedTokens
        tokenSet = Set(parsedTokens)
    }

    func count(of token: String) -> Int {
        tokens.count { $0 == token.lowercased() }
    }

    func containsToken(_ token: String) -> Bool {
        tokenSet.contains(token.lowercased())
    }

    func containsAnyToken(_ candidates: Set<String>) -> Bool {
        !tokenSet.isDisjoint(with: candidates)
    }

    func containsPhrase(_ phrase: [String]) -> Bool {
        let normalized = phrase.map { $0.lowercased() }
        guard !normalized.isEmpty, normalized.count <= tokens.count else {
            return false
        }
        for start in 0...(tokens.count - normalized.count) {
            if Array(tokens[start..<(start + normalized.count)]) == normalized {
                return true
            }
        }
        return false
    }

    func containsFreeConstraint(
        knowledgeBase: SearchKnowledgeBase = .shared
    ) -> Bool {
        for (index, token) in tokens.enumerated() where token == "free" {
            if hasValidSubject(
                before: index,
                knowledgeBase: knowledgeBase
            ) {
                return true
            }
            if index + 2 < tokens.count,
               ["of", "from"].contains(tokens[index + 1]),
               hasValidSubject(
                after: index + 1,
                knowledgeBase: knowledgeBase
               ) {
                return true
            }
        }
        return false
    }

    private func hasValidSubject(
        before end: Int,
        knowledgeBase: SearchKnowledgeBase
    ) -> Bool {
        let maximumLength = min(3, end)
        guard maximumLength > 0 else { return false }
        for length in 1...maximumLength {
            let start = end - length
            let candidate = tokens[start..<end].joined(separator: " ")
            if knowledgeBase.isValidSubject(candidate) {
                return true
            }
        }
        return false
    }

    private func hasValidSubject(
        after start: Int,
        knowledgeBase: SearchKnowledgeBase
    ) -> Bool {
        let available = tokens.count - start - 1
        let maximumLength = min(3, available)
        guard maximumLength > 0 else { return false }
        for length in 1...maximumLength {
            let end = start + 1 + length
            let candidate = tokens[(start + 1)..<end].joined(separator: " ")
            if knowledgeBase.isValidSubject(candidate) {
                return true
            }
        }
        return false
    }
}
