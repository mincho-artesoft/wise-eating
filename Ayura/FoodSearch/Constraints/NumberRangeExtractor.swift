//
//  NumberRangeExtractor.swift
//  DietaryScanner
//
//  Created by Mincho Milev on 28.11.25.
//

import Foundation

class NumberRangeExtractor {
    
    struct ExtractionCandidate {
        let subjectText: String
        let operatorText: String?
        let valueText: String?
        let secondValueText: String?
        let unitText: String?
        let operatorText2: String?
        let unitText2: String?
        let matchedText: String
        let isAbstract: Bool
    }
    
    // --- REGEX COMPONENTS ---
    
    private let unitPart = #"(?:[\s-]*(?<unit>mg|mcg|kg|g|t|lbs?|oz|ml|l|iu|kcal|%)(?=\W|$))?"#
    private let unitPart2 = #"(?:[\s-]*(?<unit2>mg|mcg|kg|g|t|lbs?|oz|ml|l|iu|kcal|%)(?=\W|$))?"#
    
    private let numPart = #"(?<value>\d+(?:\.\d+)?|one|two|three|four|five|six|seven|eight|nine|ten|twenty)"#
    private let numPart2 = #"(?<value2>\d+(?:\.\d+)?|one|two|three|four|five|six|seven|eight|nine|ten|twenty)"#
    private let rangePart = #"(?:\s*(?:-|to)\s*(?<value2>\d+(?:\.\d+)?))?"#
    
    // Numeric Operators (>, <, =, etc)
    private let opPart = #"(?<operator><=|>=|==|<|>|max|min|maximum|minimum|minimal|maximal|at least|at most|no more than|not exceeding|up to|limit to|cap at|more than|less than|greater than|lower than|under|over|above|below|exceeds|equals|equal to|is|exactly|around|about|approx|approximately|close to|source of|free of|free from|without|lack|lacks|no|zero|non|minus|except|avoid|exclude|excluding|excepting|nix|none|never|not|=)?"#
    
    private let opPart2 = #"(?<operator2><=|>=|==|<|>|max|min|maximum|minimum|at least|at most|no more than|not exceeding|up to|limit to|cap at|more than|less than|greater than|lower than|under|over|above|below|exceeds|equals|equal to|is|exactly|=)"#
    
    // ABSTRACT OPERATORS
    // Includes: High, Low, Rich, Poor, Free, Zero, Lite, Light, Heavy, Most, Least
    private let abstractOpPart = #"(?<abstractOp>high potency|potency|high|highest|most|rich in|rich|poor in|poor|free of|free|no|without|non|minus|except|zero|not|never|nix|none|avoid|exclude|excluding|excepting|contains|has|source of|heavy|with|more than|greater than|less than|least|minimal|lowest|lower|low|lite|light|under|over|above|below|exceeds|neutral|balanced|normal|basic)?"#
    
    private let postUnitNoise = #"(?:(?:\s*[/,]\s*|\s+per\s+|\s+)(?:serving|capsule|tablet|scoop|bar|ml|g|softgel|gummy|dose|day|daily|amount|value|liquid|syrup|solution|drops)s?)?"#
    
    private let connector = #"(?:\s*[-:\/\(\)]\s*|\s+(?:of|in|with|as|from)\s+|\s*(?=[<>=])|\s+)"#
    
    private let subjectRaw = #"(?<subject>[a-zA-Z0-9\s%\-\(\)\.,]+?)"#
    
    private var patterns: [String] {
        return [
            // 1. EXPLICIT "BETWEEN": "Between 5 and 10g Protein"
            #"(?:between|from)\s+"# + numPart + #"\s+(?:and|to|-)\s+"# + numPart2 + unitPart + postUnitNoise + #"\s+(?:of\s+)?(?<subject>[a-zA-Z0-9\s%\-\(\)]+)"#,
            
            // 2. VALUE FIRST: "more than 10 vitamin c", ">= 5g fat", etc.
            // IMPORTANT: subject stops before the next comparator keyword or end-of-string,
            // so sequences like "... more than 10 vitamin c more than 14 fat" become
            // TWO matches: [10 vitamin c] and [14 fat].
            opPart
                + #"\s*"# + numPart
                + rangePart
                + unitPart
                + postUnitNoise
                + connector
                + #"(?<subject>[a-zA-Z0-9\s\(\)\-%]+?)(?=\s+(?:and\s+)?(?:more than|less than|greater than|lower than|under|over|above|below|exceeds|at least|at most|no more than|not exceeding|up to|limit to|cap at|<=|>=|<|>|=)\b|$)"#,
            
            // 3. SUBJECT FIRST: "sugar < 5g"
            subjectRaw + connector + opPart + #"\s*"# + numPart + rangePart + unitPart + postUnitNoise + #"(?=$|\s|[\),])"#,
            
            // 4. ABSTRACT (Subject First) - "Tomatoes Low Acid" matches "Low Acid"
            subjectRaw + connector + abstractOpPart + #"(?=$|\s|[\),])"#,
            
            // 5. ABSTRACT (Op First) - "High pH", "Low Fat", "No Sugar", "Vegan"
            // Note: AbstractOp is optional in regex, but we filter later if both op and value are nil.
            abstractOpPart + #"\s+(?:of\s+)?(?<subject>[a-zA-Z0-9\s\(\)\-%]+)"#,
            
            // 6. DANGLING OP (Fallback)
            opPart + #"\s+(?:of\s+)?(?<subject>[a-zA-Z0-9\s\(\)\-%]+)"#
        ]
    }
    
    func extract(from input: String) -> [ExtractionCandidate] {
        var candidates: [ExtractionCandidate] = []
        let processedInput = input
        
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(location: 0, length: processedInput.utf16.count)
            let matches = regex.matches(in: processedInput, options: [], range: range)
            
            for match in matches {
                let subject = match.groupValue(named: "subject", in: processedInput)
                let value = match.groupValue(named: "value", in: processedInput)
                let abstractOp = match.groupValue(named: "abstractOp", in: processedInput)
                let opFromGroup = match.groupValue(named: "operator", in: processedInput)
                
                guard let finalSubject = subject else { continue }
                if value == nil && abstractOp == nil && opFromGroup == nil {
                    // Special case: If the subject itself is a Diet (e.g. "Vegan"), treat it as Abstract.
                    if SearchKnowledgeBase.shared.isValidSubject(finalSubject) == false { continue }
                }
                
                var op = opFromGroup ?? abstractOp
                let lowerInput = processedInput.lowercased()
                
                if (lowerInput.contains("between") || lowerInput.contains("from")) && op == nil && value != nil {
                    op = "between"
                }
                
                let val2 = match.groupValue(named: "value2", in: processedInput)
                let op2 = match.groupValue(named: "operator2", in: processedInput)
                let unit = match.groupValue(named: "unit", in: processedInput)
                let unit2 = match.groupValue(named: "unit2", in: processedInput)
                let fullMatchString = String(processedInput[Range(match.range, in: processedInput)!])
                
                // --- SUBJECT CLEANING ---
                var cleanSubject = cleanSubjectText(finalSubject)
                
                // If regex captured "Low Fat" as subject, strip "Low"
                let adj = ["low ", "high ", "more than ", "less than ", "neutral ", "balanced ", "normal ", "least ", "most ", "minimal ", "rich ", "free ", "no ", "non "]
                for a in adj {
                    if cleanSubject.lowercased().hasPrefix(a) {
                        cleanSubject = String(cleanSubject.dropFirst(a.count)).trimmingCharacters(in: .whitespaces)
                    }
                }
                
                cleanSubject = normalizeSubjectAlias(cleanSubject)
                
                // --- VALIDATION ---
                // "tomatoes" -> False (unless in map). "Protein" -> True. "Acid" -> True.
                if !SearchKnowledgeBase.shared.isValidSubject(cleanSubject) { continue }
                
                // Deduplicate
                if candidates.contains(where: { $0.matchedText == fullMatchString }) { continue }
                
                let isAbstract = (value == nil)
                
                candidates.append(ExtractionCandidate(
                    subjectText: cleanSubject,
                    operatorText: op?.trimmingCharacters(in: .whitespacesAndNewlines),
                    valueText: value?.trimmingCharacters(in: .whitespacesAndNewlines),
                    secondValueText: val2?.trimmingCharacters(in: .whitespacesAndNewlines),
                    unitText: unit?.trimmingCharacters(in: .whitespacesAndNewlines),
                    operatorText2: op2?.trimmingCharacters(in: .whitespacesAndNewlines),
                    unitText2: unit2?.trimmingCharacters(in: .whitespacesAndNewlines),
                    matchedText: fullMatchString,
                    isAbstract: isAbstract
                ))
            }
        }
        return candidates
    }
    
    private func normalizeSubjectAlias(_ text: String) -> String {
        let lower = text.lowercased()
        if lower == "b12" { return "vitamin b12" }
        if lower == "vit c" { return "vitamin c" }
        if lower == "vit d" { return "vitamin d" }
        if lower == "ph." || lower == "p.h" || lower == "p.h." { return "ph" }
        return text
    }
    
    private func cleanSubjectText(_ text: String) -> String {
        var clean = text
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "-", with: " ")
        
        let noiseWords = [
            "softgels", "per tablet", "serving", "vs", "type", "style", "per scoop",
            "per 100g", "syrup", "liquid", "bar", "capsule", "products", "more than", "less than", "of",
            "foods", "food", "diet", "intake"
        ]
        
        for word in noiseWords {
            clean = clean.replacingOccurrences(of: word, with: "", options: .caseInsensitive, range: nil)
        }
        
        if clean.lowercased().hasSuffix(" free") { clean = String(clean.dropLast(5)) }
        
        return clean.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}
