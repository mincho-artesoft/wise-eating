import SwiftUI
import SwiftData
import PhotosUI

@MainActor
struct ExerciseItemEditorView: View {
    @State private var isAITapOnCooldown: Bool = false
    @ObservedObject private var aiManager = AIManager.shared
    @State private var hasUserMadeEdits: Bool = true
    @State private var runningGenerationJobID: UUID? = nil
    @State private var showAIGenerationToast = false
    @State private var toastTimer: Timer? = nil
    @State private var toastProgress: Double = 0.0
    @State private var alertMsg = ""
    @State private var isBannerAdLoaded: Bool = false
    @State private var pendingAIJobIDToDeleteOnSave: UUID? = nil
    @Query private var userSettingsArray: [UserSettings]   // 👈 ДОБАВИ ТОВА
    private var isAIButtonEnabledGlobally: Bool {
        userSettingsArray.first?.isAIButtonEnabled ?? true
    }
    // --- Photo source state (като при FoodItemReceptEditorView) ---
    private enum PhotoSourceTarget {
        case main
        case gallery
        case galleryReplace(index: Int)
    }
    
    @State private var showPhotoSourceDialog = false
    @State private var showCameraPicker = false
    @State private var showPhotoLibraryPicker = false
    @State private var currentPhotoTarget: PhotoSourceTarget? = nil
    
    // --- AI Floating Button: State ---
    @State private var isAIButtonVisible: Bool = true
    @State private var aiButtonOffset: CGSize = .zero
    @State private var aiIsDragging: Bool = false
    @GestureState private var aiGestureDragOffset: CGSize = .zero
    @State private var aiIsPressed: Bool = false
    private let aiButtonPositionKey = "floatingFoodAIButtonPosition"
    @State private var isGeneratingAIData = false
    
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var ctx
    
    private enum FocusableField: Hashable {
        case name, description, videoURL, metValue, duration, minAge
    }
    @FocusState private var focusedField: FocusableField?
    
    let onDismiss: (ExerciseItem?) -> Void
    
    private let exerciseToEdit: ExerciseItem?
    private let dubExercise: ExerciseItemCopy?
    private let isAIInit: Bool
    var profile: Profile?
    
    @State private var name: String
    @State private var description: String
    @State private var videoURL: String
    @State private var metValueString: String
    @State private var durationMinutesString: String
    @State private var minAgeMonthsTxt: String
    
    // Вече не ползваме PhotosPicker директно, но може да оставим това състояние ако искаш
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    
    @State private var selectedMuscleGroups: Set<MuscleGroup.ID>
    @State private var selectedSports: Set<Sport.ID>
    
    @State private var galleryData: [Data] = []
    @State private var newGalleryItems: [PhotosPickerItem] = []   // вече не се използва, но не пречи
    @State private var showReplacePicker = false
    @State private var replacementItem: PhotosPickerItem?
    @State private var replaceAtIndex: Int?
    @State private var tappedIndex: Int? = nil
    @State private var showPopover = false
    
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSaving = false
    
    fileprivate enum OpenMenu { case none, muscle, sport }
    @State private var openMenu: OpenMenu = .none
    
    init(
        item: ExerciseListView.PresentedItem? = nil,
        dubExercise: ExerciseItemCopy? = nil,
        isAIInit: Bool = false,
        profile: Profile?,
        onDismiss: @escaping (ExerciseItem?) -> Void
    ) {
        self.onDismiss = onDismiss
        self.profile = profile
        self.dubExercise = dubExercise
        self.isAIInit = isAIInit
        
        var initialExercise: ExerciseItem? = nil
        if let item = item {
            if case .edit(let exercise) = item {
                initialExercise = exercise
            }
        }
        self.exerciseToEdit = initialExercise
        
        if let copy = dubExercise {
            _name = State(initialValue: isAIInit ? copy.name : "Copy of \(copy.name)")
            _description = State(initialValue: copy.exerciseDescription ?? "")
            _videoURL = State(initialValue: copy.videoURL ?? "")
            _metValueString = State(initialValue: copy.metValue.map { String(format: "%.1f", $0) } ?? "")
            _photoData = State(initialValue: copy.photo)
            _selectedMuscleGroups = State(initialValue: Set(copy.muscleGroups.map(\.id)))
            _selectedSports = State(initialValue: Set(copy.sports?.map(\.id) ?? []))
            _galleryData = State(initialValue: copy.gallery ?? [])
            _durationMinutesString = State(initialValue: copy.durationMinutes.map { String($0) } ?? "")
            _minAgeMonthsTxt = State(initialValue: copy.minimalAgeMonths > 0 ? String(copy.minimalAgeMonths) : "")
        } else if let p = initialExercise {
            _name = State(initialValue: p.name)
            _description = State(initialValue: p.exerciseDescription ?? "")
            _videoURL = State(initialValue: p.videoURL ?? "")
            _metValueString = State(initialValue: p.metValue.map { String(format: "%.1f", $0) } ?? "")
            _photoData = State(initialValue: p.photo)
            _selectedMuscleGroups = State(initialValue: Set(p.muscleGroups.map(\.id)))
            _selectedSports = State(initialValue: Set(p.sports?.map(\.id) ?? []))
            _galleryData = State(initialValue: p.gallery?.map(\.data) ?? [])
            _durationMinutesString = State(initialValue: p.durationMinutes.map { String($0) } ?? "")
            _minAgeMonthsTxt = State(initialValue: p.minimalAgeMonths > 0 ? String(p.minimalAgeMonths) : "")
        } else {
            _name = State(initialValue: "")
            _description = State(initialValue: "")
            _videoURL = State(initialValue: "")
            _metValueString = State(initialValue: "")
            _photoData = State(initialValue: nil)
            _selectedMuscleGroups = State(initialValue: [])
            _selectedSports = State(initialValue: [])
            _galleryData = State(initialValue: [])
            _durationMinutesString = State(initialValue: "")
            _minAgeMonthsTxt = State(initialValue: "")
        }
    }
    
    
    // MARK: - Computed Properties
    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving
    }
    
    private var navigationTitle: String {
        exerciseToEdit == nil && dubExercise == nil ? "Add Exercise" : "Edit Exercise"
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                customToolbar
                mainForm
            }
            .alert("Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
                    .foregroundColor(effectManager.currentGlobalAccentColor)
            } message: {
                Text(alertMessage)
            }
            .presentationDetents([.medium, .large])
            .disabled(isSaving)
            .blur(radius: isSaving ? 1.5 : 0)
            
            if openMenu != .none {
                bottomSheetPanel
                    .transition(.move(edge: .bottom).animation(.easeInOut(duration: 0.3)))
                    .zIndex(1)
            }
            
            if isSaving {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                        .scaleEffect(1.5)
                    Text("Saving…")
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .font(.headline)
                }
                .padding(30)
                .glassCardStyle(cornerRadius: 20)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Saving")
                .zIndex(1000)
            }
        }
        .background(ThemeBackgroundView().ignoresSafeArea())
        .overlay {
            if showAIGenerationToast {
                aiGenerationToast
            }
            GeometryReader { geometry in
                Group {
                    if !isSaving &&
                        !showAlert &&
                        GlobalState.aiAvailability != .deviceNotEligible &&
                        openMenu == .none &&
                        isAIButtonEnabledGlobally{
                        AIButton(geometry: geometry)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiExerciseDetailJobCompleted)) { notification in
            guard !hasUserMadeEdits,
                  let userInfo = notification.userInfo,
                  let completedJobID = userInfo["jobID"] as? UUID,
                  completedJobID == self.runningGenerationJobID else {
                return
            }
            
            print("▶️ ExerciseItemEditorView: Received .aiExerciseDetailJobCompleted for job \(completedJobID). Populating data.")
            
            Task {
                if #available(iOS 26.0, *) {
                    await populateFromCompletedJob(jobID: completedJobID)
                }
            }
        }
        .onChange(of: name) { _, _ in hasUserMadeEdits = true }
        .onChange(of: description) { _, _ in hasUserMadeEdits = true }
        .onAppear { loadAIButtonPosition() }
        .sheet(isPresented: $showCameraPicker) {
            CameraPicker { image in
                handlePickedUIImage(image)
            }
            .presentationCornerRadius(20)
        }
        .sheet(isPresented: $showPhotoLibraryPicker) {
            PhotoLibraryPicker { image in
                handlePickedUIImage(image)
            }
            .presentationCornerRadius(20)
        }
        .confirmationDialog(
            "Select photo source",
            isPresented: $showPhotoSourceDialog
        ) {
            Button("Take Photo") {
                showPhotoSourceDialog = false
                showCameraPicker = true
            }
            Button("Choose from Library") {
                showPhotoSourceDialog = false
                showPhotoLibraryPicker = true
            }
            Button("Cancel", role: .cancel) {
                showPhotoSourceDialog = false
                currentPhotoTarget = nil
            }
        }
    }
    
    @ViewBuilder
    private var customToolbar: some View {
        HStack {
            Button("Cancel", action: { onDismiss(nil) })
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
            
            Spacer()
            Text(navigationTitle).font(.headline)
            Spacer()
            
            Button("Save", action: save)
                .disabled(isSaveDisabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
                .foregroundStyle(isSaveDisabled ? effectManager.currentGlobalAccentColor.opacity(0.4) : effectManager.currentGlobalAccentColor)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding([.horizontal, .top])
    }
    
    private var mainForm: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    generalSection
                    bannerAdSection
                        .frame(height: isBannerAdLoaded ? 120 : 0)
                    gallerySection
                    detailsSection
                    muscleGroupSection
                    sportsSection
                }
                .padding()
                Spacer(minLength: 150)
            }
            .onChange(of: focusedField) { _, newFocus in
                guard let fieldID = newFocus else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(fieldID, anchor: .top)
                    }
                }
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
            .background(Color.clear)
        }
    }
    
    
    // MARK: - Sections
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .padding(.bottom, -4)
            
            VStack(spacing: 16) {
                StyledLabeledPicker(label: "Exercise Name", isRequired: true) {
                    ConfigurableTextField(
                        title: "e.g., Barbell Squat",
                        value: $name,
                        type: .standard,
                        placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                        textAlignment: .leading,
                        focused: $focusedField,
                        fieldIdentifier: .name
                    )
                }
                .id(FocusableField.name)
                
                HStack(alignment: .center, spacing: 16) {
                    photoPicker
                    
                    VStack(alignment: .leading, spacing: 12) {
                        StyledLabeledPicker(label: "Default Duration (min)") {
                            ConfigurableTextField(
                                title: "e.g., 15",
                                value: $durationMinutesString,
                                type: .integer,
                                placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                                textAlignment: .leading,
                                focused: $focusedField,
                                fieldIdentifier: .duration
                            )
                            .font(.system(size: 16))
                        }
                        .id(FocusableField.duration)
                        
                        StyledLabeledPicker(label: "Description", height: 120) {
                            descriptionEditor
                                .focused($focusedField, equals: .description)
                        }
                        .id(FocusableField.description)
                    }
                }
                
                StyledLabeledPicker(label: "Minimum Age (months)") {
                    ConfigurableTextField(
                        title: "e.g. 6",
                        value: $minAgeMonthsTxt,
                        type: .integer,
                        placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                        textAlignment: .leading,
                        focused: $focusedField,
                        fieldIdentifier: .minAge
                    )
                    .font(.system(size: 16))
                }
                .id(FocusableField.minAge)
            }
            .padding()
            .glassCardStyle(cornerRadius: 20)
        }
    }
    
    private var descriptionEditor: some View {
        ZStack(alignment: .topLeading) {
            if description.isEmpty {
                Text("Description")
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6))
                    .font(.system(size: 16))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 8)
            }
            TextEditor(text: $description)
                .font(.system(size: 16))
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
        }
    }
    
    private var gallerySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gallery")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            
            VStack { galleryGrid }
                .padding()
                .glassCardStyle(cornerRadius: 20)
            // като при FoodItemReceptEditorView – PhotosPicker остава само за legacy replace по желание
                .photosPicker(isPresented: $showReplacePicker, selection: $replacementItem, matching: .images)
                .onChange(of: replacementItem, handleReplacementItemChange)
        }
    }
    
    private var galleryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
            ForEach(Array(galleryData.enumerated()), id: \.offset) { index, data in
                if let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable().scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipped()
                        .cornerRadius(8)
                        .onLongPressGesture {
                            tappedIndex = index
                            showPopover = true
                        }
                        .popover(
                            isPresented: popoverBinding(for: index),
                            attachmentAnchor: .rect(.bounds),
                            arrowEdge: .bottom
                        ) {
                            galleryPopoverContent(for: index, data: data)
                        }
                }
            }
            let color = effectManager.currentGlobalAccentColor
            Button {
                presentPhotoSource(for: .gallery)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(style: .init(lineWidth: 1, dash: [4]))
                        .frame(width: 80, height: 80)
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                }
                .foregroundColor(color)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func galleryPopoverContent(for index: Int, data: Data) -> some View {
        HStack(spacing: 0) {
            Button("Set as main") {
                photoData = data
                showPopover = false
                hasUserMadeEdits = true
            }
            .frame(maxWidth: .infinity)
            
            Divider()
            
            Button("Change") {
                showPopover = false
                presentPhotoSource(for: .galleryReplace(index: index))
            }
            .frame(maxWidth: .infinity)
            
            Divider()
            
            Button(role: .destructive) {
                galleryData.remove(at: index)
                showPopover = false
                hasUserMadeEdits = true
            } label: {
                Text("Remove")
            }
            .frame(maxWidth: .infinity)
        }
        .font(.footnote)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 300)
        .presentationCompactAdaptation(.none)
    }
    
    private var detailsSection: some View {
        VStack(spacing: 16) {
            StyledLabeledPicker(label: "Video URL (optional)") {
                ConfigurableTextField(
                    title: "e.g., https://youtube.com/...",
                    value: $videoURL,
                    type: .standard,
                    placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                    textAlignment: .leading,
                    focused: $focusedField,
                    fieldIdentifier: .videoURL
                )
            }
            .id(FocusableField.videoURL)
            
            StyledLabeledPicker(label: "MET Value (optional)") {
                ConfigurableTextField(
                    title: "e.g., 8.0",
                    value: $metValueString,
                    type: .decimal,
                    placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                    textAlignment: .leading,
                    focused: $focusedField,
                    fieldIdentifier: .metValue
                )
            }
            .id(FocusableField.metValue)
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
    }
    
    private var muscleGroupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Primary Muscles")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            MultiSelectButton(
                selection: $selectedMuscleGroups,
                items: MuscleGroup.allCases,
                label: { $0.rawValue },
                prompt: "Select muscle groups...",
                isExpanded: openMenu == .muscle
            )
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { openMenu = .muscle } }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .glassCardStyle(cornerRadius: 20)
        }
    }
    
    private var sportsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Related Sports")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            MultiSelectButton(
                selection: $selectedSports,
                items: Sport.allCases.sorted { $0.rawValue < $1.rawValue },
                label: { $0.rawValue },
                prompt: "Select related sports...",
                isExpanded: openMenu == .sport
            )
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { openMenu = .sport } }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .glassCardStyle(cornerRadius: 20)
        }
    }
    
    // MARK: - UI Components
    private var photoPicker: some View {
        let imageData = photoData
        let color = effectManager.currentGlobalAccentColor.opacity(0.6)
        
        return Button {
            presentPhotoSource(for: .main)
        } label: {
            Group {
                if let data = imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.15))
                        Image(systemName: "dumbbell.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .foregroundStyle(color)
                    }
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.leading, -4)
    }
    
    @ViewBuilder
    private var bottomSheetPanel: some View {
        ZStack(alignment: .bottom) {
            (effectManager.isLightRowTextColor ? Color.black.opacity(0.4) : Color.white.opacity(0.4))
                .ignoresSafeArea()
                .onTapGesture { withAnimation { openMenu = .none } }
            
            VStack(spacing: 8) {
                HStack {
                    Text("Select \(openMenu.title)")
                        .font(.headline)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                    Spacer()
                    Button("Done") { withAnimation { openMenu = .none } }
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassCardStyle(cornerRadius: 20)
                }
                .padding(.horizontal)
                .frame(height: 35)
                
                switch openMenu {
                case .muscle:
                    IconMultiSelectGridView(
                        items: MuscleGroup.allCases,
                        selection: $selectedMuscleGroups,
                        searchPrompt: "Search muscles...",
                        iconSize: CGSize(width: 48, height: 80),
                        useIconColor: true
                    )
                case .sport:
                    IconMultiSelectGridView(
                        items: Sport.allCases.sorted { $0.rawValue < $1.rawValue },
                        selection: $selectedSports,
                        searchPrompt: "Search sports...",
                        iconSize: CGSize(width: 48, height: 48),
                        useIconColor: false
                    )
                case .none:
                    EmptyView()
                }
            }
            .padding(.top)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, effectManager.isLightRowTextColor ? .dark : .light)
            }
            .cornerRadius(20, corners: [.topLeft, .topRight])
            .frame(maxHeight: UIScreen.main.bounds.height * 0.85)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .zIndex(1)
    }
    
    // MARK: - Logic
    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            alertMessage = "Exercise name cannot be empty."
            showAlert = true
            return
        }
        
        Task {
            isSaving = true
            await Task.yield()
            
            let itemToSave: ExerciseItem
            if let existing = exerciseToEdit {
                itemToSave = existing
            } else if let copy = dubExercise, let id = copy.originalID,
                      let existing = (try? ctx.fetch(FetchDescriptor<ExerciseItem>(predicate: #Predicate { $0.id == id })))?.first {
                itemToSave = existing
            } else {
                var desc = FetchDescriptor<ExerciseItem>(sortBy: [SortDescriptor(\.id, order: .reverse)])
                desc.fetchLimit = 1
                let maxID = (try? ctx.fetch(desc).first?.id) ?? 0
                itemToSave = ExerciseItem(id: maxID + 1, name: "", muscleGroups: [])
                ctx.insert(itemToSave)
            }
            
            itemToSave.name = trimmedName
            itemToSave.exerciseDescription = description.trimmingCharacters(in: .whitespaces).nilIfEmpty()
            itemToSave.videoURL = videoURL.trimmingCharacters(in: .whitespaces).nilIfEmpty()
            itemToSave.metValue = Double(metValueString)
            itemToSave.photo = photoData
            itemToSave.muscleGroups = selectedMuscleGroups.compactMap { MuscleGroup(rawValue: $0) }
            itemToSave.sports = selectedSports.compactMap { Sport(rawValue: $0) }
            itemToSave.durationMinutes = Int(durationMinutesString)
            itemToSave.minimalAgeMonths = Int(minAgeMonthsTxt) ?? 0
            
            if itemToSave.gallery == nil { itemToSave.gallery = [] }
            itemToSave.gallery?.removeAll { photo in !galleryData.contains(photo.data) }
            for data in galleryData {
                if !(itemToSave.gallery?.contains(where: { $0.data == data }) ?? false) {
                    let newPhoto = ExercisePhoto(data: data)
                    itemToSave.gallery?.append(newPhoto)
                }
            }
            
            do {
                try ctx.save()
                
                // ✅ Ако има завършен AI job, го трием чак сега – при успешно Save
                if let pendingID = pendingAIJobIDToDeleteOnSave,
                   let job = aiManager.jobs.first(where: { $0.id == pendingID }) {
                    await aiManager.deleteJob(job)
                    pendingAIJobIDToDeleteOnSave = nil
                }
                
                onDismiss(itemToSave)
            } catch {
                alertMessage = "Failed to save exercise: \(error.localizedDescription)"
                showAlert = true
                isSaving = false
            }
            
        }
    }
    
    // Оставяме тази функция, макар че вече не ползваме PhotosPicker за добавяне
    private func handleNewGalleryItems(_: [PhotosPickerItem], items: [PhotosPickerItem]) {
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run { galleryData.append(data) }
                }
            }
            await MainActor.run { newGalleryItems.removeAll() }
        }
    }
    
    private func handleReplacementItemChange(_: PhotosPickerItem?, item: PhotosPickerItem?) {
        guard let idx = replaceAtIndex, let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run { galleryData[idx] = data }
            }
            await MainActor.run {
                replacementItem = nil
                replaceAtIndex  = nil
            }
        }
    }
    
    private func popoverBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { showPopover && tappedIndex == index },
            set: { showPopover = $0 }
        )
    }
    
    // MARK: - AI & Ads Logic
    
    /// Тази функция стартира същинската работа на AI.
    /// Извиква се само когато потребителят е "платил" (с пари или с гледане на реклама).
    private func startAIGeneration() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMsg = "Please enter a name for the exercise first."
            showAlert = true
            return
        }
        
        focusedField = nil
        hasUserMadeEdits = false
        
        if #available(iOS 26.0, *) {
            triggerAIGenerationToast()
            
            if let newJob = aiManager.startExerciseDetailGeneration(
                for: self.profile,
                exerciseName: self.name,
                jobType: .exerciseDetail
            ) {
                self.runningGenerationJobID = newJob.id
            } else {
                alertMsg = "Could not start AI generation job."
                showAlert = true
                toastTimer?.invalidate()
                toastTimer = nil
                withAnimation { showAIGenerationToast = false }
            }
        } else {
            alertMsg = "AI data generation requires iOS 26 or newer."
            showAlert = true
        }
    }
    
    /// Основният handler на бутона.
    private func handleAITap() {
        if isAITapOnCooldown {
            return
        }
        
        // 1. Веднага активираме cooldown за да предотвратим спам/двойни кликове
        isAITapOnCooldown = true
        Task { @MainActor in
            // Тук можеш да смениш 1.5 на 1.0 или 2.0 според това, което искаш
            try? await Task.sleep(for: .seconds(1.5))
            isAITapOnCooldown = false
        }
        
        NotificationCenter.default.post(name: .snoozeAds, object: nil)
        
        // 1. Проверка за наличност на AI
        guard ensureAIAvailableOrShowMessage() else { return }
        
        // 2. Валидация на името (преди рекламите)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMsg = "Please enter a name for the exercise first."
            showAlert = true
            return
        }
        
        // 3. Проверка за АБОНАМЕНТ
        // Ако потребителят е на платен план (не е Base), пропускаме рекламите.
        if !AdsConfiguration.shouldShowAds {
            print("💎 Premium user: Skipping ad.")
            startAIGeneration()
            return
        }
        
        // 4. Логика за реклами (Base Plan)
        print("📺 Free user: Checking for ads...")
        // Опит 1: Видео с награда (Rewarded) - Приоритет
        if RewardedAdManager.shared.isReady {
            print("📺 Showing Rewarded Ad...")
            RewardedAdManager.shared.showIfAvailable { amount, type in
                // Този код се изпълнява САМО ако рекламата е изгледана докрай
                print("✅ Ad watched! Starting generation.")
                self.startAIGeneration()
            }
            // Ако потребителят затвори видеото преждевременно, startAIGeneration НЯМА да се извика.
        }
        // Опит 2: Цял екран (Interstitial) - Резервен вариант
        else if InterstitialAdManager.shared.isReady {
            print("⚠️ Rewarded not ready. Showing Interstitial fallback...")
            InterstitialAdManager.shared.showIfAvailable {
                // Извиква се, когато потребителят затвори рекламата (хиксчето)
                print("✅ Interstitial closed. Starting generation.")
                self.startAIGeneration()
            }
        }
        // Опит 3: Няма никакви реклами (Graceful degradation)
        else {
            print("⚠️ No ads available. Proceeding graciously.")
            // Пускаме услугата, за да не ядосваме потребителя, че няма реклами
            startAIGeneration()
            
            // Опитваме да заредим за следващия път
            Task {
                await RewardedAdManager.shared.loadAd()
                await InterstitialAdManager.shared.loadAd()
            }
        }
    }
    
    @available(iOS 26.0, *)
    private func populateFromCompletedJob(jobID: UUID) async {
        guard let job = (aiManager.jobs.first { $0.id == jobID }),
              let resultData = job.resultData else {
            alertMsg = "Could not find completed job data."
            showAlert = true
            runningGenerationJobID = nil
            return
        }
        
        do {
            let response = try JSONDecoder().decode(ExerciseItemDTO.self, from: resultData)
            let generator = AIExerciseDetailGenerator(container: ctx.container)
            let mapped = generator.mapResponseToState(dto: response)
            
            withAnimation(.easeInOut) {
                self.description         = mapped.description
                self.metValueString      = mapped.metValueString
                self.selectedMuscleGroups = mapped.selectedMuscleGroups
                self.selectedSports      = mapped.selectedSports
                self.minAgeMonthsTxt     = mapped.minAgeMonthsTxt
            }
            
            // ❗️Не трием job-а тук – само отбелязваме, че трябва да се изтрие при Save
            runningGenerationJobID = nil
            pendingAIJobIDToDeleteOnSave = jobID
            
        } catch {
            alertMessage = "Failed to process AI data: \(error.localizedDescription)"
            showAlert = true
            runningGenerationJobID = nil
            
            // При грешка все пак чистим job-а
            await aiManager.deleteJob(job)
        }
    }
    
    
    @ViewBuilder
    private var aiGenerationToast: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generating Details...").fontWeight(.bold)
                    Text("AI is fetching data for your exercise.").font(.caption)
                    ProgressView(value: min(max(toastProgress, 0.0), 1.0), total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                        .animation(.linear, value: toastProgress)
                }
                Spacer()
                Button("OK") {
                    toastTimer?.invalidate()
                    toastTimer = nil
                    withAnimation { showAIGenerationToast = false }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor).padding()
            .glassCardStyle(cornerRadius: 20).padding()
            .transition(.move(edge: .top).combined(with: .opacity))
            
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.keyboard)
    }
    
    private func triggerAIGenerationToast() {
        toastTimer?.invalidate()
        toastProgress = 0.0
        withAnimation { showAIGenerationToast = true }
        
        let totalDuration = 5.0
        let updateInterval = 0.1
        let progressIncrement = updateInterval / totalDuration
        
        toastTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { timer in
            DispatchQueue.main.async {
                self.toastProgress += progressIncrement
                if self.toastProgress >= 1.0 {
                    timer.invalidate()
                    self.toastTimer = nil
                    withAnimation { self.showAIGenerationToast = false }
                }
            }
        }
    }
    
    // --- AI Floating Button: Helpers ---
    private func aiBottomPadding(for geometry: GeometryProxy) -> CGFloat {
        let size = geometry.size
        guard size.width > 0 else { return 75 }
        let aspect = size.height / size.width
        return aspect > 1.9 ? 75 : 95
    }
    private func aiTrailingPadding(for geometry: GeometryProxy) -> CGFloat { 45 }
    
    private func aiDragGesture(geometry: GeometryProxy) -> some Gesture {
        let buttonSize: CGFloat = 60
        let radius = buttonSize / 2
        
        return DragGesture(minimumDistance: 0)
            .updating($aiGestureDragOffset) { value, state, _ in
                // Жив превод по време на drag – без анимация
                state = value.translation
            }
            .onChanged { value in
                let distance = max(abs(value.translation.width), abs(value.translation.height))
                
                if distance > 6 {
                    // Вече влачим – махаме "pressed" и маркираме "dragging"
                    if !aiIsDragging {
                        aiIsDragging = true
                        aiIsPressed = false
                    }
                } else {
                    // Малко мърдане = натиснат бутон
                    aiIsPressed = true
                }
            }
            .onEnded { value in
                let safeArea = geometry.safeAreaInsets
                let size = geometry.size
                
                // Базова позиция (дясно-долу) спрямо размера + твоите padding-и
                let baseX = size.width  - aiTrailingPadding(for: geometry) - radius
                let baseY = size.height - aiBottomPadding(for: geometry)   - radius
                
                // Центърът, ако приложим текущия offset + преместеното
                let rawCenterX = baseX + aiButtonOffset.width  + value.translation.width
                let rawCenterY = baseY + aiButtonOffset.height + value.translation.height
                
                // Ограничаваме центъра ВЪТРЕ в екрана
                let minX = radius
                let maxX = size.width  - radius
                let minY = radius + safeArea.top
                let maxY = size.height - radius - safeArea.bottom - 80
                
                let clampedCenterX = min(max(rawCenterX, minX), maxX)
                let clampedCenterY = min(max(rawCenterY, minY), maxY)
                
                // Новият offset е просто разлика спрямо базовата позиция
                let newOffset = CGSize(
                    width:  clampedCenterX - baseX,
                    height: clampedCenterY - baseY
                )
                
                if aiIsDragging {
                    aiButtonOffset = newOffset
                    saveAIButtonPosition()
                } else {
                    // Тап (без реален drag)
                    handleAITap()
                }
                
                aiIsDragging = false
                aiIsPressed = false
            }
    }
    
    private func saveAIButtonPosition() {
        let d = UserDefaults.standard
        d.set(aiButtonOffset.width,  forKey: "\(aiButtonPositionKey)_width")
        d.set(aiButtonOffset.height, forKey: "\(aiButtonPositionKey)_height")
    }
    
    private func loadAIButtonPosition() {
        let d = UserDefaults.standard
        let w = d.double(forKey: "\(aiButtonPositionKey)_width")
        let h = d.double(forKey: "\(aiButtonPositionKey)_height")
        self.aiButtonOffset = CGSize(width: w, height: h)
    }
    
    @ViewBuilder
    private func AIButton(geometry: GeometryProxy) -> some View {
        let buttonSize: CGFloat = 60
        let radius = buttonSize / 2
        let safeArea = geometry.safeAreaInsets
        let size = geometry.size
        
        // Базова позиция (дясно-долу) с твоите "маржове"
        let baseX = size.width  - aiTrailingPadding(for: geometry) - radius
        let baseY = size.height - aiBottomPadding(for: geometry)   - radius
        
        // Център със запазения offset + текущия drag
        let rawCenterX = baseX + aiButtonOffset.width  + aiGestureDragOffset.width
        let rawCenterY = baseY + aiButtonOffset.height + aiGestureDragOffset.height
        
        // Ограничаваме центъра ВЪТРЕ в екрана (и safe area)
        let minX = radius
        let maxX = size.width  - radius
        let minY = radius + safeArea.top
        let maxY = size.height - radius - safeArea.bottom
        
        let centerX = min(max(rawCenterX, minX), maxX)
        let centerY = min(max(rawCenterY, minY), maxY)
        
        let scale = aiIsDragging ? 1.05 : (aiIsPressed ? 0.92 : 1.0)
        
        ZStack {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundColor(effectManager.currentGlobalAccentColor)
        }
        .frame(width: buttonSize, height: buttonSize)
        .glassCardStyle(cornerRadius: buttonSize / 2 + 2)
        .scaleEffect(scale)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: aiIsPressed)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: aiIsDragging)
        .contentShape(Circle())                     // само кръгчето е кликаемо
        .position(x: centerX, y: centerY)           // абсолютна позиция, вече clamp-ната
        .opacity(isAIButtonVisible ? (isAITapOnCooldown ? 0.5 : 1.0) : 0)
        .disabled(!isAIButtonVisible || isAITapOnCooldown)
        .gesture(aiDragGesture(geometry: geometry)) // жестът е върху 60x60, не върху цял екран
        .transition(.scale.combined(with: .opacity))
    }
    
    private func ensureAIAvailableOrShowMessage() -> Bool {
        switch GlobalState.aiAvailability {
        case .available:
            return true
        case .deviceNotEligible:
            alertMessage = "This device doesn’t support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            alertMessage = "Apple Intelligence is turned off. Enable it in Settings to use AI exercise generation."
        case .modelNotReady:
            alertMessage = "The model is downloading or preparing. Please try again in a bit."
        case .unavailableUnsupportedOS:
            alertMessage = "Apple Intelligence requires iOS 26 or newer. Update your OS to use this feature."
        case .unavailableOther:
            alertMessage = "Apple Intelligence is currently unavailable for an unknown reason."
        }
        showAlert = true
        return false
    }
    
    // MARK: - Photo source helpers (същите като при FoodItemReceptEditorView)
    private func presentPhotoSource(for target: PhotoSourceTarget) {
        currentPhotoTarget = target
        showPhotoSourceDialog = true
    }
    
    private func handlePickedUIImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        
        switch currentPhotoTarget {
        case .main:
            photoData = data
            
        case .gallery:
            galleryData.append(data)
            
        case .galleryReplace(let index):
            if galleryData.indices.contains(index) {
                galleryData[index] = data
            }
            
        case .none:
            break
        }
        
        hasUserMadeEdits = true
        currentPhotoTarget = nil
    }
    
    @ViewBuilder
    private var bannerAdSection: some View {
        // Показваме банер само за free (Base) потребители
        if AdsConfiguration.shouldShowAds {
            BannerAdView(adsBool: $isBannerAdLoaded, bucket: .large)
                .frame(height: 120)
                .opacity(isBannerAdLoaded ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: isBannerAdLoaded)
                .padding(.horizontal)
        }
    }
}

fileprivate extension ExerciseItemEditorView.OpenMenu {
    var title: String {
        switch self {
        case .muscle: "Muscle Groups"
        case .sport:  "Sports"
        case .none:   ""
        }
    }
}
