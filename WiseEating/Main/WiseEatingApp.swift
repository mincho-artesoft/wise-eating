// ==== FILE: /Users/aleksandarsvinarov/Desktop/as/vitahealth-clean/WiseEating/Main/WiseEatingApp.swift ====
import SwiftUI
import SwiftData

// Можем да изнесем и ODR в отделен файл, но ако е малък, може и тук.
final class ODRDevPrefetch {
    nonisolated(unsafe) private static var req: NSBundleResourceRequest?

    static func prefetch(_ tags: Set<String>) {
        let r = NSBundleResourceRequest(tags: tags)
        r.loadingPriority = NSBundleResourceRequestLoadingPriorityUrgent
        req = r // keep alive
        r.conditionallyBeginAccessingResources { available in
            if available { return }
            r.beginAccessingResources { error in
                if let error { print("ODR prefetch failed in DEBUG: \(error)") }
            }
        }
    }
}

@main
struct WiseEatingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    // ✅ НОВО: Запазваме състояние дали това е първото стартиране някога
    @AppStorage("isFirstAppLaunch") private var isFirstAppLaunch: Bool = true
    @State private var coldStart: Bool = true

    let container: ModelContainer = DatabaseSetup.createContainer()
    
    private var notificationDelegate = NotificationDelegate()

    // В WiseEatingApp.swift
    init() {
        
        GlobalState.modelContext = container.mainContext

        Task { @MainActor in
            GlobalState.updateAIAvailability()
        }

        UNUserNotificationCenter.current().delegate = notificationDelegate
        AIManager.shared.setup(container: container)
        Task { @MainActor in
            await CalendarViewModel.shared.ensureSharedShoppingListCalendarExists()
        }
        
        // --- ПРОМЯНА: Зареждаме ВСИЧКИ видове реклами и ПУЛОВЕ тук ---
        Task { @MainActor in
            // 1. Единични формати (цял екран)
            await AppOpenAdManager.shared.loadAd()      // Open Ad
            await RewardedAdManager.shared.loadAd()     // Video Reward
            await InterstitialAdManager.shared.loadAd() // Fallback Interstitial
            
            // 2. Пулове (списъци) - стартираме ги да се пълнят веднага
            BannerAdPool.shared.warmUp()       // Банери
            NativeAdPool.shared.refreshPool()  // ✅ Native Ads (за разнообразни реклами в списъците)
        }
        // ----------------------------------------------------
    }
 
    var body: some Scene {
        WindowGroup {
            RootLauncher(container: container)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        // 1. Ревюта
                        ReviewManager.appLaunched()
                        
                        // --- ПРОМЯНА: Логика за рекламите ---
                        if isFirstAppLaunch {
                            print("🚀 Първо стартиране на приложението: Рекламата е пропусната.")
                            isFirstAppLaunch = false
                        } else {
                            // ✅ ПРОВЕРКА: Има ли селектиран профил?
                            let context = container.mainContext
                            let descriptor = FetchDescriptor<UserSettings>()
                            // Взимаме първия (и единствен) UserSettings запис
                            let settings = (try? context.fetch(descriptor))?.first
                            let hasSelectedProfile = settings?.lastSelectedProfile != nil
                            
                            if hasSelectedProfile {
                                print("🔄 Връщане в приложението (Profile Found): Ще се опита показване на реклама.")

                                if coldStart {
                                    // отбелязваме веднага, че студеното стартиране вече е минало
                                    coldStart = false
                                    
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                                        AppOpenAdManager.shared.showAdIfAvailable()
                                    }
                                } else {
                                    Task { @MainActor in
                                        AppOpenAdManager.shared.showAdIfAvailable()
                                    }
                                }
                            } else {
                                print("🔕 Връщане в приложението: НЯМА селектиран профил. Рекламата се пропуска.")
                                // Все пак маркираме coldStart като преминал, за да не се забави рекламата,
                                // ако потребителят създаде профил и веднага излезе/влезе пак.
                                coldStart = false
                            }
                        }
                        // -------------------------------------
                        
                        // 2. Абонаменти
                        print("🚀 [App Launch] Current Subscription Status: \(subscriptionManager.subscriptionStatus.rawValue.uppercased())")
                        Task { @MainActor in
                            await subscriptionManager.updatePurchasedStatus()
                        }
                        
                        // 3. AI Jobs & Status
                        Task { @MainActor in
                            GlobalState.updateAIAvailability()
                        }
                        Task { @MainActor in
                            await AIManager.shared.fetchJobs()
                        }
                        
                        // 4. Системни настройки
                        GlobalState.refreshSystemSettings()

                        // 5. Usage & Badges
                        Task { @MainActor in
                            let context = container.mainContext
                            let settingsDescriptor = FetchDescriptor<UserSettings>()
                            if let settings = (try? context.fetch(settingsDescriptor))?.first,
                               let lastProfile = settings.lastSelectedProfile {
                                
                                UsageTrackingManager.shared.logUsage(for: lastProfile)
                                await BadgeManager.shared.checkAndAwardBadges(for: lastProfile, using: context)
                            }
                        }

                    case .background:
                        print("App in background. Stop sync timers.")
                        // Зареждаме нова реклама, докато сме в бекграунд, за да е готова за следващия път
                        Task { @MainActor in
                            await AppOpenAdManager.shared.loadAd()
                        }
                        
                    case .inactive:
                        print("App is inactive.")
                        
                    @unknown default:
                        break
                    }
                }
        }
        .modelContainer(container)
    }
}
