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

    private static var isLoadingPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-databaseLoadingPreview")
        #else
        false
        #endif
    }

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var effectManager = EffectManager.shared
    
    @AppStorage("isFirstAppLaunch") private var isFirstAppLaunch: Bool = true
    
    @StateObject private var bootstrap = DatabaseBootstrapController()
    private var database: DatabaseLaunchState { bootstrap.database }
    private var notificationDelegate = NotificationDelegate()
    
    init() { AyurvedaAsanaYogaLaunchProbe.event("app-init") }

    var body: some Scene {
        WindowGroup {
            Group {
            if Self.isLoadingPreview || bootstrap.isPreparing {
                DatabaseLoadingView()
                .onAppear { AyurvedaAsanaYogaLaunchProbe.event("bootstrap-view-visible") }
            } else if let container = database.container {
                RootLauncher(container: container)
                    .modelContainer(container)
                    .preferredColorScheme(effectManager.appColorScheme)
                    .toggleStyle(ThemedSwitchToggleStyle())
                    .task {
                        guard !Self.isIsolatedSmokeTest else { return }
                        // StoreKit refreshes independently. Its cached plan already
                        // suppresses ads for subscribers, and changes reset ads below.
                        // With the short onboarding the consent form waits for a profile.
                        guard FeatureFlags.adsMayPrepare else { return }
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
                            guard FeatureFlags.adsMayPrepare else { return }
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
            .task {
                guard !Self.isLoadingPreview else { return }
                await bootstrap.start(isolated: Self.isIsolatedSmokeTest)
            }
            .onAppear { UNUserNotificationCenter.current().delegate = notificationDelegate }
        }
    }
}

@MainActor
final class DatabaseBootstrapController: ObservableObject {
    enum Phase {
        case preparing(status: String)
        case ready(ModelContainer, isRecoveryMode: Bool)
        case failed(diagnostic: String)
    }
    @Published private(set) var phase: Phase = .preparing(status: String(localized: "Preparing offline Ayurveda & Yoga library..."))
    var isPreparing: Bool { if case .preparing = phase { return true }; return false }
    var database: DatabaseLaunchState {
        switch phase {
        case .preparing(let status): return .unavailable(status)
        case .ready(let container, let recovery): return .ready(container, isRecoveryMode: recovery)
        case .failed(let diagnostic): return .unavailable(diagnostic)
        }
    }
    private var started = false

    func start(isolated: Bool) async {
        guard !started else { return }
        started = true
        // Profile only: a main-actor heartbeat exposes blocking intervals during
        // first-install preparation without changing normal launch behaviour.
        let responsivenessProbe = Task { @MainActor in
            guard ProcessInfo.processInfo.arguments.contains("-ayurvedaasanayogaLaunchProfile") else { return }
            while !Task.isCancelled {
                AyurvedaAsanaYogaLaunchProbe.event("bootstrap-main-responsive")
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
        defer { responsivenessProbe.cancel() }
        await Task.yield()
        let result = await DatabaseSetup.createContainer()
        if let container = result.container {
            GlobalState.modelContext = container.mainContext
            do { try CatalogPreferenceStore.shared.load(context: container.mainContext) }
            catch { print("Could not load catalogue preferences: \(error)") }
            GlobalState.updateAIAvailability()
            if isolated {
                print("SMOKE_TEST|APP|isolated-launch-mode")
            } else {
                AIManager.shared.setup(container: container)
            }
        }
        if let container = result.container {
            phase = .ready(container, isRecoveryMode: result.isRecoveryMode)
        } else {
            phase = .failed(diagnostic: result.diagnostic ?? "Database unavailable")
        }
        AyurvedaAsanaYogaLaunchProbe.event("bootstrap-ready")
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
                    "Your existing data has not been deleted. Please close and reopen the app."
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
