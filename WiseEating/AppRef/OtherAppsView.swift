import SwiftUI

// MARK: - Дефиниция на данните за приложенията
// Тази структура дефинира каква информация е нужна за всяко приложение в списъка.
fileprivate struct AppPromoData: Identifiable, Equatable {
    let id = UUID()
    let appName: String
    let description: String
    let iconName: String           // Името на картинката в Assets
    let systemImageFallback: String // Системна икона, ако няма картинка (напр. "heart.fill")
    let appStoreURL: String
    let accentColor: Color         // Цвят на бутона за конкретното приложение
}

// MARK: - Основен изглед
struct OtherAppsView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    // --- ДАННИ ЗА ПРИЛОЖЕНИЯТА (вградени в изгледа) ---
    private let promotionalApps: [AppPromoData] = [
        AppPromoData(
            appName: "Wise Eating & Fitness Planner",
            description: "Wise Eating is your AI-powered coach for smarter nutrition and training. It combines modern nutrition science with practical tools to help you plan meals, design workouts, manage your pantry, and understand how food and movement affect your body.",
            iconName: "WiseEatingIcon",
            systemImageFallback: "carrot.fill",
            appStoreURL: "https://apps.apple.com/us/app/wise-eating-fitness-planner/id6751406823",
            accentColor: .green
        ),
        AppPromoData(
            appName: "StoreFront Studio",
            description: "StoreFront Studio is the elite 3D design environment for iOS and macOS developers. It combines high-fidelity RealityKit rendering with a powerful Rich Text editor to help you transform raw screenshots into professional, high-converting App Store assets.",
            iconName: "StoreFrontIcon",
            systemImageFallback: "heart.text.square.fill",
            appStoreURL: "https://apps.apple.com/us/app/storefront-studio/id6757389314",
            accentColor: .cyan
        ),
        AppPromoData(
            appName: "ReelStudio",
            description: "ReelStudio is the creator-grade screen recording studio for iOS and macOS. Capture your screen and camera at the same time, control mic + system audio, and export clean MP4s for tutorials, walkthroughs, and product demos. On iOS, you can even play a video inside the app and record it together with your camera for reaction-style and presenter-led content.",
            iconName: "ReelStudioIcon",
            systemImageFallback: "record.circle.fill",
            appStoreURL: "https://apps.apple.com/us/app/reelstudio/id6758941990",
            accentColor: .purple
        ),
        AppPromoData(
            appName: "Cloud Calendars",
            description: "Cloud Calendars combines advanced scheduling with beautifully integrated weather forecasts, so you can plan with precision. It supports multiple calendar services, intuitive gesture-based editing, built-in meeting links, and detailed hourly/daily forecasts directly inside your schedule.",
            iconName: "CloudCalendarsIcon",
            systemImageFallback: "calendar.badge.clock",
            appStoreURL: "https://apps.apple.com/us/app/cloud-calendars/id6744690319",
            accentColor: .blue
        ),
        AppPromoData(
            appName: "MarketBrief AI",
            description: "MarketBrief AI helps you understand market movement with on-device analytics and a multi-agent workflow designed to separate signal from noise. Track real-time price data, explore regime-style probabilities, and use clear dashboards and charts to support your decision-making. Privacy-first: your configurations stay on your device.",
            iconName: "MarketBriefIcon",
            systemImageFallback: "chart.line.uptrend.xyaxis",
            appStoreURL: "https://apps.apple.com/us/app/market-brief-ai/id6758329388",
            accentColor: .blue.opacity(0.75)
        )
    ]

    // --- ТЯЛО НА ИЗГЛЕДА ---
    var body: some View {
        // Използваме ScrollView, за да може съдържанието да се превърта, ако е по-дълго от екрана.
        ScrollView {
            VStack(spacing: 16) {
                // Заглавие на секцията
                Text("More Apps From Us")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top)
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                // Генериране на изглед за всяко приложение от масива
                ForEach(promotionalApps) { app in
                    HStack(alignment: .top, spacing: 16) {
                        // Икона на приложението
                        // Проверява дали има картинка в Assets. Ако не, показва системна икона.
                        if let _ = UIImage(named: app.iconName) {
                            Image(app.iconName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(radius: 2)
                        } else {
                            Image(systemName: app.systemImageFallback)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .foregroundColor(app.accentColor)
                                .frame(width: 64, height: 64)
                                .background(app.accentColor.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        
                        // Текст и бутон
                        VStack(alignment: .leading, spacing: 6) {
                            Text(app.appName)
                                .font(.headline)
                                .foregroundColor(effectManager.currentGlobalAccentColor)

                            Text(app.description)
                                .font(.caption)
                                .lineLimit(nil) // Позволява неограничен брой редове
                                .fixedSize(horizontal: false, vertical: true) // Осигурява правилно разпъване във височина
                                .foregroundColor(effectManager.currentGlobalAccentColor)

                            // Бутон към App Store
                            if let url = URL(string: app.appStoreURL) {
                                Link(destination: url) {
                                    Text("Get")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 20)
                                        .background(app.accentColor)
                                        .clipShape(Capsule())
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    .padding()
                    .glassCardStyle(cornerRadius: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                
                // Добавя празно пространство в края, ако е нужно
                Spacer(minLength: 150)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Our Apps") // Може да добавите заглавие, ако този изглед е в NavigationView
    }
}
