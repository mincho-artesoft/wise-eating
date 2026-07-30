//  UnitHelpers.swift   (нов файл или разширение)

import Foundation

/// mg ⇄ g ⇄ µg (за IU просто връщаме 1 : 1 — няма данни за конверсия)
@inline(__always)
func toMg(value: Double, unit: String) -> Double {
    switch unit.lowercased() {
    case "g":            return value * 1_000
    case "µg", "mcg":    return value * 0.001
    default:             return value            // mg, IU, kcal …
    }
}

@inline(__always)
func fromMg(_ mg: Double, to unit: String) -> Double {
    switch unit.lowercased() {
    case "g":            return mg / 1_000
    case "µg", "mcg":    return mg * 1_000
    default:             return mg
    }
}

protocol DeepCopying {
    associatedtype CopyType
    @MainActor func copy() -> CopyType
}
