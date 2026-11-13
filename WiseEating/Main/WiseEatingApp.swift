// ==== FILE: WiseEatingApp.swift ====
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
            // --- Common Logic ---
            GlobalState.modelContext = container.mainContext
            
            Task { @MainActor in GlobalState.updateAIAvailability() }
            UNUserNotificationCenter.current().delegate = notificationDelegate
            AIManager.shared.setup(container: container)
            Task { @MainActor in await CalendarViewModel.shared.ensureSharedShoppingListCalendarExists() }
        }
    
    var body: some Scene {
        WindowGroup {
            RootLauncher(container: container)
                .task {
                    await AdsConsentManager.shared.prepareAds()
                }
                .onChange(of: subscriptionManager.subscriptionStatus) { _, _ in
                    Task { await AdsConsentManager.shared.subscriptionDidChange() }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // ... (старата логика за scenePhase остава същата) ...
                    switch newPhase {
                    case .active:
                        ReviewManager.appLaunched()
                        Task { await subscriptionManager.updatePurchasedStatus() }
                        Task { @MainActor in
                            await AdsConsentManager.shared.prepareAds()
                            let shouldShowAds = AdsConsentManager.shouldShowAds && AdsConsentManager.shared.canRequestAds
                            if isFirstAppLaunch {
                                isFirstAppLaunch = false
                                coldStart = false
                                return
                            }
                            guard shouldShowAds else {
                                coldStart = false
                                return
                            }
                            let context = container.mainContext
                            let settings = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first
                            let hasProfile = settings?.lastSelectedProfile != nil
                            if hasProfile {
                                if coldStart {
                                    coldStart = false
                                    try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                                    guard UIApplication.shared.applicationState == .active else { return }
                                    #if !targetEnvironment(macCatalyst)
                                    AppOpenAdManager.shared.showAdIfAvailable(forceShow: true)
                                    #endif
                                } else {
                                    try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                                    guard UIApplication.shared.applicationState == .active else { return }
                                    #if !targetEnvironment(macCatalyst)
                                    AppOpenAdManager.shared.showAdIfAvailable(forceShow: false)
                                    #endif
                                }
                            } else {
                                coldStart = false
                            }
                        }

                        Task { @MainActor in GlobalState.updateAIAvailability() }
                        Task { @MainActor in await AIManager.shared.fetchJobs() }
                        GlobalState.refreshSystemSettings()
                        
                    case .background:
                        if subscriptionManager.subscriptionStatus == .base {
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
