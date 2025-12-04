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
    @State private var isShowingDeletePlanConfirmation = false
    @State private var planToDelete: TrainingPlan? = nil
    
    // MARK: - Time / Notifications
    @State private var currentTimeString: String = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let tFmt = DateFormatter.shortTime
    @State private var hasUnreadNotifications: Bool = false
    
    // --- НАЧАЛО НА ПРОМЯНАТА ---
    // Преместваме енумерацията тук, за да е ясно, че е за този изглед.
    // Вече включва "Training Plans".
    typealias Filter = ExerciseListVM.Filter
    // --- КРАЙ НА ПРОМЯНАТА ---
    
    // MARK: - Init
    init(
        vm: ExerciseListVM, // <-- Added
        profile: Profile?,
        globalSearchText: Binding<String>,
        isSearching: Binding<Bool>,
        navBarIsHiden: Binding<Bool>,
        isProfilesDrawerVisible: Binding<Bool>,
        onActivateSearch: @escaping () -> Void,
        onDismissSearch: @escaping () -> Void,
        isSearchFieldFocused: FocusState<Bool>.Binding
    ) {
        self.vm = vm // <-- Added
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
                
                if !isSearching && (vm.filter != .default && vm.filter != .favorites) && isAddButtonVisible && !navBarIsHiden {
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
        // --- НАЧАЛО НА КОРЕКЦИЯТА ---
        .onChange(of: vm.filter) { newFilter in
            if newFilter == .plans {
                trainingPlanVM.fetchPlans()
            }
        }
        // --- КРАЙ НА КОРЕКЦИЯТА ---
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
            .alert("Delete Exercise", isPresented: $isShowingDeleteItemConfirmation) {
                Button("Delete", role: .destructive) {
                    if let item = itemToDelete {
                        withAnimation {
                            if itemUsageCount > 0 {
                                // Ако упражнението се използва – първо махаме връзките
                                vm.deleteDetachingFromWorkoutsAndPlans(item)
                            } else {
                                // Нормално изтриване
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
            .alert("Delete Training Plan", isPresented: $isShowingDeletePlanConfirmation) {
                Button("Delete Plan Only", role: .destructive) {
                    if let plan = planToDelete {
                        trainingPlanVM.delete(plan: plan, alsoDeleteLinkedWorkouts: false)
                    }
                    planToDelete = nil
                }
                
                Button("Delete Plan & Workouts", role: .destructive) {
                    if let plan = planToDelete {
                        trainingPlanVM.delete(plan: plan, alsoDeleteLinkedWorkouts: true)
                    }
                    planToDelete = nil
                }
                
                Button("Cancel", role: .cancel) {
                    planToDelete = nil
                }
            } message: {
                if let plan = planToDelete {
                    let linkedWorkoutCount = plan.days
                        .flatMap { $0.workouts }
                        .compactMap { $0.linkedWorkoutID }
                        .count
                    
                    if linkedWorkoutCount > 0 {
                        Text("""
            This training plan has \(linkedWorkoutCount) linked workout(s).

            • "Delete Plan Only" will remove the plan but keep the workouts in your exercise library.
            • "Delete Plan & Workouts" will delete the plan and those linked workouts as well.

            What would you like to do?
            """)
                    } else {
                        Text("Are you sure you want to delete the training plan '\(plan.name)'? This action cannot be undone.")
                    }
                } else {
                    Text("Are you sure you want to delete this training plan?")
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
                            .environment(\.colorScheme,effectManager.isLightRowTextColor ? .dark : .light) // 👈 Това принуждава материала да е тъмен
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
            ForEach(vm.items, id: \.id) { item in
                ExerciseRowView(item: item)
                    .id(item.id)
                    .contentShape(Rectangle())
                    .onTapGesture { present(item: .detail(item)) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        swipeActions(for: item)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            
            if vm.hasMore {
                ProgressView()
                    .onAppear { vm.loadNextPage() }
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
            }
            
            Color.clear
                .frame(height: 150)
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
    
    @ViewBuilder
    private var trainingPlansSection: some View {
        if trainingPlanVM.plans.isEmpty && globalSearchText.isEmpty {
            ContentUnavailableView("No Training Plans", systemImage: "calendar.badge.plus", description: Text("Create your first training plan by tapping the '+' button below."))
                .foregroundStyle(effectManager.currentGlobalAccentColor)
        } else if trainingPlanVM.plans.isEmpty {
            ContentUnavailableView.search(text: globalSearchText)
        } else {
            List {
                ForEach(trainingPlanVM.plans) { plan in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(plan.name)
                            .font(.headline)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        
                        HStack {
                            Text("\(plan.days.count) day\(plan.days.count == 1 ? "" : "s")")
                            Text("•")
                            Text("Created: \(plan.creationDate.formatted(date: .abbreviated, time: .omitted))")
                        }
                        .font(.caption)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .glassCardStyle(cornerRadius: 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        present(item: .detailPlan(plan))
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions {
                        Button(role: .destructive) {
                            self.planToDelete = plan
                            self.isShowingDeletePlanConfirmation = true
                        } label: {
                            Image(systemName: "trash.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                        }
                        .tint(.clear)

                        Button {
                            present(item: .editPlan(plan))
                        } label: {
                            Image(systemName: "pencil")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                        }
                        .tint(.clear)
                    }

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
    
    @ViewBuilder
    private func swipeActions(for item: ExerciseItem) -> some View {
        if item.isUserAdded {
            // DELETE
            Button(role: .destructive) {
                if #available(iOS 26.0, *) {
                    let usage = vm.trainingUsageCount(for: item)
                    if usage > 0 {
                        self.itemToDelete = item
                        self.itemUsageCount = usage
                        self.isShowingDeleteItemConfirmation = true
                    } else {
                        withAnimation {
                            vm.delete(item)
                        }
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
            
            // EDIT
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

    
    // MARK: - Deletion Logic
    private func delete(exercise: ExerciseItem) {
        withAnimation {
            vm.delete(exercise)
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
                if SIsSearching{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onActivateSearch()
                        globalSearchText = SglobalSearchText
                        SIsSearching = false
                    }
                }else{
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
        
        // --- НАЧАЛО НА КОРЕКЦИЯТА (1/2) ---
        // Променяме сигнатурата на onWorkoutEditorDismiss, за да приема (ExerciseItem?)
        let onWorkoutEditorDismiss: (ExerciseItem?) -> Void = { savedItem in
            onDismissSearch()
            withAnimation(.easeInOut) {
                presentedItem = nil
                isAddButtonVisible = true
                self.navBarIsHiden = false
                if SIsSearching{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onActivateSearch()
                        globalSearchText = SglobalSearchText
                        SIsSearching = false
                    }
                }else{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onDismissSearch()
                        globalSearchText = ""
                    }
                }
            }
            // Презареждаме само ако има запазен елемент
            if savedItem != nil {
                vm.resetAndLoad()
            }
        }
        // --- КРАЙ НА КОРЕКЦИЯТА (1/2) ---
        
        let onPlanEditorDismiss: (TrainingPlan?) -> Void = { savedPlan in
            onDismissSearch()
            withAnimation(.easeInOut(duration: 0.3)) {
                self.presentedItem = nil
                self.isAddButtonVisible = true
                self.navBarIsHiden = false
                if SIsSearching{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onActivateSearch()
                        globalSearchText = SglobalSearchText
                        SIsSearching = false
                    }
                }else{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onDismissSearch()
                        globalSearchText = ""
                    }
                }
            }
            trainingPlanVM.fetchPlans()
        }
        
        let onPlanDetailDismiss: () -> Void = {
            onDismissSearch()
            withAnimation(.easeInOut(duration: 0.3)) {
                self.presentedItem = nil
                self.isAddButtonVisible = true
                self.navBarIsHiden = false
                if SIsSearching{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onActivateSearch()
                        globalSearchText = SglobalSearchText
                        SIsSearching = false
                    }
                }else{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onDismissSearch()
                        globalSearchText = ""
                    }
                }
            }
            trainingPlanVM.fetchPlans()
        }
        
        switch item {
            // --- НАЧАЛО НА КОРЕКЦИЯТА (2/2) ---
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
            // --- КРАЙ НА КОРЕКЦИЯТА (2/2) ---
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
                onDismiss: onPlanEditorDismiss
            )
        case .editPlan(let plan):
            TrainingPlanEditorView(
                profile: profile!,
                planToEdit: plan,
                globalSearchText: $globalSearchText,
                isSearchFieldFocused: self.$isSearchFieldFocused,
                onDismiss: onPlanEditorDismiss
            )
        case .detailPlan(let plan):
            TrainingPlanDetailView(plan: plan, profile: profile!, onDismiss: onPlanDetailDismiss, navBarIsHiden: $navBarIsHiden)
        }
    }
    
    // MARK: - Helpers
    private var headerTopPadding: CGFloat { -safeAreaInsets.top + 10 }
    
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
    
    // MARK: - Floating Add Button
    private func dragGesture(geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($gestureDragOffset) { value, state, _ in
                state = value.translation
                DispatchQueue.main.async { self.isPressed = true }
            }
            .onChanged { value in
                if abs(value.translation.width) > 10 || abs(value.translation.height) > 10 {
                    self.isDragging = true
                }
            }
            .onEnded { value in
                self.isPressed = false
                if isDragging {
                    var newOffset = self.buttonOffset
                    newOffset.width += value.translation.width
                    newOffset.height += value.translation.height
                    
                    let buttonRadius: CGFloat = 40
                    let viewSize = geometry.size
                    let safeArea = geometry.safeAreaInsets
                    let minY = -viewSize.height + buttonRadius + safeArea.top
                    let maxY = -25 + safeArea.bottom
                    newOffset.height = min(maxY, max(minY, newOffset.height))
                    
                    self.buttonOffset = newOffset
                    self.saveButtonPosition()
                } else {
                    self.handleButtonTap()
                }
                self.isDragging = false
            }
    }
    
    private func addButton(geometry: GeometryProxy) -> some View {
        let currentOffset = CGSize(
            width: buttonOffset.width + gestureDragOffset.width,
            height: buttonOffset.height + gestureDragOffset.height
        )
        let scale = isDragging ? 1.15 : (isPressed ? 0.9 : 1.0)
        
        return ZStack {
            Image(systemName: "plus")
                .font(.title3)
                .foregroundColor(effectManager.currentGlobalAccentColor)
        }
        .frame(width: 60, height: 60)
        .glassCardStyle(cornerRadius: 32)
        .scaleEffect(scale)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .contentShape(Rectangle())
        .padding(.trailing, 45)
        .padding(.bottom, (geometry.size.height / geometry.size.width) > 1.9 ? 75 : 95)
        .offset(currentOffset)
        .gesture(dragGesture(geometry: geometry))
        .transition(.scale.combined(with: .opacity))
    }
}
