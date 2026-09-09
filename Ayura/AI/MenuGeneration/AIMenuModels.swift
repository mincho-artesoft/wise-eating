// ==== FILE: AIMenuGenerator.swift ====
import Foundation
import SwiftData
import FoundationModels

// MARK: - AI Schemas (разделени по етапи)

@available(iOS 26.0, *)
@Generable
struct AIMenuNameOnly: Codable, Sendable {
    /// Кратко име (1–2 думи) от ограничен набор (Breakfast, Brunch, Lunch, Snack, Dinner).
    @Guide(description: "Menu name (1–2 words) chosen ONLY from: Breakfast, Brunch, Lunch, Snack, Dinner.")
    var menuName: String
}

@available(iOS 26.0, *)
@Generable
struct AIMenuDetailsOnly: Codable, Sendable {
    /// Описание във формат: Summary ред + празен ред + номерирани стъпки.
    @Guide(description: "Summary line + numbered steps.")
    var description: String

    /// Общо активно време за приготвяне в минути (10–360).
    @Guide(description: "Total active minutes (10–360).")
    var prepTimeMinutes: Int
}

// --- START OF CHANGE (Decorated Name) ---
@available(iOS 26.0, *)
@Generable
struct AIMenuDecoratedNameOnly: Codable, Sendable {
    /// Кратко, “украшено” име, което ВКЛЮЧВА каноничния слот (Breakfast/…)
    /// и добавя 1–2 думи за стил/съставка/кухня. Без емоджита/брендове.
    @Guide(description: "Decorated display name (3–6 words). Must include the canonical slot (Breakfast/Brunch/Lunch/Snack/Dinner). No emojis or brands.")
    var displayName: String
}
// --- END OF CHANGE (Decorated Name) ---
