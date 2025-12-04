import SwiftUI

struct NutriItem: Identifiable, Equatable {

    let id: String
    let otherId: String
    let color: Color
    let label: String
    let unit: String
    var amount: Double = 0
    var isVitamin = true
    
    let requirement: Requirement?

    //––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
    // MARK: –  Init helpers
    //––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
    init(mineral m: Mineral, demographic: String) {
        self.id = m.symbol
        self.otherId = m.id
        self.color = Color(hex: m.colorHex)
        self.label = m.symbol
        self.unit = m.unit
        self.isVitamin = false
        self.requirement = m.requirements.first { $0.demographic == demographic }
    }

    init(vitamin v: Vitamin, demographic: String) {
        self.id = v.abbreviation
        self.otherId = v.id
        self.color = Color(hex: v.colorHex)
        self.label = v.abbreviation
        self.unit = v.unit
        self.requirement = v.requirements.first { $0.demographic == demographic }
    }
    
    //––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
    // MARK: –  Computed properties
    //––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
    var dailyNeed:  Double? { requirement?.dailyNeed }
    var upperLimit: Double? { requirement?.upperLimit }

    var nutrientID: String? {
        if isVitamin{
            return "vit_" + otherId
        }else{
            return "min_" + otherId
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.amount == rhs.amount
    }
}
