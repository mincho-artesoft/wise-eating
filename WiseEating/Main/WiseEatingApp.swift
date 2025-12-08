import SwiftUI
import SwiftData

// Можем да изнесем и ODR в отделен файл, но ако е малък, може и тук.
// За пълна чистота, ето го отделно (може да го сложите в ODRHelpers.swift):
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

    // Инициализираме контейнера чрез изнесената логика
    let container: ModelContainer = DatabaseSetup.createContainer()
    
    private var notificationDelegate = NotificationDelegate()

    init() {
        GlobalState.modelContext = container.mainContext

        // ⬇️ Първоначална проверка (ако iOS < 26 -> автоматично става unavailable)
        Task { @MainActor in
            GlobalState.updateAIAvailability()
        }

        UNUserNotificationCenter.current().delegate = notificationDelegate
        AIManager.shared.setup(container: container)
        Task { @MainActor in
            await CalendarViewModel.shared.ensureSharedShoppingListCalendarExists()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootLauncher(container: container)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        // ⭐ ТУК: регистрираме стартиране за ReviewManager
                        ReviewManager.appLaunched()
                        
                        print("🚀 [App Launch] Current Subscription Status: \(subscriptionManager.subscriptionStatus.rawValue.uppercased())")
                        
                        // Опресняваме статуса от Apple сървърите
                        Task { @MainActor in
                            await subscriptionManager.updatePurchasedStatus()
                        }
                        
                        Task { @MainActor in
                            print("🔄 ScenePhase .active — updating AI availability…")
                            GlobalState.updateAIAvailability()
                            print("🧠 Current AI availability: \(GlobalState.aiAvailability.rawValue)")
                        }

                        Task { @MainActor in
                            await AIManager.shared.fetchJobs()
                        }
                        
                        let locale = Locale.current
                        let calendar = Calendar.current
                        
                        if let regionCode = locale.region?.identifier {
                            GlobalState.region = regionCode
                        }
                        
                        GlobalState.calendar = String(describing: calendar.identifier)
                        
                        let temp = Measurement(value: 9, unit: UnitTemperature.celsius)
                        let formattedTemp = temp.formatted(.measurement(width: .abbreviated, usage: .person, numberFormatStyle: .number))
                        let unit = formattedTemp.contains("F") ? UnitTemperature.fahrenheit : UnitTemperature.celsius
                        GlobalState.temperatureUnit = unit.symbol
                        
                        GlobalState.measurementSystem = (locale.measurementSystem == .metric) ? "Metric" : "Imperial"
                        
                        GlobalState.firstWeekday = calendar.firstWeekday
                        
                        let df = DateFormatter()
                        df.locale = locale
                        df.dateStyle = .short
                        GlobalState.dateFormat = df.dateFormat ?? ""
                        
                        let nf = NumberFormatter()
                        nf.locale = locale
                        nf.numberStyle = .decimal
                        let num = 1234567.89 as NSNumber
                        GlobalState.numberFormat = nf.string(from: num) ?? ""
                        
                        if let currencyCode = locale.currency?.identifier {
                            GlobalState.currencyCode = currencyCode
                        }

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
