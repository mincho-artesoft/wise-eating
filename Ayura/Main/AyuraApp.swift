// ==== FILE: AyuraApp.swift ====
import SwiftUI
import SwiftData
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@main
struct AyuraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    @AppStorage("isFirstAppLaunch") private var isFirstAppLaunch: Bool = true
    @State private var coldStart: Bool = true
    
    let container: ModelContainer = DatabaseSetup.createContainer()
    private var notificationDelegate = NotificationDelegate()
    
    init() {
            // --- Common Logic ---
            GlobalState.modelContext = container.mainContext
            
            Task { @MainActor in GlobalState.updateAIAvailability() }
            UNUserNotificationCenter.current().delegate = notificationDelegate
            AIManager.shared.setup(container: container)
            Task { @MainActor in await CalendarViewModel.shared.ensureSharedShoppingListCalendarExists() }
            
            // --- AD LOADING LOGIC ---
            if AdsConfiguration.shouldShowAds {
                
                #if !targetEnvironment(macCatalyst)
                // Инициализация на SDK
                MobileAds.shared.start(completionHandler: nil)
               
                
                // App Open Ad е OK да се зареди, защото се показва веднага при отваряне
                Task { @MainActor in await AppOpenAdManager.shared.loadAd() }
                
                // Тези за цял екран (Rewarded/Interstitial) също са OK да се заредят по 1 брой
                Task.detached(priority: .background) {
                    try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                    await MainActor.run {
                        // Правим повторна проверка преди зареждането
                        if AdsConfiguration.shouldShowAds {
                            print("🚀 [AdOptimization] Loading fullscreen ads...")
                            Task { await RewardedAdManager.shared.loadAd() }
                            Task { await InterstitialAdManager.shared.loadAd() }
                        }
                    }
                }
                #endif
            } else {
                print("🚫 [Ads] Advertising is disabled. Skipping SDK initialization.")
            }
        }
    
    var body: some Scene {
        WindowGroup {
            RootLauncher(container: container)
                .onChange(of: scenePhase) { _, newPhase in
                    // ... (старата логика за scenePhase остава същата) ...
                    switch newPhase {
                    case .active:
                        ReviewManager.appLaunched()
                        let shouldShowAds = AdsConfiguration.shouldShowAds
                        
                        if isFirstAppLaunch {
                            isFirstAppLaunch = false
                        } else if shouldShowAds {
                            let context = container.mainContext
                            let settings = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first
                            let hasProfile = settings?.lastSelectedProfile != nil
                            
                            if hasProfile {
                                if coldStart {
                                    coldStart = false
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                                        #if !targetEnvironment(macCatalyst)
                                        AppOpenAdManager.shared.showAdIfAvailable(forceShow: true)
                                        #endif
                                    }
                                } else {
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                                        #if !targetEnvironment(macCatalyst)
                                        AppOpenAdManager.shared.showAdIfAvailable(forceShow: false)
                                        #endif
                                    }
                                }
                            } else { coldStart = false }
                        }
                        
                        Task { @MainActor in await subscriptionManager.updatePurchasedStatus() }
                        Task { @MainActor in GlobalState.updateAIAvailability() }
                        Task { @MainActor in await AIManager.shared.fetchJobs() }
                        GlobalState.refreshSystemSettings()
                        
                    case .background:
                        if AdsConfiguration.shouldShowAds {
                            #if !targetEnvironment(macCatalyst)
                            Task { @MainActor in await AppOpenAdManager.shared.loadAd() }
                            #endif
                        }
                    default: break
                    }
                }
        }
        .modelContainer(container)
    }
}
