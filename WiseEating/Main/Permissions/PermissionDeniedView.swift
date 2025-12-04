import SwiftUI

struct PermissionDeniedView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    /// Типът на разрешението, което трябва да се поиска.
    let type: PermissionType
    
    /// Показва ли се фоновата тема (ThemeBackgroundView).
    var hasBackground: Bool = true

    /// Callback, който се извиква, когато потребителят се върне от настройките,
    /// за да може основният изглед да провери отново статуса.
    let onTryAgain: () -> Void

    // Къстъм инициализатор с стойност по подразбиране, за да не се счупят старите извиквания
    init(type: PermissionType, hasBackground: Bool = true, onTryAgain: @escaping () -> Void) {
        self.type = type
        self.hasBackground = hasBackground
        self.onTryAgain = onTryAgain
    }

    var body: some View {
        ZStack {
            if hasBackground {
                ThemeBackgroundView()
                    .ignoresSafeArea()
            }

            VStack(spacing: 20) {
                Spacer()
                
                VStack(spacing: 25) {
                    Image(systemName: type.systemImageName)
                        .font(.system(size: 80, weight: .light))
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    
                    Text(type.title)
                        .font(.title2.bold())
                        .foregroundColor(effectManager.currentGlobalAccentColor)

                    Text(type.description)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.9))
                        .padding(.horizontal)
                    
                    if type != .network{
                        Button(action: { PermissionManager.shared.openAppSettings(for: type) }) {
                            Text(type == .allTrainingFeatures ? "Open Health App" : "Open Settings")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .foregroundColor(effectManager.currentGlobalAccentColor)
                        }
                        .glassCardStyle(cornerRadius: 20)
                    }
                }
                .padding(30)
                .glassCardStyle(cornerRadius: 30)
                
                Spacer()
                Spacer()
            }
            .padding()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            onTryAgain()
        }
    }
}
