import Foundation
import StoreKit
import SwiftUI
import UIKit

/// ReviewManager за Ayura
///
/// Условия:
/// - Поне 5 стартирания на приложението
/// - Поне 1 ден от инсталацията
/// - Поне 120 дни от последното показване на prompt-а
///
/// Използване:
///   - В `scenePhase == .active`:
///       `ReviewManager.appLaunched()`
@MainActor
enum ReviewManager {
    // MARK: - Tunables
    private static let requiredLaunches         = 5
    private static let requiredDaysAfterInstall = 1
    private static let cooldownDays             = 120

    // MARK: - Keys
    private static let installDateKey  = "rm_installDate"
    private static let launchCountKey  = "rm_launchCount"
    private static let lastPromptKey   = "rm_lastPromptDate"

    // MARK: - Public API

    /// Викай при всяко "влизане" в app-а (scenePhase == .active).
    static func appLaunched() {
        let ud = UserDefaults.standard
        print("📥 [ReviewManager] appLaunched() called")

        // Ако няма записана дата на инсталация – записваме сега
        if ud.object(forKey: installDateKey) == nil {
            let now = Date()
            ud.set(now, forKey: installDateKey)
            print("📌 [ReviewManager] First install date set: \(now)")
        }

        // Броим стартиранията
        let launches = ud.integer(forKey: launchCountKey) + 1
        ud.set(launches, forKey: launchCountKey)
        print("📊 [ReviewManager] Launch count updated: \(launches)")

        evaluateIfNeeded()
    }

    // MARK: - Internal logic

    private static func evaluateIfNeeded() {
        print("⚙️ [ReviewManager] evaluateIfNeeded()")

        guard shouldPrompt else {
            print("⚙️ [ReviewManager] shouldPrompt == false → няма да показваме popup.")
            return
        }

        print("✅ [ReviewManager] shouldPrompt == true → опит за requestReview()")

        // Взимаме активната foreground сцена
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
                print("⚠️ [ReviewManager] Няма foregroundActive UIWindowScene → прекратяваме.")
                return
        }

        Task {
            print("⭐ [ReviewManager] Calling requestReview(in:)…")
            if #available(iOS 18.0, *) {
                AppStore.requestReview(in: scene)
            } else {
                SKStoreReviewController.requestReview(in: scene)
            }

            let now = Date()
            let ud = UserDefaults.standard
            ud.set(now, forKey: lastPromptKey)
            ud.set(0, forKey: launchCountKey) // нулираме брояча

            print("📅 [ReviewManager] lastPromptDate set to \(now)")
            print("🔁 [ReviewManager] launchCount reset to 0")
        }
    }

    private static var shouldPrompt: Bool {
        let ud = UserDefaults.standard

        print("🔍 [ReviewManager] Evaluating shouldPrompt…")

        let launches = ud.integer(forKey: launchCountKey)
        print("   • launches = \(launches) (needs ≥ \(requiredLaunches))")

        // Трябва да имаме дата на инсталация
        guard let install = ud.object(forKey: installDateKey) as? Date else {
            print("   ⛔ installDate not set → returning false")
            return false
        }

        let daysSinceInstall = Date().timeIntervalSince(install) / 86_400
        print("   • daysSinceInstall ≈ \(String(format: "%.2f", daysSinceInstall)) (needs ≥ \(requiredDaysAfterInstall))")

        // Проверка: минал ли е минималният брой дни от инсталация
        guard daysSinceInstall >= Double(requiredDaysAfterInstall) else {
            print("   ⛔ Not enough days since install → returning false")
            return false
        }

        // Проверка: достатъчно стартирания
        guard launches >= requiredLaunches else {
            print("   ⛔ Not enough launches → returning false")
            return false
        }

        // Проверка за cooldown от последния prompt
        if let last = ud.object(forKey: lastPromptKey) as? Date {
            let daysSinceLastPrompt = Date().timeIntervalSince(last) / 86_400
            print("   • daysSinceLastPrompt ≈ \(String(format: "%.2f", daysSinceLastPrompt)) (needs ≥ \(cooldownDays))")

            guard daysSinceLastPrompt >= Double(cooldownDays) else {
                print("   ⛔ Cooldown not elapsed → returning false")
                return false
            }
        } else {
            print("   • No lastPromptDate → first time allowed")
        }

        print("   ✅ All conditions satisfied → shouldPrompt = true")
        return true
    }
}
