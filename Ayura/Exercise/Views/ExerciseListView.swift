import SwiftUI
import SwiftData

struct ExerciseListView: View {
    // MARK: – Env & Deps
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    // MARK: - Inputs
    let profile: Profile?
    @Binding var globalSearchText: String
    @Binding var isSearching: Bool
    @Binding var navBarIsHiden: Bool
    @Binding var isProfilesDrawerVisible: Bool
    @State private var SIsSearching = false
    @State private var SglobalSearchText = ""
    let onActivateSearch: () -> Void
    let onDismissSearch: () -> Void
    @FocusState.Binding var isSearchFieldFocused: Bool

    // MARK: - VM
    @ObservedObject var vm: ExerciseListVM
    @StateObject var trainingPlanVM: TrainingPlanListVM

    // MARK: - Presentation
    @State private var presentedItem: PresentedItem? = nil
    @State private var isAddButtonVisible = true

    enum PresentedItem: Identifiable {
        case new, edit(ExerciseItem), detail(ExerciseItem)
        case newWorkout, editWorkout(ExerciseItem)
        case newPlan, editPlan(TrainingPlan), detailPlan(TrainingPlan)
        case detailTemplate(TrainingPlanListVM.DisplayPlan)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let item): "edit-\(item.id)"
            case .detail(let item): "detail-\(item.id)"
            case .newWorkout: "newWorkout"
            case .editWorkout(let item): "editWorkout-\(item.id)"
            case .newPlan: "newPlan"
            case .editPlan(let plan): "editPlan-\(plan.id)"
            case .detailPlan(let plan): "detailPlan-\(plan.id)"
            case .detailTemplate(let plan): "detailTemplate-\(plan.id)"
            }
        }
    }

    // MARK: - Floating Button Drag
    @State private var buttonOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @GestureState private var gestureDragOffset: CGSize = .zero
    @State private var isPressed: Bool = false
    private let buttonPositionKey = "exerciseFloatingButtonPosition"

    // MARK: - Deleting
    @State private var isShowingDeleteItemConfirmation = false
    @State private var itemToDelete: ExerciseItem? = nil
    @State private var itemUsageCount: Int = 0

    // ✅ FIX: НЕ държим TrainingPlan reference в state за delete!
    @State private var isShowingDeletePlanConfirmation = false
    @State private var planToDeleteID: UUID? = nil
    @State private var planToDeleteName: String = ""
    @State private var planToDeleteLinkedWorkoutCount: Int = 0

    // MARK: - Time / Notifications
    @State private var currentTimeString: String = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let tFmt = DateFormatter.shortTime
    @State private var hasUnreadNotifications: Bool = false

    typealias Filter = ExerciseListVM.Filter

    // MARK: - Init
    init(
        vm: ExerciseListVM,
        profile: Profile?,
        globalSearchText: Binding<String>,
        isSearching: Binding<Bool>,
        navBarIsHiden: Binding<Bool>,
        isProfilesDrawerVisible: Binding<Bool>,
        onActivateSearch: @escaping () -> Void,
        onDismissSearch: @escaping () -> Void,
        isSearchFieldFocused: FocusState<Bool>.Binding
    ) {
        self.vm = vm
        self.profile = profile
        self._globalSearchText = globalSearchText
        self._isSearching = isSearching
        self._navBarIsHiden = navBarIsHiden
        self._isProfilesDrawerVisible = isProfilesDrawerVisible
        self.onActivateSearch = onActivateSearch
        self.onDismissSearch = onDismissSearch
        self._isSearchFieldFocused = isSearchFieldFocused
        _trainingPlanVM = StateObject(wrappedValue: TrainingPlanListVM(profile: profile))
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    mainContent
                        .opacity(presentedItem == nil ? 1 : 0)
                        .allowsHitTesting(presentedItem == nil)
                        .zIndex(0)

                    if let item = presentedItem {
                        presentedItemView(for: item)
                            .transition(.move(edge: .trailing))
                            .zIndex(10)
                    }
                }

                if !isSearching &&
                    (vm.filter != .default && vm.filter != .favorites) &&
                    !(vm.filter == .plans && trainingPlanVM.selectedScope == .templates) &&
                    isAddButtonVisible &&
                    !navBarIsHiden {
                    addButton(geometry: geometry)
                }
            }
            .onReceive(timer) { _ in
                self.currentTimeString = Self.tFmt.string(from: Date())
            }
            .task { await checkForUnreadNotifications() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await checkForUnreadNotifications() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .unreadNotificationStatusChanged)) { _ in
                Task { await checkForUnreadNotifications() }
            }
        }
        .onAppear {
            vm.attach(context: modelContext)
            trainingPlanVM.attach(context: modelContext)
            vm.ensureInitialLoad(withInitialSearch: globalSearchText)
            loadButtonPosition()
        }
        .onChange(of: globalSearchText) { _, newValue in
            vm.searchText = newValue
            if vm.filter == .plans {
                trainingPlanVM.searchText = newValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .exerciseFavoriteToggled)) { notification in
            vm.updateItemAndPruneFavorites(notification: notification)
        }
        .onChange(of: vm.filter) { newFilter in
            if newFilter == .plans {
                trainingPlanVM.fetchPlans()
            }
        }
        .onChange(of: modelContext) { _, new in
            vm.attach(context: new)
            trainingPlanVM.attach(context: new)
        }
    }

    private func checkForUnreadNotifications() async {
        let unread = await NotificationManager.shared.getUnreadNotifications()
        self.hasUnreadNotifications = !unread.isEmpty
    }

    // MARK: - Main Content
    private var mainContent: some View {
        ZStack {
            VStack(spacing: 0) {
                if let profile {
                    userToolbar(for: profile)
                        .padding(.trailing, 50)
                        .padding(.leading, 40)
                        .padding(.horizontal, -20)
                        .padding(.bottom, 8)
                }

                UpdatePlanBanner()

                customToolbar
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                let layoutMode: WrappingSegmentedControl<Filter>.LayoutMode =
                (horizontalSizeClass == .regular) ? .wrap : .scrollable

                WrappingSegmentedControl(selection: $vm.filter, layoutMode: layoutMode)
                    .padding(.bottom, 5)

                if vm.filter == .plans {
                    trainingPlansSection
                } else if vm.items.isEmpty && !vm.isLoading {
                    Spacer()
                    ContentUnavailableView {
                        Label(emptyStateTitle, systemImage: "dumbbell")
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                    } description: {
                        emptyStateDescription
                    }
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    Spacer()
                } else {
                    exerciseItemsList
                }
            }
            .padding(.top, headerTopPadding)

            // Delete Exercise alert (не е променян)
            .alert("Delete Exercise", isPresented: $isShowingDeleteItemConfirmation) {
                Button("Delete", role: .destructive) {
                    if let item = itemToDelete {
                        withAnimation {
                            if itemUsageCount > 0 {
                                vm.deleteDetachingFromWorkoutsAndPlans(item)
                            } else {
                                vm.delete(item)
                            }
                        }
                    }
                    itemToDelete = nil
                    itemUsageCount = 0
                }
                Button("Cancel", role: .cancel) {
                    itemToDelete = nil
                    itemUsageCount = 0
                }
            } message: {
                if let item = itemToDelete {
                    if itemUsageCount > 0 {
                        Text("""
This exercise is used in \(itemUsageCount) workouts or training plans.
If you delete it, it will be removed from those workouts and plans.

Are you sure you want to continue?
""")
                    } else {
                        Text("Are you sure you want to delete '\(item.name)'? This action cannot be undone.")
                    }
                } else {
                    Text("")
                }
            }

            // ✅ FIX: Delete Training Plan alert (без достъп до plan.days след delete)
            .alert(
                planToDeleteName.isEmpty ? "Delete Training Plan" : "Delete \"\(planToDeleteName)\"",
                isPresented: $isShowingDeletePlanConfirmation
            ) {
                Button("Delete Plan Only", role: .destructive) {
                    if let id = planToDeleteID {
                        trainingPlanVM.deletePlan(planID: id, alsoDeleteLinkedWorkouts: false)
                    }
                    planToDeleteID = nil
                    planToDeleteName = ""
                    planToDeleteLinkedWorkoutCount = 0
                }

                Button("Delete Plan & Workouts", role: .destructive) {
                    if let id = planToDeleteID {
                        trainingPlanVM.deletePlan(planID: id, alsoDeleteLinkedWorkouts: true)
                    }
                    planToDeleteID = nil
                    planToDeleteName = ""
                    planToDeleteLinkedWorkoutCount = 0
                }

                Button("Cancel", role: .cancel) {
                    planToDeleteID = nil
                    planToDeleteName = ""
                    planToDeleteLinkedWorkoutCount = 0
                }
            } message: {
                if planToDeleteLinkedWorkoutCount > 0 {
                    Text("""
This training plan has \(planToDeleteLinkedWorkoutCount) linked workout(s).

• "Delete Plan Only" will remove the plan but keep the workouts in your exercise library.
• "Delete Plan & Workouts" will delete the plan and those linked workouts as well.

What would you like to do?
""")
                } else {
                    Text("Are you sure you want to delete this training plan? This action cannot be undone.")
                }
            }

            if vm.isLoading && vm.items.isEmpty {
                Color.black.opacity(0.05)
                    .ignoresSafeArea()

                ProgressView()
                    .scaleEffect(1.2)
                    .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, effectManager.isLightRowTextColor ? .dark : .light)
                    }
                    .shadow(radius: 6)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Toolbars
    @ViewBuilder
    private func userToolbar(for profile: Profile) -> some View {
        HStack {
            Text(currentTimeString)
                .font(.system(size: 16)).fontWeight(.medium)
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .onAppear { self.currentTimeString = Self.tFmt.string(from: Date()) }

            Spacer()

            Button(action: { NotificationCenter.default.post(name: .openProfilesDrawer, object: nil) }) {
                ZStack(alignment: .topTrailing) {
                    if let photoData = profile.photoData, let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage).resizable().scaledToFill()
                            .frame(width: 40, height: 40).clipShape(Circle())
                    } else {
                        ZStack {
                            Circle().fill(effectManager.currentGlobalAccentColor.opacity(0.2))
                            if let firstLetter = profile.name.first {
                                Text(String(firstLetter)).font(.headline)
                                    .foregroundColor(effectManager.currentGlobalAccentColor)
                            }
                        }.frame(width: 40, height: 40)
                    }
                    if hasUnreadNotifications {
                        Circle().fill(Color.orange)
                            .frame(width: 12, height: 12)
                            .offset(x: 1, y: -1)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var customToolbar: some View {
        HStack {
            Group {
                if vm.filter == .default { Text("Default Exercises").font(.title.bold()) }
                else if vm.filter == .favorites { Text("Favorite Exercises").font(.title.bold()) }
                else if vm.filter == .all { Text("Exercises").font(.title.bold()) }
                else if vm.filter == .workouts { Text("My Workouts").font(.title.bold()) }
                else if vm.filter == .plans { Text("Training Plans").font(.title.bold()) }
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)

            Spacer()
        }
    }

    // MARK: - Lists
    private var exerciseItemsList: some View {
        List {
            ForEach(Array(vm.items.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 0) {
                    ExerciseRowView(item: item)
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture { present(item: .detail(item)) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            swipeActions(for: item)
                        }
                        .padding(.vertical, 6)

                    if shouldShowAd(at: index) {
                        AdRowView()
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                            .transition(.opacity)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }

            if vm.hasMore {
                ProgressView()
                    .onAppear { vm.loadNextPage() }
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
            }

            Color.clear.frame(height: 150)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
        .ignoresSafeArea(.all)
    }

    private var trainingPlansSection: some View {
        VStack(spacing: 0) {
            // 1. Табовете (My Plans / Templates)
            WrappingSegmentedControl(
                selection: $trainingPlanVM.selectedScope,
                layoutMode: .wrap
            )
            .padding(.horizontal)
            
            // ✅ НОВО: Събтайтъл над целия списък, само ако сме в Templates
            if trainingPlanVM.selectedScope == .templates {
                HStack() {
                    Image(systemName: "sparkles")
                        .symbolRenderingMode(.hierarchical)
                    Text("AI-assisted fitness training plans")
                    Spacer()
                }
                .font(.title3)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                .padding(.top, 8)
                .padding(.bottom, 2)
                .padding(.horizontal, 12)
                .transition(.opacity)
            } else {
                // Добавяме малко разстояние, когато няма събтайтъл, за да не залепва списъкът
                Color.clear.frame(height: 10)
            }
            
            // 2. Съдържанието (Списък или Empty State)
            if trainingPlanVM.displayPlans.isEmpty {
                if globalSearchText.isEmpty {
                    let title = trainingPlanVM.selectedScope == .myPlans ? "No Training Plans" : "No Templates"
                    let desc = trainingPlanVM.selectedScope == .myPlans
                    ? "Create your first training plan manually or copy one from the Templates tab."
                    : "No template plans are available at the moment."
                    
                    VStack(spacing: 16) {
                        ContentUnavailableView(title, systemImage: "calendar.badge.clock", description: Text(desc))
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                        
                        if trainingPlanVM.selectedScope == .templates {
                            Button("Load Default Templates") {
                                Task {
                                    if let jsonURL = Bundle.main.url(forResource: "workouts", withExtension: "json"),
                                       let data = try? Data(contentsOf: jsonURL) {
                                        do {
                                            try await TrainingPlanImporter.shared.importTemplates(jsonData: data, context: modelContext)
                                            trainingPlanVM.fetchPlans()
                                        } catch {
                                            print("❌ Error importing templates: \(error)")
                                        }
                                    }
                                }
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassCardStyle(cornerRadius: 12)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        }
                    }
                    .padding(.top, 20) // Малко отстояние от табовете при empty state
                } else {
                    ContentUnavailableView {
                        Label("No Results for \"\(globalSearchText)\"", systemImage: "magnifyingglass")
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                    } description: {
                        Text("Check the spelling or try a new search.")
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                    .padding(.top, 20)
                }
            } else {
                List {
                    ForEach(Array(trainingPlanVM.displayPlans.enumerated()), id: \.element.id) { index, planWrapper in
                        VStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top) {
                                    Text(planWrapper.name)
                                        .font(.headline)
                                        .foregroundColor(effectManager.currentGlobalAccentColor)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    
                                    Spacer()
                                }
                                
                                HStack {
                                    Text("\(planWrapper.dayCount) day\(planWrapper.dayCount == 1 ? "" : "s")")
                                    Text("•")
                                    
                                    if !planWrapper.isTemplate, let date = planWrapper.creationDate {
                                        Text("Created: \(date.formatted(date: .abbreviated, time: .omitted))")
                                    } else {
                                        Text("Template")
                                    }
                                    
                                    if planWrapper.minAgeMonths > 0 {
                                        Text("•")
                                        Text("\(Int(planWrapper.minAgeMonths / 12))y+")
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .glassCardStyle(cornerRadius: 20)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if planWrapper.isTemplate {
                                    present(item: .detailTemplate(planWrapper))
                                } else if let realPlan = planWrapper.originalObject as? TrainingPlan {
                                    present(item: .detailPlan(realPlan))
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !planWrapper.isTemplate,
                                   let realPlan = planWrapper.originalObject as? TrainingPlan {
                                    
                                    Button(role: .destructive) {
                                        self.planToDeleteID = realPlan.id
                                        self.planToDeleteName = realPlan.name
                                        self.planToDeleteLinkedWorkoutCount = realPlan.days
                                            .flatMap { $0.workouts }
                                            .compactMap { $0.linkedWorkoutID }
                                            .count
                                        
                                        self.isShowingDeletePlanConfirmation = true
                                    } label: {
                                        Image(systemName: "trash.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                                    }
                                    .tint(.clear)
                                    
                                    Button {
                                        present(item: .editPlan(realPlan))
                                    } label: {
                                        Image(systemName: "pencil")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                                    }
                                    .tint(.clear)
                                }
                            }
                            .padding(.vertical, 6)
                            
                            if shouldShowAd(at: index) {
                                AdRowView()
                                    .padding(.top, 8)
                                    .padding(.bottom, 8)
                                    .transition(.opacity)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
                    
                    Color.clear.frame(height: 150)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
        }
    }

    @ViewBuilder
    private func swipeActions(for item: ExerciseItem) -> some View {
        if item.isUserAdded {
            Button(role: .destructive) {
                if #available(iOS 26.0, *) {
                    let usage = vm.trainingUsageCount(for: item)
                    if usage > 0 {
                        self.itemToDelete = item
                        self.itemUsageCount = usage
                        self.isShowingDeleteItemConfirmation = true
                    } else {
                        withAnimation { vm.delete(item) }
                    }
                } else {
                    self.itemToDelete = item
                    self.itemUsageCount = vm.trainingUsageCount(for: item)
                    self.isShowingDeleteItemConfirmation = true
                }
            } label: {
                Image(systemName: "trash.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
            }
            .tint(.clear)

            Button {
                if item.isWorkout {
                    present(item: .editWorkout(item))
                } else {
                    present(item: .edit(item))
                }
            } label: {
                Image(systemName: "pencil")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
            }
            .tint(.clear)
        }
    }

    // MARK: - Presented Content
    @ViewBuilder
    private func presentedItemView(for item: PresentedItem) -> some View {
        let onDismissItemView: (ExerciseItem?) -> Void = { savedItem in
            onDismissSearch()
            withAnimation(.easeInOut) {
                presentedItem = nil
                isAddButtonVisible = true
                self.navBarIsHiden = false
                if SIsSearching {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onActivateSearch()
                        globalSearchText = SglobalSearchText
                        SIsSearching = false
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onDismissSearch()
                        globalSearchText = ""
                    }
                }
            }
            if savedItem != nil {
                vm.resetAndLoad()
            }
        }

        let onWorkoutEditorDismiss: (ExerciseItem?) -> Void = { savedItem in
            onDismissSearch()
            withAnimation(.easeInOut) {
                presentedItem = nil
                isAddButtonVisible = true
                self.navBarIsHiden = false
                if SIsSearching {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onActivateSearch()
                        globalSearchText = SglobalSearchText
                        SIsSearching = false
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onDismissSearch()
                        globalSearchText = ""
                    }
                }
            }
            if savedItem != nil {
                vm.resetAndLoad()
            }
        }

        let onPlanEditorDismiss: (TrainingPlan?) -> Void = { _ in
            onDismissSearch()
            withAnimation(.easeInOut(duration: 0.3)) {
                self.presentedItem = nil
                self.isAddButtonVisible = true
                self.navBarIsHiden = false
                if SIsSearching {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onActivateSearch()
                        globalSearchText = SglobalSearchText
                        SIsSearching = false
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onDismissSearch()
                        globalSearchText = ""
                    }
                }
            }
            trainingPlanVM.fetchPlans()
        }

        let onSimpleDismiss: () -> Void = {
            onDismissSearch()
            withAnimation(.easeInOut(duration: 0.3)) {
                self.presentedItem = nil
                self.isAddButtonVisible = true
                self.navBarIsHiden = false
                if SIsSearching {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onActivateSearch()
                        globalSearchText = SglobalSearchText
                        SIsSearching = false
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onDismissSearch()
                        globalSearchText = ""
                    }
                }
            }
            trainingPlanVM.fetchPlans()
        }

        switch item {
        case .new:
            ExerciseItemEditorView(profile: profile, onDismiss: onDismissItemView)
        case .edit(let exerciseItem):
            ExerciseItemEditorView(item: .edit(exerciseItem), profile: profile, onDismiss: onDismissItemView)
        case .newWorkout:
            WorkoutEditorView(
                profile: profile,
                globalSearchText: $globalSearchText,
                isSearchFieldFocused: $isSearchFieldFocused,
                onDismissSearch: onDismissSearch,
                onDismiss: onWorkoutEditorDismiss
            )
        case .editWorkout(let workout):
            WorkoutEditorView(
                itemToEdit: workout,
                profile: profile,
                globalSearchText: $globalSearchText,
                isSearchFieldFocused: $isSearchFieldFocused,
                onDismissSearch: onDismissSearch,
                onDismiss: onWorkoutEditorDismiss
            )
        case .detail(let exerciseItem):
            ExerciseItemDetailView(
                item: exerciseItem,
                profile: self.profile,
                onDismiss: { onDismissItemView(nil) }
            )
        case .newPlan:
            TrainingPlanEditorView(
                profile: profile!,
                globalSearchText: $globalSearchText,
                isSearchFieldFocused: self.$isSearchFieldFocused,
                onDismiss: onPlanEditorDismiss,
                navBarIsHiden: $navBarIsHiden,
                onDismissSearch: onDismissSearch
            )
        case .editPlan(let plan):
            TrainingPlanEditorView(
                profile: profile!,
                planToEdit: plan,
                globalSearchText: $globalSearchText,
                isSearchFieldFocused: self.$isSearchFieldFocused,
                onDismiss: onPlanEditorDismiss,
                navBarIsHiden: $navBarIsHiden,
                onDismissSearch: onDismissSearch
            )
        case .detailPlan(let plan):
            TrainingPlanDetailView(
                plan: plan,
                profile: profile!,
                onDismiss: onSimpleDismiss,
                navBarIsHiden: $navBarIsHiden
            )
        case .detailTemplate(let planWrapper):
            TemplatePlanDetailView(
                planWrapper: planWrapper,
                profile: profile!,
                onDismiss: onSimpleDismiss,
                onGet: { selectedWorkoutName in
                    onSimpleDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation {
                            if let newPlan = trainingPlanVM.copyTemplateToMyPlans(
                                planWrapper,
                                targetWorkoutName: selectedWorkoutName
                            ) {
                                present(item: .editPlan(newPlan))
                            }
                        }
                    }
                }
            )
            .onAppear {
                navBarIsHiden = true
                isAddButtonVisible = false
            }
        }
    }

    // MARK: - Helpers
    private var headerTopPadding: CGFloat {
        -safeAreaInsets.top + 10
    }
    private func present(item: PresentedItem) {
        if isSearching {
            SIsSearching = isSearching
            SglobalSearchText = globalSearchText
            onDismissSearch()
        }

        withAnimation(.easeInOut) {
            presentedItem = item
            isAddButtonVisible = false

            switch item {
            case .newWorkout, .editWorkout, .newPlan, .editPlan:
                break
            default:
                navBarIsHiden = true
            }
            isProfilesDrawerVisible = false
        }
    }

    private func handleButtonTap() {
        switch vm.filter {
        case .all:
            present(item: .new)
        case .workouts:
            present(item: .newWorkout)
        case .plans:
            present(item: .newPlan)
        default:
            break
        }
    }

    private func saveButtonPosition() {
        UserDefaults.standard.set(buttonOffset.width, forKey: "\(buttonPositionKey)_width")
        UserDefaults.standard.set(buttonOffset.height, forKey: "\(buttonPositionKey)_height")
    }

    private func loadButtonPosition() {
        let width = UserDefaults.standard.double(forKey: "\(buttonPositionKey)_width")
        let height = UserDefaults.standard.double(forKey: "\(buttonPositionKey)_height")
        self.buttonOffset = CGSize(width: width, height: height)
    }

    private var emptyStateTitle: String {
        if !vm.searchText.isEmpty { return "No Results for \"\(vm.searchText)\"" }
        switch vm.filter {
        case .all: return "No Custom Exercises"
        case .favorites: return "No Favorites"
        case .workouts: return "No Workouts"
        case .default: return "No Items Available"
        case .plans: return "No Training Plans"
        }
    }

    private var emptyStateDescription: Text {
        let text: String
        if !vm.searchText.isEmpty { text = "Try a different search term or change the filter." }
        else {
            switch vm.filter {
            case .all: text = "Tap the '+' button to add your first exercise."
            case .favorites: text = "You can add exercises to your favorites by swiping left on them."
            case .workouts: text = "Tap the '+' button to create your first workout."
            case .default: text = "This is the list of built-in exercises."
            case .plans: text = "Tap the '+' button to create your first training plan."
            }
        }
        return Text(text)
    }

    // MARK: - Updated Floating Button Logic
    private func bottomPadding(for geometry: GeometryProxy) -> CGFloat {
        let size = geometry.size
        guard size.width > 0 else { return 75 }
        let aspectRatio = size.height / size.width
        return aspectRatio > 1.9 ? 75 : 95
    }

    private func trailingPadding(for geometry: GeometryProxy) -> CGFloat { 45 }

    private func dragGesture(geometry: GeometryProxy) -> some Gesture {
        let buttonSize: CGFloat = 60
        let radius = buttonSize / 2

        return DragGesture(minimumDistance: 0)
            .updating($gestureDragOffset) { value, state, _ in
                state = value.translation
            }
            .onChanged { value in
                let distance = max(abs(value.translation.width), abs(value.translation.height))

                if distance > 6 {
                    if !isDragging {
                        isDragging = true
                        isPressed = false
                    }
                } else {
                    isPressed = true
                }
            }
            .onEnded { value in
                let safeArea = geometry.safeAreaInsets
                let size = geometry.size

                let baseX = size.width  - trailingPadding(for: geometry) - radius
                let baseY = size.height - bottomPadding(for: geometry)   - radius

                let rawCenterX = baseX + buttonOffset.width  + value.translation.width
                let rawCenterY = baseY + buttonOffset.height + value.translation.height

                let minX = radius
                let maxX = size.width  - radius
                let minY = radius + safeArea.top
                let maxY = size.height - radius - safeArea.bottom - 80

                let clampedCenterX = min(max(rawCenterX, minX), maxX)
                let clampedCenterY = min(max(rawCenterY, minY), maxY)

                let newOffset = CGSize(
                    width:  clampedCenterX - baseX,
                    height: clampedCenterY - baseY
                )

                if isDragging {
                    buttonOffset = newOffset
                    saveButtonPosition()
                } else {
                    handleButtonTap()
                }

                isDragging = false
                isPressed = false
            }
    }

    private func addButton(geometry: GeometryProxy) -> some View {
        let buttonSize: CGFloat = 60
        let radius = buttonSize / 2
        let safeArea = geometry.safeAreaInsets
        let size = geometry.size

        let baseX = size.width  - trailingPadding(for: geometry) - radius
        let baseY = size.height - bottomPadding(for: geometry)   - radius

        let rawCenterX = baseX + buttonOffset.width  + gestureDragOffset.width
        let rawCenterY = baseY + buttonOffset.height + gestureDragOffset.height

        let minX = radius
        let maxX = size.width  - radius
        let minY = radius + safeArea.top
        let maxY = size.height - radius - safeArea.bottom

        let centerX = min(max(rawCenterX, minX), maxX)
        let centerY = min(max(rawCenterY, minY), maxY)

        let scale = isDragging ? 1.05 : (isPressed ? 0.92 : 1.0)

        return ZStack {
            Image(systemName: "plus")
                .font(.title3)
                .foregroundColor(effectManager.currentGlobalAccentColor)
        }
        .frame(width: buttonSize, height: buttonSize)
        .glassCardStyle(cornerRadius: radius)
        .scaleEffect(scale)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isPressed)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
        .contentShape(Circle())
        .position(x: centerX, y: centerY)
        .opacity(isAddButtonVisible ? 1 : 0)
        .disabled(!isAddButtonVisible)
        .gesture(dragGesture(geometry: geometry))
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Ad Logic
    private func shouldShowAd(at index: Int) -> Bool {
        if !AdsConfiguration.shouldShowAds { return false }
        if index < 2 { return false }
        let remainder = index % 7
        return remainder == 2 || remainder == 5
    }
}
