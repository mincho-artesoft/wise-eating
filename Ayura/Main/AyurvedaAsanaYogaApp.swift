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
    
    private let database = DatabaseSetup.createContainer()
    private var notificationDelegate = NotificationDelegate()
    
    init() {
            guard let container = database.container else {
                return
            }
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

            // Consent and ad SDK startup run after the root view is visible.

        }
    
    var body: some Scene {
        WindowGroup {
            if let container = database.container {
                RootLauncher(container: container)
                    .modelContainer(container)
                    .preferredColorScheme(effectManager.appColorScheme)
                    .toggleStyle(ThemedSwitchToggleStyle())
                    .task {
                        guard !Self.isIsolatedSmokeTest else { return }
                        // StoreKit refreshes independently. Its cached plan already
                        // suppresses ads for subscribers, and changes reset ads below.
                        await AdsConsentManager.shared.prepareAds()
                    }
                    .onChange(of: subscriptionManager.subscriptionStatus) { _, _ in
                        guard !Self.isIsolatedSmokeTest else { return }
                        Task { await AdsConsentManager.shared.subscriptionDidChange() }
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                    guard !Self.isIsolatedSmokeTest else { return }
                    // ... (старата логика за scenePhase остава същата) ...
                    switch newPhase {
                    case .active:
                        ReviewManager.appLaunched()
                        Task { await subscriptionManager.updatePurchasedStatus() }
                        Task { @MainActor in
                            await AdsConsentManager.shared.prepareAds()
                            if isFirstAppLaunch {
                                isFirstAppLaunch = false
                                return
                            }
                            guard AdsConfiguration.canRequestAds else { return }
                            let settings = (try? container.mainContext.fetch(
                                FetchDescriptor<UserSettings>()
                            ))?.first
                            guard settings?.lastSelectedProfile != nil else { return }
                            try? await Task.sleep(for: .seconds(2))
                            guard !Task.isCancelled,
                                  UIApplication.shared.applicationState == .active else { return }
                            AppOpenAdManager.shared.showAdIfAvailable()
                        }

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
            } else {
                DatabaseUnavailableView(
                    diagnostic: database.diagnostic ?? "Unknown database error"
                )
                .preferredColorScheme(effectManager.appColorScheme)
            }
        }
    }
}

private struct DatabaseUnavailableView: View {
    let diagnostic: String

    var body: some View {
        ZStack {
            ThemeBackgroundView()
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 42, weight: .semibold))

                Text("We couldn't prepare your data")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(
                    "Your existing data has not been deleted. "
                        + "Please close and reopen the app."
                )
                .font(.body)
                .multilineTextAlignment(.center)

                #if DEBUG
                Text(diagnostic)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                #endif
            }
            .padding(32)
            .frame(maxWidth: 520)
            .glassCardStyle(cornerRadius: 24)
            .padding()
        }
    }
}
