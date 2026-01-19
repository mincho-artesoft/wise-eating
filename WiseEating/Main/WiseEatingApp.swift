import SwiftUI
import SwiftData
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@main
struct WiseEatingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    @AppStorage("isFirstAppLaunch") private var isFirstAppLaunch: Bool = true
    @State private var coldStart: Bool = true
    
    let container: ModelContainer = DatabaseSetup.createContainer()
    private var notificationDelegate = NotificationDelegate()
    
    init() {
        // --- Common Logic (Винаги се изпълнява) ---
        GlobalState.modelContext = container.mainContext
        
        Task { @MainActor in GlobalState.updateAIAvailability() }
        UNUserNotificationCenter.current().delegate = notificationDelegate
        AIManager.shared.setup(container: container)
        Task { @MainActor in await CalendarViewModel.shared.ensureSharedShoppingListCalendarExists() }
        
        // --- AD LOADING LOGIC ---
        // Проверяваме директно Singleton-а, защото @ObservedObject още не е инициализиран напълно в init()
        // Ако е в промоция, status автоматично е .removeAds, така че кодът в if-а няма да се изпълни.
        if SubscriptionManager.shared.subscriptionStatus == .base {
            
            // Инициализация на AdMob САМО за iOS
            #if !targetEnvironment(macCatalyst)
            let testDevices = [
                "7F2105B5-5CC4-436C-88C1-28BA71BD949C",
                "9DD38651-791A-4B28-84CD-DB22E51DBAF4"
            ]
            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = testDevices
            MobileAds.shared.start(completionHandler: nil)
            #else
            print("🖥️ Running on Mac Catalyst. AdMob disabled, using AdSense fallback.")
            #endif
            
            // Зареждане на App Open Ad (Първоначално)
            Task { @MainActor in await AppOpenAdManager.shared.loadAd() }
            
            // Зареждане на останалите реклами във фонов режим
            Task.detached(priority: .background) {
                try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                await MainActor.run {
                    // Правим повторна проверка, в случай че статусът се е сменил през тези 3 секунди
                    if SubscriptionManager.shared.subscriptionStatus == .base {
                        print("🚀 [AdOptimization] Starting delayed ad loading...")
                        Task { await RewardedAdManager.shared.loadAd() }
                        Task { await InterstitialAdManager.shared.loadAd() }
                        // Task { await RewardedInterstitialAdManager.shared.loadAd() }
                        
                        BannerAdPool.shared.warmUp()
                        
                        #if !targetEnvironment(macCatalyst)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            NativeAdPool.shared.refreshPool()
                        }
                        #endif
                    } else {
                        print("💎 [AdOptimization] Subscription active/promo detected. Aborting background ad load.")
                    }
                }
            }
        } else {
            print("💎 [WiseEatingApp] Premium/Promo active on launch. Skipping ALL ad initialization.")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            RootLauncher(container: container)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        ReviewManager.appLaunched()
                        
                        // Проверяваме дали трябва да показваме реклами
                        let shouldShowAds = subscriptionManager.subscriptionStatus == .base
                        
                        if isFirstAppLaunch {
                            isFirstAppLaunch = false
                        } else if shouldShowAds { // Само ако е Base план
                            // Логика за показване на App Open Ad
                            let context = container.mainContext
                            let settings = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first
                            let hasProfile = settings?.lastSelectedProfile != nil
                            
                            if hasProfile {
                                if coldStart {
                                    coldStart = false
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                                        AppOpenAdManager.shared.showAdIfAvailable(forceShow: true)
                                    }
                                } else {
                                    Task { @MainActor in
                                        AppOpenAdManager.shared.showAdIfAvailable(forceShow: false)
                                    }
                                }
                            } else {
                                coldStart = false
                            }
                        }
                        
                        Task { @MainActor in await subscriptionManager.updatePurchasedStatus() }
                        Task { @MainActor in GlobalState.updateAIAvailability() }
                        Task { @MainActor in await AIManager.shared.fetchJobs() }
                        GlobalState.refreshSystemSettings()
                        
                    case .background:
                        // Зареждаме реклама за следващия път САМО ако няма абонамент/промо
                        if subscriptionManager.subscriptionStatus == .base {
                            Task { @MainActor in await AppOpenAdManager.shared.loadAd() }
                        }
                        
                    default: break
                    }
                }
        }
        .modelContainer(container)
    }
}
