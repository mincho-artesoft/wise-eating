import EventKit
import SwiftUI
import SwiftData

struct RootLauncher: View {
    let container: ModelContainer
    @State private var isReady = false

    @ObservedObject private var effectManager = EffectManager.shared

    @Query private var allVitamins: [Vitamin]
    @Query private var allMinerals: [Mineral]
    
    var body: some View {
        ZStack {
            if isReady {
                RootView()
                    .modelContainer(container)
                    .transition(.opacity.animation(.easeInOut))
                    .onAppear {
                        AyurvedaAsanaYogaLaunchProbe.event("root-view-appeared")
                        DispatchQueue.main.async {
                            AyurvedaAsanaYogaLaunchProbe.event("first-interactive-frame")
                        }
                    }
            } else {
                DatabaseLoadingView()
                    .transition(.opacity.animation(.easeInOut))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .task(priority: .userInitiated) {
            guard !isReady else { return }
            AyurvedaAsanaYogaLaunchProbe.event("root-task-begin")
            // 1. Намиране на цветове (Theme)
            let viewToRender = ThemeBackgroundView()
            let snapshot = viewToRender.renderAsImage(size: UIScreen.main.bounds.size)
            effectManager.snapshot = snapshot
            effectManager.updateThemeForeground()
            print("🎨 RootLauncher: Initial snapshot taken and accent color set.")
            AyurvedaAsanaYogaLaunchProbe.event("theme-snapshot-end")

            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(
                "-catalogSeparationSmokeTest"
            ) {
                await CatalogSeparationSmokeTestRunner.run(
                    realContext: container.mainContext
                )
                return
            }
            #endif

            // 2. Seeding (Попълване на базата и създаване на Cache Blob)
            await SeedManager.seedIfNeeded(container: container)

            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-aiGenerationSmokeTest") {
                if #available(iOS 26.0, *) {
                    await AIGenerationSmokeTestRunner.run(container: container)
                } else {
                    print("AI_SMOKE|ERROR|iOS 26 or newer is required")
                }
                return
            }
            #endif
            
            // FoodSearch performs the same version-checked load when its view opens.
            // Keeping the 28 MB cache decode off the launch path makes first render
            // independent of a feature the user may not open in this session.
            AyurvedaAsanaYogaLaunchProbe.event("search-index-load-deferred")

            // Only local database preparation gates the UI. EventKit permission
            // requests may wait for user interaction (or another system sheet)
            // indefinitely, so they must never own the launch spinner.
            withAnimation {
                isReady = true
            }
            AyurvedaAsanaYogaLaunchProbe.event("root-ready-set")
            await Task.yield()
            guard !Task.isCancelled else { return }

            let modelContext = container.mainContext
            AyurvedaAsanaYogaLaunchProbe.event("calendar-load-begin")
            // Retain automatic profile recovery on a reinstall: ask once, after
            // the UI is visible, then restore as soon as access is granted.
            // With the short onboarding the calendar is not asked for at launch:
            // it is used here only if access was given before, and asked for on
            // the welcome screen ("I have used the app before") or when the
            // profile is saved.
            let calendarNotAskedYet = EKEventStore.authorizationStatus(for: .event) == .notDetermined
            let calendarAccessGranted = (FeatureFlags.newOnboarding && calendarNotAskedYet)
                ? false
                : await CalendarViewModel.shared.requestCalendarAccessIfNeeded()
            
            if calendarAccessGranted {
                await CalendarViewModel.shared.ensureSharedShoppingListCalendarExists()
                let existingProfiles = try? modelContext.fetch(FetchDescriptor<Profile>())
                let existingProfileIDs = Set(existingProfiles?.map { $0.id.uuidString } ?? [])

                await CalendarViewModel.shared.reconstructProfilesFromCalendars(
                    existingProfileIDs: existingProfileIDs,
                    allVitamins: allVitamins,
                    allMinerals: allMinerals,
                    context: modelContext
                )

            } else {
                print("Calendar access not granted. Skipping profile reconstruction from calendars.")
            }
            AyurvedaAsanaYogaLaunchProbe.event("calendar-load-end")
        }
    }
}
