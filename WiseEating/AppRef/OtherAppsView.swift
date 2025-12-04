// MARK: - OtherAppsView.swift (Коригирана версия със скролиране)

import SwiftUI

struct OtherAppsView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // --- ИНФОРМАЦИЯ ЗА ВАШЕТО ПРИЛОЖЕНИЕ ---
    fileprivate let cloudCalendarsApp = AppInfo(
        name: "Cloud Calendars",
        description: "Plan with precision. Stay ahead of the weather. Cloud Calendars combines advanced scheduling features with beautifully integrated weather forecasts, helping you plan your days more effectively.",
        iconName: "CloudCalendarsIcon",
        appStoreURL: "https://apps.apple.com/us/app/cloud-calendars/id6744690319"
    )

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack {
                Link(destination: URL(string: cloudCalendarsApp.appStoreURL)!) {
                    promoCardView(app: cloudCalendarsApp)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                
                Color.clear
                    .frame(height: 150)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .frame(minHeight: UIScreen.main.bounds.height - 200)
        }
        .mask(
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: effectManager.currentGlobalAccentColor, location: 0.01),
                    .init(color: effectManager.currentGlobalAccentColor, location: 0.9),
                    .init(color: .clear, location: 0.95)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        // --- КРАЙ НА ПРОМЯНАТА (2/2) ---
    }

    // View за промо картата на приложението (без промени)
    private func promoCardView(app: AppInfo) -> some View {
        VStack(spacing: 16) {
            Image(app.iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(radius: 5, y: 4)

            Text(app.name)
                .font(.title2.bold())
                .foregroundColor(effectManager.currentGlobalAccentColor)

            Text(app.description)
                .font(.subheadline)
                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("View on the App Store")
                .font(.headline)
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .clipShape(Capsule())
                .glassCardStyle(cornerRadius: 30)
               
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .glassCardStyle(cornerRadius: 30)
    }
}

fileprivate struct AppInfo {
    let name: String
    let description: String
    let iconName: String
    let appStoreURL: String
}
