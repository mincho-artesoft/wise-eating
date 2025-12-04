import SwiftData
import Foundation

@Model
public final class AminoAcidsData: Identifiable {
    @Attribute(.unique) public var id = UUID()

    // Съвпадат 1:1 с генератора ("amino_acids")
    public var alanine:         Nutrient?
    public var arginine:        Nutrient?
    public var asparticAcid:    Nutrient?
    public var cystine:         Nutrient?
    public var glutamicAcid:    Nutrient?
    public var glycine:         Nutrient?
    public var histidine:       Nutrient?
    public var isoleucine:      Nutrient?
    public var leucine:         Nutrient?
    public var lysine:          Nutrient?
    public var methionine:      Nutrient?
    public var phenylalanine:   Nutrient?
    public var proline:         Nutrient?
    public var threonine:       Nutrient?
    public var tryptophan:      Nutrient?
    public var tyrosine:        Nutrient?
    public var valine:          Nutrient?
    public var serine:          Nutrient?
    public var hydroxyproline:  Nutrient?

    @Relationship(inverse: \FoodItem.aminoAcids) public var foodItem: FoodItem?

    public init(
        alanine: Nutrient? = nil,
        arginine: Nutrient? = nil,
        asparticAcid: Nutrient? = nil,
        cystine: Nutrient? = nil,
        glutamicAcid: Nutrient? = nil,
        glycine: Nutrient? = nil,
        histidine: Nutrient? = nil,
        isoleucine: Nutrient? = nil,
        leucine: Nutrient? = nil,
        lysine: Nutrient? = nil,
        methionine: Nutrient? = nil,
        phenylalanine: Nutrient? = nil,
        proline: Nutrient? = nil,
        threonine: Nutrient? = nil,
        tryptophan: Nutrient? = nil,
        tyrosine: Nutrient? = nil,
        valine: Nutrient? = nil,
        serine: Nutrient? = nil,
        hydroxyproline: Nutrient? = nil
    ) {
        self.alanine = alanine
        self.arginine = arginine
        self.asparticAcid = asparticAcid
        self.cystine = cystine
        self.glutamicAcid = glutamicAcid
        self.glycine = glycine
        self.histidine = histidine
        self.isoleucine = isoleucine
        self.leucine = leucine
        self.lysine = lysine
        self.methionine = methionine
        self.phenylalanine = phenylalanine
        self.proline = proline
        self.threonine = threonine
        self.tryptophan = tryptophan
        self.tyrosine = tyrosine
        self.valine = valine
        self.serine = serine
        self.hydroxyproline = hydroxyproline
    }

    // По избор: KeyPath map (удобно за предикати/дисплей логика)
    public static func keyPath(for id: String) -> KeyPath<AminoAcidsData, Nutrient?> {
        switch id {
        case "alanine": return \.alanine
        case "arginine": return \.arginine
        case "asparticAcid": return \.asparticAcid
        case "cystine": return \.cystine
        case "glutamicAcid": return \.glutamicAcid
        case "glycine": return \.glycine
        case "histidine": return \.histidine
        case "isoleucine": return \.isoleucine
        case "leucine": return \.leucine
        case "lysine": return \.lysine
        case "methionine": return \.methionine
        case "phenylalanine": return \.phenylalanine
        case "proline": return \.proline
        case "threonine": return \.threonine
        case "tryptophan": return \.tryptophan
        case "tyrosine": return \.tyrosine
        case "valine": return \.valine
        case "serine": return \.serine
        case "hydroxyproline": return \.hydroxyproline
        default: return \.alanine
        }
    }
}
