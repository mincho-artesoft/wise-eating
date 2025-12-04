// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth2/WiseEating/Nodes/Views/NodeEditorView.swift ====
import SwiftUI
import SwiftData
import EventKit

@MainActor
struct NodeEditorView: View {
    // MARK: - Dependencies
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var effectManager = EffectManager.shared
    
    var onDismiss: () -> Void
    
    let profile: Profile
    
    // MARK: - Item to edit or nil for new
    let nodeToEdit: Node?
    
    // MARK: - State
    @State private var nodeText: String
    @State private var date: Date
    
    @State private var linkedFoods: [FoodItem] = []
    @State private var linkedExercises: [ExerciseItem] = []
    
    @State private var selectedFoodIDs: Set<FoodItem.ID>
    @State private var selectedExerciseIDs: Set<ExerciseItem.ID>
    @FocusState private var isTextEditorFocused: Bool
    private var isSaveDisabled: Bool {
        nodeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(profile: Profile, node: Node? = nil, onDismiss: @escaping () -> Void) {
        self.profile = profile
        self.nodeToEdit = node
        self.onDismiss = onDismiss
        
        _nodeText = State(initialValue: node?.textContent ?? "")
        _date = State(initialValue: node?.date ?? Date())
        
        if let node = node {
            _selectedFoodIDs = State(initialValue: Set((node.linkedFoods ?? []).map { $0.id }))
            _selectedExerciseIDs = State(initialValue: Set((node.linkedExercises ?? []).map { $0.id }))
        } else {
            _selectedFoodIDs = State(initialValue: [])
            _selectedExerciseIDs = State(initialValue: [])
        }
    }
    
    private var nodeTextEditor: some View {
        ZStack(alignment: .topLeading) {
            Text(nodeText.isEmpty ? " " : nodeText)
                .font(.system(size: 16))
                .foregroundColor(.clear)
                .padding(.horizontal, 5)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)

            if nodeText.isEmpty {
                Text("Enter your thoughts, notes, or observations...")
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6))
                    .font(.system(size: 16))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            
            TextEditor(text: $nodeText)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .frame(maxHeight: 400)
                .focused($isTextEditorFocused)   // 👈 НОВО
        }
        .frame(minHeight: 120, maxHeight: 400)
    }

    
    var body: some View {
        ZStack {
            ThemeBackgroundView().ignoresSafeArea()
            VStack(spacing: 0) {
                toolbar
                
                ScrollView {
                    VStack(spacing: 24) {
                        generalSection
                        foodsSection
                        exercisesSection
                    }
                    .padding()
                    
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
                .onTapGesture {
                    // 👇 При тап някъде в ScrollView (извън писане) да се затвори клавиатурата
                    isTextEditorFocused = false
                }
            }
        }
        .task(id: date) {
            await loadDataFromCalendar()
        }
        .alert("Error", isPresented: .constant(false)) {
            Button("OK") {}
        }
    }

    private var toolbar: some View {
        HStack {
            Button("Cancel", action: onDismiss)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)

            Spacer()
            Text(nodeToEdit == nil ? "New Node" : "Edit Node").font(.headline)
            Spacer()

            Button("Save") {
                Task {
                    await saveNode()
                }
            }
            .disabled(isSaveDisabled)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
            .foregroundStyle(isSaveDisabled ? effectManager.currentGlobalAccentColor.opacity(0.5) : effectManager.currentGlobalAccentColor)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding()
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 16) {
                HStack {
                    Text("Date:")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    CustomDatePicker(
                        selection: $date,
                        tintColor: UIColor(effectManager.currentGlobalAccentColor),
                        textColor: .label
                    )
                    .disabled(nodeToEdit != nil)
                    .frame(height: 40)
                    .opacity(nodeToEdit != nil ? 0.6 : 1.0)
                    // Добавете този .onChange модификатор
                    .onChange(of: date) {
                        selectedFoodIDs.removeAll()
                        selectedExerciseIDs.removeAll()
                    }
                }
                .foregroundColor(effectManager.currentGlobalAccentColor)
                
                StyledLabeledPicker(label: "Note", isFixedHeight: false) {
                    nodeTextEditor
                }
            }
            .padding()
            .glassCardStyle(cornerRadius: 20)
        }
    }

    private var foodsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Link Foods from this Day")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)

            VStack(spacing: 10) {
                if linkedFoods.isEmpty {
                    Text("No foods logged in calendar for this day.")
                        .font(.caption)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(linkedFoods) { food in
                    SelectableFoodRowNode(
                        food: food,
                        isSelected: selectedFoodIDs.contains(food.id)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)   // <- важното
                    .contentShape(Rectangle())                         // цялата ширина да е tappable
                    .onTapGesture {
                        withAnimation(.spring()) {
                            if selectedFoodIDs.contains(food.id) {
                                selectedFoodIDs.remove(food.id)
                            } else {
                                selectedFoodIDs.insert(food.id)
                            }
                        }
                    }
                }
            }
            .padding()
            .glassCardStyle(cornerRadius: 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Link Exercises from this Day")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)

            VStack(spacing: 10) {
                if linkedExercises.isEmpty {
                    Text("No workouts logged in calendar for this day.")
                        .font(.caption)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)

                }

                ForEach(linkedExercises) { exercise in
                    SelectableExerciseRowNode(
                        exercise: exercise,
                        isSelected: selectedExerciseIDs.contains(exercise.id)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)   // <- пак тук
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring()) {
                            if selectedExerciseIDs.contains(exercise.id) {
                                selectedExerciseIDs.remove(exercise.id)
                            } else {
                                selectedExerciseIDs.insert(exercise.id)
                            }
                        }
                    }
                }
            }
            .padding()
            .glassCardStyle(cornerRadius: 20)
            .frame(maxWidth: .infinity, alignment: .leading)

        }
    }


    private func loadDataFromCalendar() async {
        let calendarMeals = await CalendarViewModel.shared.meals(forProfile: profile, on: date)
        let calendarTrainings = await CalendarViewModel.shared.trainings(forProfile: profile, on: date)
        
        var foods = Set<FoodItem>()
        for meal in calendarMeals {
            let mealFoods = meal.foods(using: modelContext)
            for foodItem in mealFoods.keys {
                foods.insert(foodItem)
            }
        }
        
        var exercises = Set<ExerciseItem>()
        for training in calendarTrainings {
            let trainingExercises = training.exercises(using: modelContext)
            for exerciseItem in trainingExercises.keys {
                exercises.insert(exerciseItem)
            }
        }
        
        self.linkedFoods = Array(foods).sorted { $0.name < $1.name }
        self.linkedExercises = Array(exercises).sorted { $0.name < $1.name }
    }
    
    private func saveNode() async {
        let node: Node
        if let existing = nodeToEdit {
            node = existing
        } else {
            node = Node(profile: self.profile)
            modelContext.insert(node)
        }
        
        node.textContent = nodeText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
        node.date = date
        
        node.linkedFoods = self.linkedFoods.filter { selectedFoodIDs.contains($0.id) }
        node.linkedExercises = self.linkedExercises.filter { selectedExerciseIDs.contains($0.id) }
        
        node.profile = self.profile
        
        // --- НАЧАЛО НА ПРОМЯНАТА ---
        await saveNodeToCalendar(node: node, profile: self.profile)
        // --- КРАЙ НА ПРОМЯНАТА ---
        
        do {
            try modelContext.save()
            onDismiss()
        } catch {
            print("Failed to save node: \(error)")
            onDismiss()
        }
    }

    // --- НАЧАЛО НА ПРОМЯНАТА ---
    private func saveNodeToCalendar(node: Node, profile: Profile) async {
        let calendarVM = CalendarViewModel.shared
        guard let calendar = calendarVM.calendarEX(for: profile) else {
            print("Could not find or create a calendar for the profile.")
            return
        }

        let store = calendarVM.eventStore
        let event: EKEvent

        if let eventID = node.calendarEventID, let existingEvent = store.event(withIdentifier: eventID) {
            event = existingEvent
        } else {
            event = EKEvent(eventStore: store)
        }

        event.calendar = calendar
        event.title = "Node"
        event.notes = node.textContent
        event.isAllDay = true
        
        let startOfDay = Calendar.current.startOfDay(for: node.date)
        event.startDate = startOfDay
        event.endDate = startOfDay

        do {
            try store.save(event, span: .thisEvent, commit: true)
            if node.calendarEventID == nil {
                node.calendarEventID = event.eventIdentifier
                print("Created and linked new calendar event with ID: \(event.eventIdentifier ?? "nil")")
            } else {
                print("Updated existing calendar event with ID: \(event.eventIdentifier ?? "nil")")
            }
        } catch {
            print("Failed to save node event to calendar: \(error)")
        }
    }
    // --- КРАЙ НА ПРОМЯНАТА ---
}
