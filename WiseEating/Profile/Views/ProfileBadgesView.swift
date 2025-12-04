// WiseEating/Profile/Views/ProfileBadgesView.swift
import SwiftUI
import SwiftData

struct ProfileBadgesView: View {
    let profile: Profile
    @ObservedObject private var effectManager = EffectManager.shared
    
    // MARK: - Safe area / toolbar state
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @Environment(\.modelContext) private var modelContext
    
    @State private var currentTimeString: String = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let tFmt = DateFormatter.shortTime
    @State private var hasUnreadNotifications: Bool = false
    
    @State private var uniqueFoodsCount: Int = 0
    @State private var nutritionStreak: Int = 0
    @State private var uniqueExercisesCount: Int = 0
    @State private var workoutStreak: Int = 0
    // +++ НАЧАЛО НА ПРОМЯНАТА (1/5): Добавяме ново състояние за дните на активност +++
    @State private var usageDaysCount: Int = 0
    // +++ КРАЙ НА ПРОМЯНАТА (1/5) +++
    
    private var headerTopPadding: CGFloat {
        -safeAreaInsets.top + 10
    }
    
    // MARK: - Data Structures
    
    // --- НАЧАЛО НА ПРОМЯНАТА (2/5): Премахваме локалните дефиниции ---
    // private struct BadgeItem...
    // private struct BadgeGroup...
    // --- КРАЙ НА ПРОМЯНАТА (2/5) ---
    
    // MARK: - Badge Configuration
    // --- НАЧАЛО НА ПРОМЯНАТА (3/5): Актуализираме дефинициите, за да съвпадат с BadgeManager ---
    private let badgeGroups: [BadgeGroup] = [
        .init(
            title: "Foods",
            items: [
                .init(id: "Foods 25", imageName: "Foods 25", label: "25 Foods", threshold: 25),
                .init(id: "Foods 50", imageName: "Foods 50", label: "50 Foods", threshold: 50),
                .init(id: "Foods 100", imageName: "Foods 100", label: "100 Foods", threshold: 100)
            ]
        ),
        .init(
            title: "Nutrition",
            items: [
                .init(id: "Nutrition 3d", imageName: "Nutrition 3d", label: "3 Days", threshold: 3),
                .init(id: "Nutrition 1w", imageName: "Nutrition 1w", label: "1 Week", threshold: 7),
                .init(id: "Nutrition 1m", imageName: "Nutrition 1m", label: "1 Month", threshold: 30)
            ]
        ),
        .init(
            title: "Exercises",
            items: [
                .init(id: "Exercises 10", imageName: "Exercises 10", label: "10 Workouts", threshold: 10),
                .init(id: "Exercises 25", imageName: "Exercises 25", label: "25 Workouts", threshold: 25),
                .init(id: "Exercises 50", imageName: "Exercises 50", label: "50 Workouts", threshold: 50)
            ]
        ),
        .init(
            title: "Workout",
            items: [
                .init(id: "Workout 3d", imageName: "Workout 3d", label: "3 Days Streak", threshold: 3),
                .init(id: "Workout 1w", imageName: "Workout 1w", label: "1 Week Streak", threshold: 7),
                .init(id: "Workout 1m", imageName: "Workout 1m", label: "1 Month Streak", threshold: 30)
            ]
        ),
        .init(
            title: "Usage",
            items: [
                .init(id: "Usage 3d", imageName: "Usage 3d", label: "3 Days Active", threshold: 3),
                .init(id: "Usage 1w", imageName: "Usage 1w", label: "1 Week Active", threshold: 7),
                .init(id: "Usage 1m", imageName: "Usage 1m", label: "1 Month Active", threshold: 30)
            ]
        ),
    ]
    // --- КРАЙ НА ПРОМЯНАТА (3/5) ---
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            userToolbar(for: profile)
                .padding(.trailing, 50)
                .padding(.leading, 40)
                .padding(.horizontal, -20)
                .padding(.bottom, 8)
            
            UpdatePlanBanner()
            
            customToolbar
                .padding(.horizontal)
                .padding(.bottom, 8)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(badgeGroups.enumerated()), id: \.element.id) { index, group in
                        VStack(alignment: .leading, spacing: 12) {
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(group.title)
                                        .font(.headline)
                                        .foregroundColor(effectManager.currentGlobalAccentColor)
                                    
                                    if group.title == "Foods" {
                                        Spacer()
                                        Text("\(uniqueFoodsCount) unique tracked")
                                            .font(.caption)
                                            .bold()
                                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                                    } else if group.title == "Nutrition" {
                                        Spacer()
                                        Text("\(nutritionStreak) day streak")
                                            .font(.caption)
                                            .bold()
                                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                                    } else if group.title == "Exercises" {
                                        Spacer()
                                        Text("\(uniqueExercisesCount) unique tracked")
                                            .font(.caption)
                                            .bold()
                                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                                    } else if group.title == "Workout" {
                                        Spacer()
                                        Text("\(workoutStreak) day streak")
                                            .font(.caption)
                                            .bold()
                                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                                    // +++ НАЧАЛО НА ПРОМЯНАТА (4/5): Добавяме показване на броя дни на активност +++
                                    } else if group.title == "Usage" {
                                        Spacer()
                                        Text("\(usageDaysCount) active days")
                                            .font(.caption)
                                            .bold()
                                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                                    }
                                    // +++ КРАЙ НА ПРОМЯНАТА (4/5) +++
                                }
                                
                                // --- НАЧАЛО НА ПРОМЯНАТА (3/5): Премахваме subtitle, който вече не съществува в модела ---
                                // Text(group.subtitle)
                                // --- КРАЙ НА ПРОМЯНАТА (3/5) ---
                            }
                            .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 30) {
                                    ForEach(group.items) { item in
                                        let isUnlocked = checkIsUnlocked(groupTitle: group.title, item: item)
                                        
                                        VStack(spacing: 12) {
                                            Image(item.imageName)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(height: 175)
                                                .shadow(radius: isUnlocked ? 4 : 0)
                                                .grayscale(isUnlocked ? 0 : 1.0)
                                                .opacity(isUnlocked ? 1.0 : 0.3)
                                            
                                            Text(item.label)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(isUnlocked ? 0.9 : 0.4))
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 10)
                            }
                        }
                        .padding(.top, 10)
                        if index < badgeGroups.count - 1 {
                            Rectangle()
                                .fill(effectManager.currentGlobalAccentColor.opacity(0.3))
                                .frame(height: 1)
                                .padding(.horizontal)
                                .padding(.top, 5)
                        }
                    }
                }
                
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
        }
        .padding(.top, headerTopPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeBackgroundView().ignoresSafeArea())
        .onReceive(timer) { _ in
            self.currentTimeString = Self.tFmt.string(from: Date())
        }
        .task {
            await checkForUnreadNotifications()
            await calculateStatsForDisplay()
        }
    }
    
    // MARK: - Logic for Unlocking
    
    private func checkIsUnlocked(groupTitle: String, item: BadgeItem) -> Bool {
        // Проверката вече ще работи коректно
        return profile.unlockedBadgeIDs.contains(item.id)
    }

    private func calculateStatsForDisplay() async {
        let (uniqueFoods, nutritionS) = await BadgeManager.shared.calculateNutritionStats(for: profile)
        let (uniqueExercises, workoutS) = await BadgeManager.shared.calculateExerciseStats(for: profile)
        
        await MainActor.run {
            self.uniqueFoodsCount = uniqueFoods
            self.nutritionStreak = nutritionS
            self.uniqueExercisesCount = uniqueExercises
            self.workoutStreak = workoutS
            // +++ НАЧАЛО НА ПРОМЯНАТА (5/5): Зареждаме и дните на активност +++
            self.usageDaysCount = UsageTrackingManager.shared.getUsageCount(for: profile)
            // +++ КРАЙ НА ПРОМЯНАТА (5/5) +++
        }
    }
    
    // MARK: - Toolbars
    
    @ViewBuilder
    private func userToolbar(for profile: Profile) -> some View {
        HStack {
            Text(currentTimeString)
                .font(.system(size: 16))
                .fontWeight(.medium)
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .onAppear {
                    self.currentTimeString = Self.tFmt.string(from: Date())
                }
            
            Spacer()
            
            Button(action: {
                NotificationCenter.default.post(
                    name: Notification.Name("openProfilesDrawer"),
                    object: nil
                )
            }) {
                ZStack(alignment: .topTrailing) {
                    if let photoData = profile.photoData,
                       let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        ZStack {
                            Circle()
                                .fill(effectManager.currentGlobalAccentColor.opacity(0.2))
                            if let firstLetter = profile.name.first {
                                Text(String(firstLetter))
                                    .font(.headline)
                                    .foregroundColor(effectManager.currentGlobalAccentColor)
                            }
                        }
                        .frame(width: 40, height: 40)
                    }
                    
                    if hasUnreadNotifications {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 12, height: 12)
                            .offset(x: 1, y: -1)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(effectManager.currentGlobalAccentColor)
        }
    }
    
    private var customToolbar: some View {
        HStack {
            Text("Badges")
                .font(.title.bold())
                .foregroundColor(effectManager.currentGlobalAccentColor)
            
            Spacer()
        }
    }
    
    // MARK: - Notifications
    
    private func checkForUnreadNotifications() async {
        let unread = await NotificationManager.shared.getUnreadNotifications()
        self.hasUnreadNotifications = !unread.isEmpty
    }
}
