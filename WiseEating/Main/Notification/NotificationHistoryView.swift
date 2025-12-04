import SwiftUI
import EventKit
import SwiftData
import UserNotifications // Необходим за UNAuthorizationStatus

struct NotificationHistoryView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @Binding var currentDrawerContent: RootView.ProfilesDrawerContent

    let onDismiss: () -> Void

    @State private var unreadNotifications: [NotificationHistoryItem]? = nil
    @Query private var profiles: [Profile]
    
    // --- ПРОМЯНА 1: Състояние за статуса на правата ---
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar (Остава винаги видим, за да може потребителят да се върне назад)
            HStack {
                Button {
                    withAnimation {
                        currentDrawerContent = .profiles
                    }
                } label: {
                    HStack {
                        Text("Back")
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)

                Spacer()
                Text("Notification History").font(.headline)
                Spacer()
                
                // Бутонът Clear All се показва само ако имаме права и има известия
                if authorizationStatus != .denied && unreadNotifications?.isEmpty == false {
                    Button("Clear All", action: clearAllNotifications)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .glassCardStyle(cornerRadius: 20)
                } else {
                    Button("Clear All") {}.hidden()
                        .padding(.horizontal, 10).padding(.vertical, 5)
                }
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .padding()

            // --- ПРОМЯНА 2: Проверка на статуса ---
            if authorizationStatus == .denied {
//                ScrollView(showsIndicators: false) {
                    // Ако са отказани, показваме екрана за подкана
                    PermissionDeniedView(
                        type: .notifications,
                        hasBackground: false // Важно: без фон, за да стои добре в този view
                    ) {
                        // Callback при връщане от настройките
                        Task { await checkPermissions() }
                    }
                    Spacer()
//                }
            } else {
                // Ако са разрешени (или notDetermined/provisional), показваме списъка
                contentView
            }
        }
        .task {
            // --- ПРОМЯНА 3: Проверяваме правата при зареждане ---
            await checkPermissions()
            if authorizationStatus != .denied {
                self.unreadNotifications = await NotificationManager.shared.getUnreadNotifications()
            }
        }
        // --- ПРОМЯНА 4: Опресняване при връщане от Settings ---
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await checkPermissions()
                if authorizationStatus != .denied {
                    self.unreadNotifications = await NotificationManager.shared.getUnreadNotifications()
                }
            }
        }
    }

    // Изнасяме логиката за съдържанието в отделна променлива за по-чист код
    @ViewBuilder
    private var contentView: some View {
        if let notifications = unreadNotifications {
            if notifications.isEmpty {
                ContentUnavailableView(
                    "No Unread Notifications",
                    systemImage: "bell.slash",
                    description: Text("You're all caught up!")
                )
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                .padding()
                Spacer()
            } else {
                List {
                    ForEach(notifications) { notification in
                        notificationRow(for: notification)
                            .swipeActions {
                                Button(role: .destructive) {
                                    markAsRead(notification: notification)
                                } label: {
                                    Image(systemName: "trash.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                                }
                                .tint(.clear)
                            }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    
                    Color.clear.frame(height: 150)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
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
            }
        } else {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
            Spacer()
        }
    }

    @ViewBuilder
    private func notificationRow(for notification: NotificationHistoryItem) -> some View {
        let profileName: String? = {
            if let profileIDString = notification.userInfo["profileID"] as? String,
               let profileID = UUID(uuidString: profileIDString) {
                return profiles.first { $0.id == profileID }?.name
            }
            return nil
        }()
        
        Button(action: {
            handleNotificationTap(for: notification)
        }) {
            HStack(spacing: 12) {
                VStack {
                    let isBadgeNotification = notification.userInfo["openBadges"] as? String == "true"
                    
                    let iconName = if isBadgeNotification {
                        "rosette"
                    } else if notification.userInfo["trainingID"] != nil {
                        "dumbbell.fill"
                    } else if notification.userInfo["mealID"] != nil {
                        "fork.knife"
                    } else {
                        "cart.fill" // Fallback for shopping list
                    }
                    
                    Image(systemName: iconName)
                        .font(.title2)
                        .frame(width: 30)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                }
                
                VStack(alignment: .leading) {
                    Text(notification.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(notification.body)
                        .font(.subheadline)
                        .lineLimit(2)
                        .opacity(0.8)
                    
                    HStack(spacing: 6) {
                        if let name = profileName {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.caption2)
                            Text(name)
                                .font(.caption2.weight(.semibold))
                        }
                        Text("•")
                            .font(.caption2)
                        Text(notification.date, style: .relative)
                            .font(.caption2)
                    }
                    .opacity(0.6)
                }
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .glassCardStyle(cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }

    // --- ПРОМЯНА 5: Функция за проверка на правата ---
    private func checkPermissions() async {
        let status = await NotificationManager.shared.getAuthorizationStatus()
        withAnimation {
            self.authorizationStatus = status
        }
    }

    private func markAsRead(notification: NotificationHistoryItem) {
        NotificationManager.shared.removeDeliveredNotification(identifier: notification.id)
        withAnimation {
            unreadNotifications?.removeAll { $0.id == notification.id }
        }
        NotificationCenter.default.post(name: .unreadNotificationStatusChanged, object: nil)
    }
    
    private func clearAllNotifications() {
        guard let notificationsToClear = unreadNotifications, !notificationsToClear.isEmpty else { return }
        
        let identifiers = notificationsToClear.map { $0.id }
        NotificationManager.shared.removeDeliveredNotifications(identifiers: identifiers)
        
        withAnimation {
            unreadNotifications?.removeAll()
        }
        NotificationCenter.default.post(name: .unreadNotificationStatusChanged, object: nil)
    }

    private func handleNotificationTap(for notification: NotificationHistoryItem) {
        let userInfo = notification.userInfo

        onDismiss()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let coordinator = NavigationCoordinator.shared
            
            if let profileIDString = userInfo["profileID"] as? String,
               let profileID = UUID(uuidString: profileIDString) {
                coordinator.pendingProfileID = profileID
            }
            
            if let listIDString = userInfo["shoppingListID"] as? String,
               let listID = UUID(uuidString: listIDString) {
                coordinator.pendingShoppingListID = listID
            }
            else if let mealIDString = userInfo["mealID"] as? String,
                      let mealID = UUID(uuidString: mealIDString),
                      let mealDateTimeInterval = userInfo["mealDate"] as? TimeInterval {
                let mealDate = Date(timeIntervalSince1970: mealDateTimeInterval)
                coordinator.pendingMealID = mealID
                coordinator.pendingMealDate = mealDate
            }
            else if let trainingIDString = userInfo["trainingID"] as? String,
                      let trainingID = UUID(uuidString: trainingIDString),
                      let trainingDateTimeInterval = userInfo["trainingDate"] as? TimeInterval,
                      let trainingName = userInfo["trainingName"] as? String {
                let trainingDate = Date(timeIntervalSince1970: trainingDateTimeInterval)
                coordinator.pendingTrainingID = trainingID
                coordinator.pendingTrainingDate = trainingDate
                coordinator.pendingTrainingName = trainingName
            }
            else if let openBadges = userInfo["openBadges"] as? String, openBadges == "true" {
                coordinator.pendingBadgeProfileID = coordinator.pendingProfileID
            }
        }

        markAsRead(notification: notification)
    }
}
