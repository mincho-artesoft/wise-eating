@preconcurrency import UserNotifications

/// Структура, която представя едно известие в списъка с история.
struct NotificationHistoryItem: Identifiable, Hashable {
    let id: String // Notification Request Identifier
    let title: String
    let body: String
    let date: Date
    let userInfo: [AnyHashable: Any]

    // --- КОРЕКЦИЯ: Ръчна имплементация на Equatable и Hashable ---
    // Сравняваме и хешираме само по уникалния идентификатор (id).
    static func == (lhs: NotificationHistoryItem, rhs: NotificationHistoryItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}



@MainActor
class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            print("Разрешението за нотификации е: \(granted)")
            return granted
        } catch {
            print("Грешка при искане на разрешение: \(error.localizedDescription)")
            return false
        }
    }
    
    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    func scheduleNotification(title: String, body: String, timeInterval: TimeInterval, userInfo: [String: Sendable], profileID: UUID?) async throws -> String {
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        var finalUserInfo = userInfo
        if let id = profileID {
            finalUserInfo["profileID"] = id.uuidString
        }
        content.userInfo = finalUserInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let id = UUID().uuidString
        
        let request = UNNotificationRequest(identifier: id, content: content.copy() as! UNNotificationContent, trigger: trigger)

        try await UNUserNotificationCenter.current().add(request)
        
        print("Нотификация с ID: \(id) е успешно планирана for profile: \(profileID?.uuidString ?? "Unassigned").")
        
        return id
    }

    func cancelNotification(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        print("Нотификация с ID: \(id) е отменена.")
    }
    
    func getUnreadNotifications() async -> [NotificationHistoryItem] {
            let deliveredNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
            
            return deliveredNotifications
                .filter { notification in
                    // Изключваме AI нотификациите
                    notification.request.content.userInfo["generationJobID"] == nil
                }
                .map { notification in
                    NotificationHistoryItem(
                        id: notification.request.identifier,
                        title: notification.request.content.title,
                        body: notification.request.content.body,
                        date: notification.date,
                        userInfo: notification.request.content.userInfo
                    )
                }
                .sorted { $0.date > $1.date }
                .prefix(10)
                .map { $0 }

    }
    
    // --- НАЧАЛО НА ПРОМЯНАТА (1/2): Нова функция за значки ---
    /// Връща само непрочетените известия, свързани със значки.
    func getUnreadBadgeNotifications() async -> [NotificationHistoryItem] {
        let deliveredNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
        
        return deliveredNotifications
            .filter { $0.request.content.userInfo["openBadges"] as? String == "true" }
            .map { notification in
                NotificationHistoryItem(
                    id: notification.request.identifier,
                    title: notification.request.content.title,
                    body: notification.request.content.body,
                    date: notification.date,
                    userInfo: notification.request.content.userInfo
                )
            }
    }
    // --- КРАЙ НА ПРОМЯНАТА (1/2) ---

    func removeDeliveredNotification(identifier: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        print("Notification with ID \(identifier) marked as read and removed from history.")
    }

    func removeDeliveredNotifications(identifiers: [String]) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        print("Notifications with IDs \(identifiers) marked as read and removed.")
    }
    
    // --- НАЧАЛО НА ПРОМЯНАТА (2/2): Функцията за AI остава, но я подреждаме ---
    /// Връща само непрочетените известия, свързани с AI.
    func getUnreadAINotifications() async -> [NotificationHistoryItem] {
        let deliveredNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
        
        return deliveredNotifications
            .filter { notification in
                notification.request.content.userInfo["generationJobID"] != nil
            }
            .map { notification in
                NotificationHistoryItem(
                    id: notification.request.identifier,
                    title: notification.request.content.title,
                    body: notification.request.content.body,
                    date: notification.date,
                    userInfo: notification.request.content.userInfo
                )
            }
    }
    
    /// Маркира всички AI известия като прочетени.
    func markAllAINotificationsAsRead() async {
        let aiNotifications = await getUnreadAINotifications()
        let identifiers = aiNotifications.map { $0.id }
        if !identifiers.isEmpty {
            removeDeliveredNotifications(identifiers: identifiers)
            await MainActor.run {
                NotificationCenter.default.post(name: .unreadNotificationStatusChanged, object: nil)
            }
        }
    }
}
