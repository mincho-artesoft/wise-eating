// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/AyurvedaAsanaYoga/AyurvedaAsanaYoga/Settings/SettingsView.swift ====
import SwiftUI
import PhotosUI
import SwiftData
@preconcurrency import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @Query private var profiles: [Profile]
    @Query private var shoppingLists: [ShoppingListModel]

    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var backgroundManager = BackgroundManager.shared
    @ObservedObject private var effectManager = EffectManager.shared

    @AppStorage(NotificationManager.appNotificationsEnabledKey)
    private var appNotificationsEnabled = true

    @State private var notificationPermissionLoaded = false
    @State private var notificationsAuthorized = false
    @State private var showingImagePicker = false
    @State private var inputImage: UIImage?
    @State private var imageToReplace: UIImage?
    
    @Binding var editorState: ThemeEditorState?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                notificationsSection

                Divider().padding(.horizontal)

                Text("Appearance")
                    .font(.title2.bold())
                    .padding(.horizontal)
                
                Text("Choose a theme or a background image to change the application's appearance.")
                    .font(.subheadline)
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 25) {
                        
                        // Бутон за добавяне на нова тема
                        AddThemeButton {
                            self.editorState = .new
                        }
                        
                        if backgroundManager.canAddMoreRecentImages {
                            ImagePickerButton(
                                showingImagePicker: $showingImagePicker
                            )
                        }
                        
                        // Вградени background-и
                        ForEach(backgroundManager.builtInBackgrounds, id: \.name) { background in
                            let isSelected = backgroundManager.selectedImage == background.image

                            VStack(spacing: 8) {
                                ZStack {
                                    Image(uiImage: background.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(Circle())
                                    
                                    Circle()
                                        .stroke(effectManager.currentGlobalAccentColor.opacity(0.1), lineWidth: 1)
                                }
                                .frame(width: 60, height: 60)
                                .shadow(radius: 3, y: 2)
                                .overlay(
                                    Group {
                                        if isSelected {
                                            Circle()
                                                .stroke(effectManager.currentGlobalAccentColor, lineWidth: 4)
                                                .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                                        }
                                    }
                                )
                                .frame(width: 68, height: 68)
                                .scaleEffect(isSelected ? 1.1 : 1.0)

                                Text(background.name)
                                    .font(.caption)
                                    .fontWeight(isSelected ? .bold : .medium)
                            }
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    backgroundManager.selectBuiltInBackground(background.image)
                                }
                            }
                        }
                        
                        // Списък с последни изображения (User added)
                        ForEach(backgroundManager.recentImages, id: \.self) { image in
                               RecentImageButton(
                                   image: image,
                                   isSelected: backgroundManager.selectedImage == image,
                                   action: { backgroundManager.selectImage(image) }
                               )
                               .contextMenu {
                                Button {
                                    self.imageToReplace = image
                                    self.showingImagePicker = true
                                } label: { Label("Replace", systemImage: "arrow.triangle.2.circlepath") }
                                
                                Button(role: .destructive) {
                                    withAnimation { backgroundManager.deleteRecentImage(image) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }

                        // Списък с наличните теми
                        ForEach(themeManager.allAvailableThemes) { theme in
                            ThemePickerButton(theme: theme, selectedTheme: $themeManager.currentTheme)
                                .contextMenu {
                                    if !theme.isDefaultTheme {
                                        Button {
                                            self.editorState = .edit(theme)
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }

                                        Button(role: .destructive) {
                                            withAnimation { themeManager.deleteCustomTheme(themeToDelete: theme) }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    } else {
                                        Text(theme.name).font(.subheadline)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .frame(height: 120)
                
                Divider().padding(.horizontal)
                
                EffectControlPanelView()
                  
            }
            .padding(.top)
            Spacer(minLength: 150)
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
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $inputImage)
        }
        .onChange(of: inputImage) { _, newImage in
            guard let newImage = newImage else { return }

            if let oldImage = imageToReplace {
                backgroundManager.replaceRecentImage(oldImage: oldImage, with: newImage)
                self.imageToReplace = nil
            } else {
                backgroundManager.addImageToRecents(newImage)
            }
        }
        .onChange(of: themeManager.currentTheme) { _, newTheme in
            themeManager.setTheme(to: newTheme)
        }
        .task {
            await refreshNotificationPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await refreshNotificationPermission(restoreRemindersWhenAuthorized: true)
            }
        }
    }

    @ViewBuilder
    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Notifications")
                    .font(.title2.bold())

                Image(
                    systemName: notificationsAuthorized && appNotificationsEnabled
                        ? "bell.fill"
                        : "bell.slash.fill"
                )
                .font(.title3.weight(.semibold))
            }

            if !notificationPermissionLoaded {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking notification permission…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if notificationsAuthorized {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Allow notifications in Ayura")
                            .font(.headline)

                        Text("Controls reminders and updates for the entire app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Toggle("", isOn: $appNotificationsEnabled)
                        .labelsHidden()
                        .tint(effectManager.currentGlobalAccentColor)
                        .onChange(of: appNotificationsEnabled) { _, isEnabled in
                            Task {
                                await applyNotificationPreference(isEnabled)
                            }
                        }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Notifications are disabled in iOS", systemImage: "bell.slash.fill")
                        .font(.headline)

                    Text("Open Settings → Apps → Ayura → Notifications and turn on Allow Notifications.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                        openURL(url)
                    } label: {
                        Label("Open iOS Settings", systemImage: "gear")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(effectManager.currentGlobalAccentColor)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(.horizontal)
    }

    @MainActor
    private func refreshNotificationPermission(
        restoreRemindersWhenAuthorized: Bool = false
    ) async {
        let wasAuthorized = notificationsAuthorized
        let status = await NotificationManager.shared.getAuthorizationStatus()
        notificationsAuthorized = status == .authorized
            || status == .provisional
            || status == .ephemeral
        notificationPermissionLoaded = true

        if restoreRemindersWhenAuthorized,
           notificationsAuthorized,
           !wasAuthorized,
           appNotificationsEnabled {
            await restoreFutureReminders()
        }
    }

    @MainActor
    private func applyNotificationPreference(_ isEnabled: Bool) async {
        await NotificationManager.shared.setAppNotificationsEnabled(isEnabled)
        if isEnabled {
            await restoreFutureReminders()
        }
    }

    @MainActor
    private func restoreFutureReminders() async {
        guard notificationsAuthorized, appNotificationsEnabled else { return }

        for profile in profiles {
            for meal in profile.meals {
                if let oldID = meal.notificationID {
                    NotificationManager.shared.cancelNotification(id: oldID)
                    meal.notificationID = nil
                }

                guard let minutes = meal.reminderMinutes, minutes > 0 else { continue }
                let reminderDate = meal.startTime.addingTimeInterval(-TimeInterval(minutes * 60))
                guard reminderDate > Date() else { continue }

                meal.notificationID = try? await NotificationManager.shared.scheduleNotification(
                    title: "🍽️ Meal Reminder",
                    body: "It's time for your \(meal.name). Enjoy!",
                    timeInterval: reminderDate.timeIntervalSinceNow,
                    userInfo: [
                        "mealID": meal.id.uuidString,
                        "mealDate": meal.startTime.timeIntervalSince1970,
                    ],
                    profileID: profile.id
                )
            }

            for training in profile.trainings {
                if let oldID = training.notificationID {
                    NotificationManager.shared.cancelNotification(id: oldID)
                    training.notificationID = nil
                }

                guard let minutes = training.reminderMinutes, minutes > 0 else { continue }
                let reminderDate = training.startTime.addingTimeInterval(-TimeInterval(minutes * 60))
                guard reminderDate > Date() else { continue }

                training.notificationID = try? await NotificationManager.shared.scheduleNotification(
                    title: "🧘 Workout Reminder",
                    body: "Time for your workout: \(training.name)!",
                    timeInterval: reminderDate.timeIntervalSinceNow,
                    userInfo: [
                        "trainingID": training.id.uuidString,
                        "trainingDate": training.startTime.timeIntervalSince1970,
                        "trainingName": training.name,
                    ],
                    profileID: profile.id
                )
            }
        }

        for list in shoppingLists where !list.isCompleted {
            if let oldID = list.notificationID {
                NotificationManager.shared.cancelNotification(id: oldID)
                list.notificationID = nil
            }

            guard let minutes = list.reminderMinutes, minutes > 0 else { continue }
            let reminderDate = list.eventStartDate.addingTimeInterval(-TimeInterval(minutes * 60))
            guard reminderDate > Date() else { continue }

            list.notificationID = try? await NotificationManager.shared.scheduleNotification(
                title: "🛒 Shopping Reminder",
                body: "Time to buy groceries for your list: \(list.name)",
                timeInterval: reminderDate.timeIntervalSinceNow,
                userInfo: ["shoppingListID": list.id.uuidString],
                profileID: list.profile?.id
            )
        }

        await NotificationManager.shared.refreshPracticeReminderIfNeeded()
        try? modelContext.save()
    }
}
