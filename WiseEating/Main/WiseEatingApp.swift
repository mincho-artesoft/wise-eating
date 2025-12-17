import SwiftUI
import SwiftData
import GoogleMobileAds

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
        // 1. Дефиниране на тестовите устройства
        let testDevices = [
            "7F2105B5-5CC4-436C-88C1-28BA71BD949C", // Wife iPad
            "9DD38651-791A-4B28-84CD-DB22E51DBAF4",  // Wife iPhone
            "83168461-56E7-4160-B4D2-8CA539FEBB1B",
            "560CA1A2-1EC6-4BDA-8F0A-0B41839EE3EB",
            "69FE353C-01C9-4BA5-8861-67355A140C56",
            "027E2BBC-9DD1-4BBA-9C6C-79E8F1BE7351"
        ]
        
        // 2. Конфигурация (MobileAds.shared)
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = testDevices
        
        // 3. Стартиране
        MobileAds.shared.start(completionHandler: nil)
        
        
        // --- Останалата логика (без промяна) ---
        GlobalState.modelContext = container.mainContext
        
        Task { @MainActor in
            GlobalState.updateAIAvailability()
        }
        
        UNUserNotificationCenter.current().delegate = notificationDelegate
        AIManager.shared.setup(container: container)
        Task { @MainActor in
            await CalendarViewModel.shared.ensureSharedShoppingListCalendarExists()
        }
        
        // 1. Зареждаме САМО App Open Ad веднага
        Task { @MainActor in
            await AppOpenAdManager.shared.loadAd()
        }
        
        // 2. Всички останали реклами зареждаме със закъснение
        Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            
            await MainActor.run {
                print("🚀 [AdOptimization] Starting delayed heavy ad loading...")
                
                Task { await RewardedAdManager.shared.loadAd() }
                Task { await InterstitialAdManager.shared.loadAd() }
                Task { await RewardedInterstitialAdManager.shared.loadAd() }
                
                BannerAdPool.shared.warmUp()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NativeAdPool.shared.refreshPool()
                }
            }
        }
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
                                print("🔄 Връщане в приложението (Profile Found).")
                                
                                if coldStart {
                                    // СТУДЕН СТАРТ:
                                    // Изчакваме 3 секунди и форсираме показването (forceShow: true)
                                    // защото user-ът иска винаги при старт да има реклама.
                                    coldStart = false
                                    
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                                        AppOpenAdManager.shared.showAdIfAvailable(forceShow: true)
                                    }
                                } else {
                                    // ТОПЪЛ СТАРТ (връщане от background):
                                    // Тук НЕ форсираме, оставяме логиката "на всеки 10-ти" да работи.
                                    Task { @MainActor in
                                        AppOpenAdManager.shared.showAdIfAvailable(forceShow: false)
                                    }
                                }
                            } else {
                                print("🔕 Връщане в приложението: НЯМА селектиран профил. Рекламата се пропуска.")
                                // Все пак маркираме coldStart като преминал
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
