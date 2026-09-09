import SwiftUI
import PhotosUI

struct ThemeEditorView: View {
    // MARK: - Dependencies
    @ObservedObject private var effectManager = EffectManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    // НОВО: Добавяме достъп до BackgroundManager, за да можем да премахнем фоновото изображение
    @ObservedObject private var backgroundManager = BackgroundManager.shared

    // MARK: - View Properties
    let onDismiss: () -> Void
    @Binding var navBarIsHiden: Bool
    @Binding var menuState: MenuState
    
    // MARK: - State Properties
    let themeToEdit: Theme?
    
    @State private var themeId: UUID
    @State private var themeName: String = ""
    @State private var colors: [Color] = []
    @State private var startPoint: UnitPoint
    @State private var endPoint: UnitPoint
    
    // MARK: - Computed Properties
    private var navigationTitle: String {
        themeToEdit == nil ? "New Theme" : "Edit Theme"
    }

    private var isSaveDisabled: Bool {
        themeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || colors.count < 2
    }
    
    // MARK: - Init
    init(
        themeToEdit: Theme?,
        navBarIsHiden: Binding<Bool>,
        menuState: Binding<MenuState>,
        onDismiss: @escaping () -> Void
    ) {
        self.themeToEdit = themeToEdit
        self._navBarIsHiden = navBarIsHiden
        self._menuState = menuState
        self.onDismiss = onDismiss
        
        if let theme = themeToEdit {
            _themeId = State(initialValue: theme.id)
            _themeName = State(initialValue: theme.name)
            _colors = State(initialValue: theme.colors.map { $0.color })
            _startPoint = State(initialValue: theme.startPoint)
            _endPoint = State(initialValue: theme.endPoint)
        } else {
            _themeId = State(initialValue: UUID())
            _themeName = State(initialValue: "")
            _colors = State(initialValue: [.blue, .green])
            _startPoint = State(initialValue: .topLeading)
            _endPoint = State(initialValue: .bottomTrailing)
        }
    }

    // MARK: - Body
    var body: some View {
        NavigationStack() {
            GeometryReader { rootGeo in
                ZStack {
                    ThemeBackgroundView()
                        .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        customToolbar
                            .padding(.horizontal)
                        
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 24) {
                                themeNameSection
                                gradientPreviewSection // Преглед на живо
                                colorsSection
                                gradientDirectionSection
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
                    }
                }
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            navBarIsHiden = true
            menuState = .collapsed
        }
    }
    
    // MARK: - Custom Toolbar
    @ViewBuilder
    private var customToolbar: some View {
        HStack {
            HStack {
                Button("Cancel", action: onDismiss)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
            
            Spacer()

            Text(navigationTitle)
                .font(.headline)
                .foregroundColor(effectManager.currentGlobalAccentColor)

            Spacer()
            
            HStack {
                Button(themeToEdit == nil ? "Save" : "Update", action: saveTheme)
                    .disabled(isSaveDisabled)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
            .foregroundStyle(isSaveDisabled ? effectManager.currentGlobalAccentColor.opacity(0.4) : effectManager.currentGlobalAccentColor)
        }
        .padding(.top, 10)
        .foregroundColor(effectManager.currentGlobalAccentColor)
    }

    // MARK: - View Sections
    
    @ViewBuilder
    private var gradientPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Preview")
                .font(.headline)
                .foregroundColor(effectManager.currentGlobalAccentColor)

            RoundedRectangle(cornerRadius: 15)
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: startPoint,
                        endPoint: endPoint
                    )
                )
                .aspectRatio(1, contentMode: .fit) // Прави го квадратен
                .glassCardStyle(cornerRadius: 15)
        }
    }
    
    @ViewBuilder
    private var themeNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Theme Name")
                .font(.headline)
                .foregroundColor(effectManager.currentGlobalAccentColor)

            HStack{
                TextField("My Awesome Theme", text: $themeName, prompt: Text("e.g., Sunset Bliss").foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6)))
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                    .disableAutocorrection(true)                
            }
            .padding()
            .glassCardStyle(cornerRadius: 20)
        }
      
    }

    @ViewBuilder
    private var colorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colors")
                .font(.headline)
                .foregroundColor(effectManager.currentGlobalAccentColor)
            
            VStack(spacing: 0) {
                ForEach(colors.indices, id: \.self) { index in
                    HStack {
                        Text("Color \(index + 1)")
                            .foregroundColor(effectManager.currentGlobalAccentColor)

                        Spacer()

                        ColorPicker("", selection: $colors[index], supportsOpacity: true)
                            .labelsHidden()
   
                        
                        if colors.count > 2 {
                            Button {
                                deleteColor(at: IndexSet(integer: index))
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(effectManager.currentGlobalAccentColor, effectManager.isLightRowTextColor ? .black.opacity(0.2) : .white.opacity(0.2))
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 8)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    
                    if index < colors.count - 1 {
                        Divider().background(effectManager.currentGlobalAccentColor.opacity(0.4)).padding(.horizontal)
                    }
                }
                Button(action: addColor) {
                    Label("Add New Color", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading) // Подравняване вляво
                }
                .padding()
                .foregroundStyle(effectManager.currentGlobalAccentColor)

            }
            .glassCardStyle(cornerRadius: 20)
        }
    }
    
    @ViewBuilder
    private var gradientDirectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gradient Direction")
                .font(.headline)
                .foregroundColor(effectManager.currentGlobalAccentColor)

            VStack(spacing: 0) {
                // --- Start Point Picker wrapped in a Menu ---
                Menu {
                    Picker("Start Point", selection: $startPoint) {
                        Text("Top Leading").tag(UnitPoint.topLeading)
                        Text("Top").tag(UnitPoint.top)
                        Text("Top Trailing").tag(UnitPoint.topTrailing)
                        Text("Leading").tag(UnitPoint.leading)
                        Text("Center").tag(UnitPoint.center)
                    }
                } label: {
                    HStack {
                        Text("Start Point")
                        Spacer()
                        Text(name(for: startPoint))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                Divider().background(effectManager.currentGlobalAccentColor.opacity(0.4)).padding(.horizontal)

                // --- End Point Picker wrapped in a Menu ---
                Menu {
                    Picker("End Point", selection: $endPoint) {
                        Text("Bottom Trailing").tag(UnitPoint.bottomTrailing)
                        Text("Bottom").tag(UnitPoint.bottom)
                        Text("Bottom Leading").tag(UnitPoint.bottomLeading)
                        Text("Trailing").tag(UnitPoint.trailing)
                        Text("Center").tag(UnitPoint.center)
                    }
                } label: {
                    HStack {
                        Text("End Point")
                        Spacer()
                        Text(name(for: endPoint))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .foregroundColor(effectManager.currentGlobalAccentColor) // Apply color to the custom labels
            .glassCardStyle(cornerRadius: 20)
        }
    }
    
    // MARK: - Helper Methods
    private func name(for point: UnitPoint) -> String {
        switch point {
        case .topLeading: return "Top Leading"
        case .top: return "Top"
        case .topTrailing: return "Top Trailing"
        case .leading: return "Leading"
        case .center: return "Center"
        case .bottomLeading: return "Bottom Leading"
        case .bottom: return "Bottom"
        case .bottomTrailing: return "Bottom Trailing"
        case .trailing: return "Trailing"
        default: return "Custom"
        }
    }
    
    // MARK: - Private Methods
    private func addColor() {
        withAnimation { colors.append(.orange) }
    }

    private func deleteColor(at offsets: IndexSet) {
        colors.remove(atOffsets: offsets)
    }
    
    private func saveTheme() {
        let updatedTheme = Theme(
            id: themeId,
            name: themeName,
            colors: colors,
            startPoint: startPoint,
            endPoint: endPoint
        )
        
        // 1. Запазваме темата в UserDefaults
        themeManager.saveCustomTheme(updatedTheme)
        
        // --- КОРЕКЦИЯТА Е ТУК ---
        // 2. Премахваме фоновото изображение, за да сме сигурни, че темата ще се вижда.
        // Това имитира поведението при избиране на тема от списъка.
        backgroundManager.removeBackgroundImage()

        // 3. Задаваме новозапазената тема като текуща.
        themeManager.setTheme(to: updatedTheme)
        
        // 4. Затваряме екрана за редакция
        onDismiss()
    }
}
