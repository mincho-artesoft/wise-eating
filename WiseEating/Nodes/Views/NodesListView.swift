// MARK: - NodesListView.swift
import SwiftUI
import SwiftData

fileprivate enum NodesFilterType: String, CaseIterable, Identifiable {
    case all = "All"
    case meal = "Meals"
    case workouts = "Workouts"
    var id: String { self.rawValue }
}

fileprivate enum PresentedNode: Identifiable, Equatable {
    case newNode
    case editNode(Node)

    var id: String {
        switch self {
        case .newNode:
            return "newNode"
        case .editNode(let node):
            return "editNode-\(node.id)"
        }
    }

    static func == (lhs: PresentedNode, rhs: PresentedNode) -> Bool {
        lhs.id == rhs.id
    }
}

struct NodesListView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    let profile: Profile
    @State private var currentFilter: NodesFilterType = .all
    
    @Query var allNodes: [Node]
    
    @State private var presentedNode: PresentedNode? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var nodeToDelete: Node? = nil
    @State private var isShowingDeleteConfirmation = false

    // MARK: - Draggable Button State
    @State private var buttonOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @GestureState private var gestureDragOffset: CGSize = .zero
    @State private var isPressed: Bool = false
    private let buttonPositionKey = "nodesListFloatingButtonPosition"

    // Toolbar States
    @State private var currentTimeString: String = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        return df
    }()
    @State private var hasUnreadNotifications: Bool = false

    @Environment(\.safeAreaInsets) private var safeAreaInsets
    private var headerTopPadding: CGFloat { -safeAreaInsets.top + 10 }

    // --- НАЧАЛО НА ПРОМЯНАТА (1/8): Състояния за филтъра по дата ---
    @State private var filterStartDate: Date? = nil
    @State private var filterEndDate: Date? = nil
    
    private enum SheetContent: Identifiable {
        case dateRange
        var id: Self { self }
    }
    @State private var presentedSheet: SheetContent? = nil
    // --- КРАЙ НА ПРОМЯНАТА (1/8) ---
    
    // +++ НАЧАЛО НА ПРОМЯНАТА (1/2) +++
    private var datesWithNodes: Set<Date> {
        // Взимаме само датите без часове, за да улесним сравнението
        Set(allNodes
            .filter { $0.profile?.id == profile.id }
            .map { Calendar.current.startOfDay(for: $0.date) }
        )
    }
    // +++ КРАЙ НА ПРОМЯНАТА (1/2) +++
    
    private var filteredNodes: [Node] {
        let profileNodes = allNodes.filter { $0.profile?.id == profile.id }.sorted { $0.date > $1.date }
        switch currentFilter {
        case .all:
            return profileNodes
        case .meal:
            return profileNodes.filter { !($0.linkedFoods?.isEmpty ?? true) }
        case .workouts:
            return profileNodes.filter { !($0.linkedExercises?.isEmpty ?? true) }
        }
    }

    private var dateFilteredNodes: [Node] {
        guard let startDate = filterStartDate, let endDate = filterEndDate else {
            return filteredNodes
        }
        let inclusiveEndDate = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        return filteredNodes.filter { $0.date >= startDate && $0.date < inclusiveEndDate }
    }

    // --- НАЧАЛО НА ПРОМЯНАТА (2/8): Актуализация на форматирането на датата ---
    private var dateFilterDisplay: String {
        guard let start = filterStartDate, let end = filterEndDate else { return "" }
        let formatter = DateFormatter()
        // Функцията вече проверява и използва GlobalState.dateFormat
        if !GlobalState.dateFormat.isEmpty {
            formatter.dateFormat = GlobalState.dateFormat
        } else {
            formatter.dateStyle = .short // Резервен вариант
        }
        
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return formatter.string(from: start)
        }
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
    // --- КРАЙ НА ПРОМЯНАТА (2/8) ---
    
    private var emptyStateTitle: String {
        if filterStartDate != nil {
            return "No Nodes in Selected Range"
        }
        switch currentFilter {
        case .all: return "No Nodes Available"
        case .meal: return "No Meal Nodes"
        case .workouts: return "No Workout Nodes"
        }
    }

    private var emptyStateDescription: Text {
        let text: String
        if filterStartDate != nil {
            text = "Try adjusting the date range or clearing the filter to see all your nodes."
        } else {
            switch currentFilter {
            case .all: text = "Tap the '+' button to add your first node."
            case .meal: text = "Tap the '+' button to add your first meal node."
            case .workouts: text = "Tap the '+' button to add your first workout node."
            }
        }
        return Text(text)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ZStack(alignment: .bottomTrailing) {
                    ThemeBackgroundView().ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        userToolbar(for: profile)
                            .padding(.trailing, 30)
                            .padding(.leading, 20)
                            .padding(.bottom, 8)
                        
                        UpdatePlanBanner()
                        
                        customToolbar
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        
                        WrappingSegmentedControl(selection: $currentFilter, layoutMode: .wrap)
                            .padding(.bottom, 15)

                        if !dateFilteredNodes.isEmpty {
                            List {
                                ForEach(dateFilteredNodes) { node in
                                    NodeRowView(node: node)
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets())
                                        .padding(.horizontal)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            present(node: .editNode(node))
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                if #available(iOS 26.0, *) {
                                                    deleteNode(node)
                                                } else {
                                                    self.nodeToDelete = node
                                                    self.isShowingDeleteConfirmation = true
                                                }
                                            } label: {
                                                Image(systemName: "trash.fill")
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
                        } else {
                            Spacer()
                            ContentUnavailableView {
                                Label(emptyStateTitle, systemImage: "doc.text.magnifyingglass")
                            } description: {
                                emptyStateDescription
                            }
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                            Spacer()
                        }
                    }
                    
                    addButton(geometry: geometry)
                }
                .padding(.top, headerTopPadding)
                .onAppear(perform: loadButtonPosition)
                .onReceive(timer) { _ in self.currentTimeString = Self.timeFormatter.string(from: Date()) }
                .task { await checkForUnreadNotifications() }
                .opacity(presentedNode == nil ? 1 : 0)
                .allowsHitTesting(presentedNode == nil)
                
                if let presented = presentedNode {
                    presentedNodeView(for: presented)
                        .transition(.move(edge: .trailing))
                        .zIndex(10)
                }
            }
            .alert("Delete Node", isPresented: $isShowingDeleteConfirmation, presenting: nodeToDelete) { node in
                Button("Delete", role: .destructive) {
                    deleteNode(node)
                }
                Button("Cancel", role: .cancel) {
                    nodeToDelete = nil
                }
            } message: { node in
                Text("Are you sure you want to delete the node titled \"\(node.textContent ?? "Untitled")\"? This action cannot be undone.")
            }
            // --- НАЧАЛО НА ПРОМЯНАТА (5/8): Добавяме .overlay за панела ---
            .overlay {
                if presentedSheet != nil {
                    bottomSheetPanel
                }
            }
            // --- КРАЙ НА ПРОМЯНАТА (5/8) ---
        }
    }

    // --- НАЧАЛО НА ПРОМЯНАТА (6/8): Нов ViewBuilder за панела ---
    @ViewBuilder
    private var bottomSheetPanel: some View {
        ZStack(alignment: .bottom) {
            if effectManager.isLightRowTextColor {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { withAnimation { presentedSheet = nil } }
            } else {
                Color.white.opacity(0.4).ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { withAnimation { presentedSheet = nil } }
            }
           
            VStack(spacing: 8) {
                switch presentedSheet {
                case .dateRange:
                    dateRangePickerSheetContent
                case .none:
                    EmptyView()
                }
            }
            .padding(.top)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme,effectManager.isLightRowTextColor ? .dark : .light) // 👈 Това принуждава материала да е тъмен
            }
            .cornerRadius(20, corners: [.topLeft, .topRight])
            .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .zIndex(1)
        .transition(.move(edge: .bottom))
    }

    private var dateRangePickerSheetContent: some View {
        VStack {
            HStack {
                Button("Clear") {
                    withAnimation {
                        filterStartDate = nil
                        filterEndDate = nil
                        presentedSheet = nil
                    }
                }
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)

                Spacer()
                Text("Select Date Range")
                    .font(.headline)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                Spacer()
                Button("Done") { withAnimation { presentedSheet = nil } }
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 20)
            }
            .padding(.horizontal)
            .frame(height: 35)

            // +++ НАЧАЛО НА ПРОМЯНАТА (2/2) +++
            CalendarDateRangePickerWrapper(
                startDate: self.filterStartDate,
                endDate: self.filterEndDate,
                datesWithEvents: datesWithNodes,
                onComplete: { start, end in
                    self.filterStartDate = start
                    self.filterEndDate = end
                    withAnimation { self.presentedSheet = nil }
                }
            )
            // +++ КРАЙ НА ПРОМЯНАТА (2/2) +++
        }
    }
    
    @ViewBuilder
    private func presentedNodeView(for presented: PresentedNode) -> some View {
        let onDismiss: () -> Void = {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.presentedNode = nil
            }
        }

        switch presented {
        case .newNode:
            NodeEditorView(profile: profile, node: nil, onDismiss: onDismiss)
        case .editNode(let node):
            NodeEditorView(profile: profile, node: node, onDismiss: onDismiss)
        }
    }
    
    private func present(node: PresentedNode) {
        withAnimation(.easeInOut(duration: 0.3)) {
            presentedNode = node
        }
    }
    
    @ViewBuilder
    private func userToolbar(for profile: Profile) -> some View {
        HStack {
            Text(currentTimeString)
                .font(.system(size: 16)).fontWeight(.medium)
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .onAppear { self.currentTimeString = Self.timeFormatter.string(from: Date()) }
            Spacer()
            Button(action: { NotificationCenter.default.post(name: .openProfilesDrawer, object: nil) }) {
                ZStack(alignment: .topTrailing) {
                    if let photoData = profile.photoData, let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(Circle())
                    } else {
                        ZStack {
                            Circle().fill(effectManager.currentGlobalAccentColor.opacity(0.2))
                            if let firstLetter = profile.name.first {
                                Text(String(firstLetter)).font(.headline).foregroundColor(effectManager.currentGlobalAccentColor)
                            }
                        }.frame(width: 40, height: 40)
                    }
                    if hasUnreadNotifications {
                        Circle().fill(Color.orange).frame(width: 12, height: 12).offset(x: 1, y: -1)
                    }
                }
            }.buttonStyle(.plain)
        }
    }
    
    // --- НАЧАЛО НА ПРОМЯНАТА (3/8): Показване на избрания период в toolbar ---
    private var customToolbar: some View {
        HStack {
            Text("Notes").font(.title.bold()).foregroundColor(effectManager.currentGlobalAccentColor)
            Spacer()
            
            // Ако има избран период, го показваме
            if filterStartDate != nil {
                Text(dateFilterDisplay)
                    .font(.system(size: 20))
                    .lineLimit(1)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                    .transition(.opacity.combined(with: .scale))
                    .onTapGesture {
                        withAnimation(.easeInOut) {
                            presentedSheet = .dateRange
                        }
                    }
            }
            
            Button(action: {
                withAnimation(.easeInOut) {
                    presentedSheet = .dateRange
                }
            }) {
                Image(systemName: "calendar")
                    .font(.system(size: 24))
                    .foregroundColor(effectManager.currentGlobalAccentColor)
            }
            .padding(.trailing, 10)
        }
    }
    // --- КРАЙ НА ПРОМЯНАТА (3/8) ---
    
    private func addButton(geometry: GeometryProxy) -> some View {
        let currentOffset = CGSize(width: buttonOffset.width + gestureDragOffset.width, height: buttonOffset.height + gestureDragOffset.height)
        let scale = isDragging ? 1.15 : (isPressed ? 0.9 : 1.0)
        return ZStack {
            Image(systemName: "document.badge.plus")
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
        .padding(.bottom, 95)
        .offset(currentOffset)
        .gesture(dragGesture(geometry: geometry))
        .transition(.scale.combined(with: .opacity))
    }
    
    private func dragGesture(geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($gestureDragOffset) { value, state, _ in
                state = value.translation
                DispatchQueue.main.async { self.isPressed = true }
            }
            .onChanged { value in if abs(value.translation.width) > 10 || abs(value.translation.height) > 10 { self.isDragging = true } }
            .onEnded { value in
                self.isPressed = false
                if isDragging {
                    var newOffset = self.buttonOffset
                    newOffset.width += value.translation.width
                    newOffset.height += value.translation.height
                    let buttonRadius: CGFloat = 40
                    let viewSize = geometry.size
                    let safeArea = geometry.safeAreaInsets
                    let minY = -viewSize.height + buttonRadius + safeArea.top + 150
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
    
    private func handleButtonTap() {
        present(node: .newNode)
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

    private func checkForUnreadNotifications() async {
        let unread = await NotificationManager.shared.getUnreadNotifications()
        self.hasUnreadNotifications = !unread.isEmpty
    }
    
    private func deleteNode(_ node: Node) {
        withAnimation {
            modelContext.delete(node)
            try? modelContext.save()
        }
        nodeToDelete = nil
    }
}
