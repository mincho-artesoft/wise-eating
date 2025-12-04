import SwiftUI
import SwiftData
import AVKit

struct ExerciseItemDetailView: View {
    // MARK: - Managers and Environment
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext

    // MARK: - Input
    let item: ExerciseItem
    let profile: Profile?
    let onDismiss: () -> Void

    // MARK: - UI State
    @State private var selectedImageData: Data?
    @State private var mainUIImage: UIImage?
    @State private var showThumbnails = false
    @State private var isShowingLinkedNodes = false
    // +++ НАЧАЛО НА ПРОМЯНАТА (1/5) +++
    @State private var nodeToEdit: Node? = nil
    // +++ КРАЙ НА ПРОМЯНАТА (1/5) +++

    // MARK: - Computed Properties for data display
    private var galleryImages: [Data] {
        var images = [Data]()
        if let mainPhotoData = item.photo {
            images.append(mainPhotoData)
        }
        if let galleryItems = item.gallery {
            let mainPhotoAsNSData = item.photo as NSData?
            for galleryPhoto in galleryItems {
                if mainPhotoAsNSData == nil || galleryPhoto.data as NSData != mainPhotoAsNSData {
                    images.append(galleryPhoto.data)
                }
            }
        }
        return images
    }

    private var caloriesBurnedPer30Min: Double? {
        guard let profile = profile, let met = item.metValue else { return nil }
        let cpm = (met * 3.5 * profile.weight) / 200.0 // Calories per minute
        return cpm * 30 // Calories for 30 minutes
    }
    
    private var videoURL: URL? {
        guard let urlString = item.videoURL, let url = URL(string: urlString) else {
            return nil
        }
        if urlString.contains("youtube.com") || urlString.contains("youtu.be") || urlString.contains("vimeo.com") {
             return url
        }
        return nil
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                customToolbar
                    .padding(.horizontal)

                ScrollView(showsIndicators: false) {
                    if item.photo != nil {
                        mainImageSection
                            .padding(.horizontal)
                            .padding(.top, 5)
                        
                        thumbnailGallery
                    } else {
                        noImageInfoSection
                            .padding(.top, 5)
                            .padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 24) {
                        textInfoSection
                        workoutExercisesSection
                        muscleGroupSection
                        sportsSection
                        videoSection
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
            .opacity(isShowingLinkedNodes ? 0 : 1)
            .allowsHitTesting(!isShowingLinkedNodes)

            if isShowingLinkedNodes {
                linkedNodesView
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    .zIndex(5)
            }
            
            // +++ НАЧАЛО НА ПРОМЯНАТА (2/5) +++
            if let node = nodeToEdit, let profile = profile {
                NodeEditorView(profile: profile, node: node) {
                    withAnimation {
                        nodeToEdit = nil
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                .zIndex(10)
            }
            // +++ КРАЙ НА ПРОМЯНАТА (2/5) +++
        }
        .onAppear {
            if selectedImageData == nil { selectedImageData = item.photo }
            if !showThumbnails {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.showThumbnails = true
                }
            }
        }
        .task(id: selectedImageData) {
            await loadImage(data: selectedImageData)
        }
    }

    private var customToolbar: some View {
        HStack {
            HStack{
                Button { onDismiss() } label: { HStack { Text("Cancel") } }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
            
            Spacer()
            
            Text("Exercise Details").font(.headline)
            
            Spacer()

            if (item.nodes?.count ?? 0) > 0 {
                Button {
                    withAnimation { isShowingLinkedNodes = true }
                } label: {
                    Image(systemName: "list.clipboard")
                        .font(.title2)
                        .frame(width: 28, height: 28)
                }
            }

            Button {
                withAnimation { item.isFavorite.toggle() }
                try? modelContext.save()
                NotificationCenter.default.post(name: .exerciseFavoriteToggled, object: item)
            } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(.yellow)
                    .font(.title2)
                    .frame(width: 28, height: 28)
            }
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
    }

    @ViewBuilder
   private var mainImageSection: some View {
       if let image = mainUIImage {
           Color.clear
               .frame(maxWidth: .infinity)
               .frame(height: 250)
               .overlay(
                   Image(uiImage: image)
                       .resizable()
                       .aspectRatio(contentMode: .fill)
               )
               .clipped()
               .glassCardStyle(cornerRadius: 20)
               .transition(.opacity.animation(.easeInOut))
       } else {
           Rectangle()
               .fill(effectManager.currentGlobalAccentColor.opacity(0.8))
               .overlay(ProgressView()
               .opacity(selectedImageData != nil ? 1 : 0))
               .frame(height: 250)
               .clipped()
               .glassCardStyle(cornerRadius: 20)
       }
   }
    
    private func loadImage(data: Data?) async {
        guard let data = data, !data.isEmpty else {
            if !Task.isCancelled { await MainActor.run { mainUIImage = nil } }
            return
        }
        let image = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
        if !Task.isCancelled { await MainActor.run { mainUIImage = image } }
    }
    
    @ViewBuilder
    private var thumbnailGallery: some View {
        if showThumbnails {
            let allImages = galleryImages
            if allImages.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(allImages, id: \.self) { imageData in
                            AsyncImageView(imageData: imageData, contentMode: .fill) {
                                Rectangle()
                                    .fill(effectManager.currentGlobalAccentColor.opacity(0.8))
                                    .overlay(ProgressView())
                            }
                            .glassCardStyle(cornerRadius: 20)
                            .frame(width: 70, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(selectedImageData == imageData ? effectManager.currentGlobalAccentColor : Color.clear, lineWidth: 2))
                                    .onTapGesture { if selectedImageData != imageData { selectedImageData = imageData } }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .transition(.opacity.animation(.easeInOut))
            }
        } else {
            Color.clear.frame(height: 94)
        }
    }
    
    @ViewBuilder
    private var noImageInfoSection: some View {
        ZStack {
            let color = effectManager.isLightRowTextColor ? Color.black.opacity(0.8) : Color.white.opacity(0.8)
            Color(color).opacity(0)
            
            HStack(spacing: 24) {
                if let met = item.metValue {
                    VStack(spacing: 4) {
                        Label { Text("Intensity") } icon: {
                            Image(systemName: "bolt.heart.fill").foregroundColor(.red)
                        }
                        .font(.subheadline)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                        Text("\(met.clean) METs").font(.title.weight(.bold))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                }
                if let calories = caloriesBurnedPer30Min {
                    VStack(spacing: 4) {
                        Label { Text("Burn (30 min)") } icon: {
                            Image(systemName: "flame.fill").foregroundColor(.orange)
                        }
                        .font(.subheadline)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                        Text("\(calories, specifier: "%.0f") kcal")
                            .font(.title.weight(.bold))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                }
                if item.minimalAgeMonths > 0 {
                    VStack(spacing: 4) {
                        Label { Text("Min. Age") } icon: {
                            Image(systemName: "person.badge.clock.fill")
                                .symbolRenderingMode(.hierarchical)
                        }
                        .font(.subheadline)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                        
                        Text("\(item.minimalAgeMonths) mo")
                            .font(.title.weight(.bold))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                }
            }
        }
        .glassCardStyle(cornerRadius: 20)
        .frame(height: 250)
    }

    private var textInfoSection: some View {
        VStack(spacing: 16) {
            Text(item.name)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, item.photo != nil ? 0 : 16)
                .foregroundStyle(effectManager.currentGlobalAccentColor)

            if let desc = item.exerciseDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                Text(desc)
                    .font(.callout)
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if item.photo != nil {
                summaryInfoRow
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryInfoRow: some View {
        HStack(spacing: 24) {
            if let met = item.metValue {
                VStack(spacing: 2) {
                    Label { Text("Intensity") } icon: {
                        Image(systemName: "bolt.heart.fill").foregroundColor(.red)
                    }
                    .font(.caption)
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    Text("\(met.clean) METs")
                        .font(.headline)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                }
            }
            if let calories = caloriesBurnedPer30Min {
                VStack(spacing: 2) {
                    Label { Text("Burn (30 min)") } icon: { Image(systemName: "flame.fill").foregroundColor(.orange) }
                    .font(.caption)
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    Text("\(calories, specifier: "%.0f") kcal")
                        .font(.headline)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                }
            }
            if item.minimalAgeMonths > 0 {
                VStack(spacing: 2) {
                    Label { Text("Min. Age") } icon: {
                        Image(systemName: "person.badge.clock.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .font(.caption)
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))

                    Text("\(item.minimalAgeMonths) mo")
                        .font(.headline)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                }
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 10)
    }

    @ViewBuilder
    private var workoutExercisesSection: some View {
        if item.isWorkout, let exercises = item.exercises, !exercises.isEmpty {
            SectionView(title: "Exercises in this Workout") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(exercises) { link in
                        if let exercise = link.exercise {
                            HStack {
                                Text(exercise.name)
                                    .foregroundColor(effectManager.currentGlobalAccentColor)
                                Spacer()
                                Text("\(link.durationMinutes.clean) min")
                                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                            }
                            .font(.subheadline)
                            if link.id != exercises.last?.id {
                                Divider().background(effectManager.currentGlobalAccentColor.opacity(0.2))
                            }
                        }
                    }
                }
            }
            .padding()
            .glassCardStyle(cornerRadius: 20)
        }
    }

    private var muscleGroupSection: some View {
        let items = item.muscleGroups.map { StaticTag(label: $0.rawValue, color: .purple) }
        return tagSectionView(title: "Primary Muscles", tags: items)
    }

    private var sportsSection: some View {
        let items = (item.sports ?? []).map { StaticTag(label: $0.rawValue, color: .blue) }
        return tagSectionView(title: "Related Sports", tags: items)
    }

    @ViewBuilder
    private var videoSection: some View {
        if let url = videoURL {
            SectionView(title: "Video Tutorial") {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
            }
            .padding()
            .glassCardStyle(cornerRadius: 20)
        }
    }

    // +++ НАЧАЛО НА ПРОМЯНАТА (4/5) +++
    @ViewBuilder
    private var linkedNodesView: some View {
        let linkedNodes = item.nodes?.sorted { $0.date > $1.date } ?? []

        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    withAnimation { isShowingLinkedNodes = false }
                }) {
                    HStack {
                        Image(systemName: "chevron.backward")
                        Text("Back")
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)

                Spacer()
                Text("Linked Notes")
                    .font(.headline)
                Spacer()
                
                Button("Back") {}.hidden()
                    .padding(.horizontal, 10).padding(.vertical, 5)
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .padding()

            if linkedNodes.isEmpty {
                ContentUnavailableView(
                    "No Linked Notes",
                    systemImage: "note.text.badge.plus",
                    description: Text("You haven't linked this exercise to any notes yet.")
                )
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                .frame(maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(linkedNodes) { node in
                            // +++ НАЧАЛО НА ПРОМЯНАТА (5/5) +++
                            Button(action: {
                                withAnimation(.easeInOut) {
                                    nodeToEdit = node
                                }
                            }) {
                                NodeRowView(node: node)
                            }
                            .buttonStyle(.plain)
                            // +++ КРАЙ НА ПРОМЯНАТА (5/5) +++
                        }
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
    }
    // +++ КРАЙ НА ПРОМЯНАТА (4/5) +++
    
    @ViewBuilder
    private func tagSectionView(title: String, tags: [StaticTag]) -> some View {
        if !tags.isEmpty {
            SectionView(title: title) {
                CustomFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(tags) { tag in
                        StaticTagView(label: tag.label, color: tag.color)
                    }
                }
            }
            .padding()
            .glassCardStyle(cornerRadius: 20)
        }
    }
}

fileprivate struct AsyncImageView<Placeholder: View>: View {
    let imageData: Data?
    let contentMode: ContentMode
    let placeholder: Placeholder
    @State private var uiImage: UIImage?
    init(imageData: Data?, contentMode: ContentMode = .fill, @ViewBuilder placeholder: () -> Placeholder) {
        self.imageData = imageData
        self.contentMode = contentMode
        self.placeholder = placeholder()
    }
    var body: some View {
        Group {
            if let image = uiImage { Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode) } else { placeholder }
        }
        .task(id: imageData) { await loadImage() }
    }
    private func loadImage() async {
        guard let data = imageData, !data.isEmpty else { if !Task.isCancelled { await MainActor.run { uiImage = nil } }; return }
        let image = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
        if !Task.isCancelled { await MainActor.run { uiImage = image } }
    }
}

fileprivate struct SectionView<Content: View>: View {
    @ObservedObject private var effectManager = EffectManager.shared
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            content()
        }
    }
}

fileprivate struct NutrientChipView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let name: String, value: Double, unit: String; var color: Color?
    private func autoScale(_ value: Double, unit: String) -> (Double, String) {
        var v = value, u = unit.lowercased()
        while v >= 1000 {
            switch u {
            case "ng": v /= 1000; u = "µg"; case "µg", "mcg": v /= 1000; u = "mg"; case "mg": v /= 1000; u = "g"; default: return (v, unit)
            }
        }
        return (v, u == unit.lowercased() ? unit : u)
    }
    var body: some View {
        let (scaled, finalUnit) = autoScale(value, unit: unit)
        HStack(spacing: 4) {
            Text(name)
                .font(.caption)
                .foregroundColor(effectManager.currentGlobalAccentColor)
            Text("\(scaled.clean) \(finalUnit)")
                .font(.caption.weight(.semibold))
                .foregroundColor(effectManager.currentGlobalAccentColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color?.opacity(0.4) ?? effectManager.currentGlobalAccentColor.opacity(0.2))
        .clipShape(Capsule())
    }
}

fileprivate struct StaticTag: Identifiable { var id = UUID(); let label: String, color: Color }

fileprivate struct StaticTagView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    let label: String, color: Color
    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.2))
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .clipShape(Capsule())
    }
}

