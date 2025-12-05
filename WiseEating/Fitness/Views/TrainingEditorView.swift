import SwiftUI
import UserNotifications

struct TrainingEditorView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    @State private var draft: Training
    var isNew: Bool
    var onSave: (Training) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var reminderOffset: Int
    private let reminderOptions = [0, 5, 10, 15, 30, 60] // 0 means "None"
    
    // Състояние за статуса на нотификациите
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    
    private struct InitialState: Equatable {
        let name: String
        let startTime: Date
        let endTime: Date
        let reminderMinutes: Int?
    }
    
    @State private var initialState: InitialState

    init(training: Training, isNew: Bool, onSave: @escaping (Training) -> Void) {
        _draft = State(initialValue: Training(from: training))
        self.isNew = isNew
        self.onSave = onSave
        
        _reminderOffset = State(initialValue: training.reminderMinutes ?? 0)

        _initialState = State(initialValue: InitialState(
            name: training.name,
            startTime: training.startTime,
            endTime: training.endTime,
            reminderMinutes: training.reminderMinutes
        ))
    }

    private var hasChanges: Bool {
        let currentReminder = reminderOffset == 0 ? nil : reminderOffset
        let currentState = InitialState(
            name: draft.name,
            startTime: draft.startTime,
            endTime: draft.endTime,
            reminderMinutes: currentReminder
        )
        return currentState != initialState
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ThemeBackgroundView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                customToolbar
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 25) {
                    HStack {
                        Text("Workout Name")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        
                        TextField("", text: $draft.name, prompt: Text("e.g., Morning Run").foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6)))
                            .font(.system(size: 16))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                            .multilineTextAlignment(.trailing)
                            .disableAutocorrection(true)
                    }
                    
                    HStack {
                        Text("Start Time")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        Spacer()
                        CustomTimePicker(
                            selection: $draft.startTime,
                            textColor: UIColor(effectManager.currentGlobalAccentColor)
                        )
                        .frame(height: 40)
                    }

                    HStack {
                        Text("End Time")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        Spacer()
                        CustomTimePicker(
                            selection: $draft.endTime,
                            textColor: UIColor(effectManager.currentGlobalAccentColor)
                        )
                        .frame(height: 40)
                    }
                    
                    // --- ЛОГИКА ЗА REMINDER ---
                    if notificationStatus == .denied {
                        // Ако известията са забранени
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Reminder")
                                Spacer()
                                Text("Notifications are disabled. Please enable them in Settings if you want to use reminders for your workouts.")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(effectManager.currentGlobalAccentColor)
                            }
                        }
                    } else {
                        // Ако са разрешени или не са определени
                        HStack {
                            Text("Reminder")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(effectManager.currentGlobalAccentColor)
                            Spacer()
                            Picker("", selection: $reminderOffset) {
                                ForEach(reminderOptions, id: \.self) { minutes in
                                    Text(formatReminder(minutes)).tag(minutes)
                                }
                            }
                            .tint(effectManager.currentGlobalAccentColor)
                        }
                    }
                    // --------------------------
                }
                .padding()
                .glassCardStyle(cornerRadius: 20)
                .padding()
                
                Spacer()
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            checkNotificationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            checkNotificationStatus()
        }
    }

    @ViewBuilder
    private var customToolbar: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack {
                    Text("Back")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
            
            Spacer()
            Text(isNew ? "Add Workout" : "Edit Workout").font(.headline)
            Spacer()
            
            let isDataValid = !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && draft.endTime > draft.startTime
            let isSaveDisabled = !isDataValid || (!isNew && !hasChanges)
            
            Button("Save") {
                if notificationStatus == .denied {
                    draft.reminderMinutes = nil
                } else {
                    draft.reminderMinutes = reminderOffset == 0 ? nil : reminderOffset
                }
                onSave(draft)
                dismiss()
            }
            .disabled(isSaveDisabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
            .foregroundStyle(isSaveDisabled ? effectManager.currentGlobalAccentColor.opacity(0.4) : effectManager.currentGlobalAccentColor)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding(.top, 10)
    }

    private func formatReminder(_ minutes: Int) -> String {
        if minutes == 0 {
            return "None"
        }
        return "\(minutes) min before"
    }
    
    private func checkNotificationStatus() {
        Task {
            let status = await NotificationManager.shared.getAuthorizationStatus()
            await MainActor.run {
                withAnimation {
                    self.notificationStatus = status
                }
            }
        }
    }
}
