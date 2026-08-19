// ==== FILE: AyurvedaAsanaYogaApp.swift ====
import SwiftUI
import SwiftData
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@main
struct AyurvedaAsanaYogaApp: App {
    private static var isAIGenerationSmokeTest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-aiGenerationSmokeTest")
        #else
        false
        #endif
    }

    private static var isCatalogSeparationSmokeTest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-catalogSeparationSmokeTest")
        #else
        false
        #endif
    }

    private static var isIsolatedSmokeTest: Bool {
        isAIGenerationSmokeTest || isCatalogSeparationSmokeTest
    }

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var effectManager = EffectManager.shared
    
    @AppStorage("isFirstAppLaunch") private var isFirstAppLaunch: Bool = true
    @State private var coldStart: Bool = true
    
    let container: ModelContainer = DatabaseSetup.createContainer()
    private var notificationDelegate = NotificationDelegate()
    
    init() {
            // --- Common Logic ---
            GlobalState.modelContext = container.mainContext
            do {
                try CatalogPreferenceStore.shared.load(context: container.mainContext)
            } catch {
                print("⚠️ Could not load catalogue preferences: \(error)")
            }
            
            Task { @MainActor in GlobalState.updateAIAvailability() }
            UNUserNotificationCenter.current().delegate = notificationDelegate
            if Self.isIsolatedSmokeTest {
                print("SMOKE_TEST|APP|isolated-launch-mode")
                return
            }
            AIManager.shared.setup(container: container)
            Task { @MainActor in await CalendarViewModel.shared.ensureSharedShoppingListCalendarExists() }

            // --- AD LOADING LOGIC ---
            if AdsConfiguration.shouldShowAds {
                
                #if canImport(GoogleMobileAds)
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
                .preferredColorScheme(effectManager.appColorScheme)
                .onChange(of: scenePhase) { _, newPhase in
                    guard !Self.isIsolatedSmokeTest else { return }
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
                                        AppOpenAdManager.shared.showAdIfAvailable(forceShow: true)
                                    }
                                } else {
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                                        AppOpenAdManager.shared.showAdIfAvailable(forceShow: false)
                                    }
                                }
                            } else { coldStart = false }
                        }
                        
                        Task { @MainActor in await subscriptionManager.updatePurchasedStatus() }
                        Task { @MainActor in GlobalState.updateAIAvailability() }
                        Task { @MainActor in await AIManager.shared.fetchJobs() }
                        Task {
                            await NotificationManager.shared.refreshPracticeReminderIfNeeded()
                        }
                        Task { @MainActor in
                            let context = container.mainContext
                            let settings = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first
                            if let profile = settings?.lastSelectedProfile {
                                await NextEventLiveActivityManager.shared.refreshIfRunning(for: profile)
                            } else {
                                NextEventLiveActivityManager.shared.refreshStatus()
                            }
                        }
                        GlobalState.refreshSystemSettings()
                        
                    case .background:
                        if AdsConfiguration.shouldShowAds {
                            Task { @MainActor in await AppOpenAdManager.shared.loadAd() }
                        }
                    default: break
                    }
                }
        }
        .modelContainer(container)
    }
}
