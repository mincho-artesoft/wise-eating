import SwiftUI
import SwiftData

struct RootLauncher: View {
    let container: ModelContainer
    @State private var isReady = false

    @ObservedObject private var effectManager = EffectManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared

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
                ZStack {
                    ThemeBackgroundView()
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                            .scaleEffect(1.5)

                        Text("Preparing database…")
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    .padding(30)
                    .glassCardStyle(cornerRadius: 20)
                }
                .transition(.opacity.animation(.easeInOut))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .task(priority: .userInitiated) {
            AyurvedaAsanaYogaLaunchProbe.event("root-task-begin")
            // 1. Намиране на цветове (Theme)
            let viewToRender = ThemeBackgroundView()
            let snapshot = viewToRender.renderAsImage(size: UIScreen.main.bounds.size)
            effectManager.snapshot = snapshot
            if let aSnapshot = snapshot {
                let accentColor = await aSnapshot.findGlobalAccentColor()
                effectManager.currentGlobalAccentColor = accentColor
                effectManager.isLightRowTextColor = accentColor.isLight()
            } else {
                let prefersLightForeground = themeManager.currentTheme
                    .prefersLightForeground
                effectManager.currentGlobalAccentColor = themeManager
                    .currentTheme
                    .preferredForegroundColor
                effectManager.isLightRowTextColor = prefersLightForeground
            }
            print("🎨 RootLauncher: Initial snapshot taken and accent color set.")
            AyurvedaAsanaYogaLaunchProbe.event("theme-snapshot-end")

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
                        
            let modelContext = container.mainContext
            AyurvedaAsanaYogaLaunchProbe.event("calendar-load-begin")
            let calendarAccessGranted = await CalendarViewModel.shared.requestCalendarAccessIfNeeded()
            
            if calendarAccessGranted {
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

            // 4. Готово - показваме UI
            if !isReady {
                withAnimation {
                    isReady = true
                }
                AyurvedaAsanaYogaLaunchProbe.event("root-ready-set")
            }
        }
    }
}
