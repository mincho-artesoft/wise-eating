// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/Ayura/Ayura/Settings/SettingsView.swift ====
import SwiftUI
import PhotosUI
import SwiftData

struct SettingsView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var backgroundManager = BackgroundManager.shared
    @ObservedObject private var effectManager = EffectManager.shared
    @Query private var userSettings: [UserSettings]

    @State private var showingImagePicker = false
    @State private var inputImage: UIImage?
    @State private var imageToReplace: UIImage?
    
    @Binding var editorState: ThemeEditorState?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
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

                VStack(alignment: .leading, spacing: 10) {
                    Text("Personalization")
                        .font(.title2.bold())
                        .foregroundStyle(effectManager.currentGlobalAccentColor)

                    if let profileID = userSettings.first?.lastSelectedProfile?.id {
                        AyurvedaConstitutionEditorButton(
                            profileID: profileID,
                            pendingDraft: .constant(nil)
                        )
                    }
                }
                .padding(.horizontal)

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
    }
}
