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
        
        // --- Common Logic ---
        GlobalState.modelContext = container.mainContext
        
        Task { @MainActor in GlobalState.updateAIAvailability() }
        UNUserNotificationCenter.current().delegate = notificationDelegate
        AIManager.shared.setup(container: container)
        Task { @MainActor in await CalendarViewModel.shared.ensureSharedShoppingListCalendarExists() }
        
        // Ad Loading (Safe on both platforms due to managers handling stubs)
        Task { @MainActor in await AppOpenAdManager.shared.loadAd() }
        
        Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            await MainActor.run {
                print("🚀 [AdOptimization] Starting delayed ad loading...")
                Task { await RewardedAdManager.shared.loadAd() }
                Task { await InterstitialAdManager.shared.loadAd() }
                // Task { await RewardedInterstitialAdManager.shared.loadAd() } // Ако ползваш и този
                
                BannerAdPool.shared.warmUp()
                
                // Native Ads нямаме на Mac с AdSense, така че само iOS
                #if !targetEnvironment(macCatalyst)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NativeAdPool.shared.refreshPool()
                }
                #endif
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            RootLauncher(container: container)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        ReviewManager.appLaunched()
                        
                        if isFirstAppLaunch {
                            isFirstAppLaunch = false
                        } else {
                            // Логика за показване на App Open Ad
                            let context = container.mainContext
                            let settings = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first
                            let hasProfile = settings?.lastSelectedProfile != nil
                            
                            if hasProfile {
                                if coldStart {
                                    coldStart = false
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 2 * 1_000_000_000) // По-малко чакане
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
                        Task { @MainActor in await AppOpenAdManager.shared.loadAd() }
                        
                    default: break
                    }
                }
        }
        .modelContainer(container)
    }
}
