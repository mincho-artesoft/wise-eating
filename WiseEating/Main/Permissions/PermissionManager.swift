import SwiftUI
import EventKit
import UserNotifications
import UIKit

/// Тип на разрешението, за което питаме.
enum PermissionType {
    case calendar
    case notifications
    case allTrainingFeatures
    case camera
    case network   // 🆕

    var title: String {
        switch self {
        case .calendar:
            // ✅ ОБНОВЕНО: включваме и тренировките
            return "Calendar Access Required for Meals & Workouts"
        case .notifications:
            // ✅ ОБНОВЕНО: включваме и тренировките, shopping lists и AI
            return "Notifications Required for Meals, Workouts & Shopping Lists"
        case .allTrainingFeatures:
            return "Health Access Required"
        case .camera:
            return "Camera Access Required"
        case .network:
            return "Internet Connection Required"
        }
    }

    var description: String {
        switch self {
        case .calendar:
            // ✅ ОБНОВЕНО: споменаваме и тренировки
            return """
            Wise Eating uses your calendar to save your meals, shopping lists, and workouts. \
            Please grant permission in Settings to use these features.
            """
        case .notifications:
            // ✅ ОБНОВЕНО: включваме shopping lists, AI и други
            return """
            Wise Eating uses notifications to remind you about your meals, workouts, shopping lists, \
            AI suggestions, and other important features. Please enable notifications in Settings \
            to stay on track and get the most out of Wise Eating.
            """
        case .allTrainingFeatures:
            return """
            To track your workouts, Wise Eating needs access to your Health data.

            The button below will open the Health app. From there, please navigate to:
            **Sharing > Apps > Wise Eating**
            """
        case .camera:
            return "Wise Eating needs camera access to scan barcodes and take photos for your foods and exercises. Please grant permission in Settings to use these features."
        case .network:
            return "An active internet connection is required to look up products and create new items. Turn on Wi-Fi or Cellular data."
        }
    }

    var systemImageName: String {
        switch self {
        case .calendar: return "calendar.badge.exclamationmark"
        case .notifications: return "bell.badge.fill"
        case .allTrainingFeatures: return "heart.text.square.fill"
        case .camera: return "camera.viewfinder"
        case .network: return "wifi.exclamationmark"
        }
    }

    /// Текст за бутона според типа
    var primaryButtonTitle: String {
        switch self {
        case .allTrainingFeatures: return "Open Health App"
        case .network, .camera, .calendar, .notifications: return "Open Settings"
        }
    }
}

/// Централизиран мениджър за проверки и отваряне на настройки.
@MainActor
class PermissionManager {
    static let shared = PermissionManager()
    private init() {}

    func checkCalendarStatus() -> EKAuthorizationStatus {
        return EKEventStore.authorizationStatus(for: .event)
    }

    func checkNotificationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    /// Отваря настройките/Health. (Заб.: Apple не дава официални URL схеми за Wi-Fi/Cellular; ползваме Settings.)
    func openAppSettings(for type: PermissionType) {
        let urlString: String
        switch type {
        case .calendar, .notifications, .camera, .network:
            urlString = UIApplication.openSettingsURLString
        case .allTrainingFeatures:
            urlString = "x-apple-health://"
        }

        guard let settingsUrl = URL(string: urlString),
              UIApplication.shared.canOpenURL(settingsUrl) else {
            print("Could not open URL: \(urlString)")
            return
        }
        UIApplication.shared.open(settingsUrl)
    }
}
