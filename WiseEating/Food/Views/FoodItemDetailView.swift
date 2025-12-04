import SwiftUI
import SwiftData
import UIKit

struct FoodItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var effectManager = EffectManager.shared

    let food: FoodItem
    let profile: Profile?
    let onDismiss: () -> Void
    
    @State private var selectedImageData: Data?
    @State private var mainUIImage: UIImage?
    @State private var showThumbnails = false

    @State private var isShowingLinkedNodes = false
    @State private var nodeToEdit: Node? = nil

    private var galleryImages: [Data] {
        var images = [Data]()
        if let mainPhotoData = food.photo {
            images.append(mainPhotoData)
        }
        if let galleryItems = food.gallery {
            let mainPhotoAsNSData = food.photo as NSData?
            for item in galleryItems {
                if mainPhotoAsNSData == nil || item.data as NSData != mainPhotoAsNSData {
                    images.append(item.data)
                }
            }
        }
        return images
    }
    
    private var descriptionOrIngredientsText: String? {
        if let desc = food.itemDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
            return desc
        }
        if (food.isRecipe || food.isMenu), let ingredients = food.ingredients, !ingredients.isEmpty {
            let topIngredients = ingredients.prefix(3)
            let ingredientsStrings = topIngredients.map { link -> String in
                let name = link.food?.name ?? "Ingredient"
                let grams = link.grams
                let formattedGrams = grams.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0fg", grams)
                    : String(format: "%.1fg", grams)
                return "\(name) \(formattedGrams)"
            }
            var text = "Contains: " + ingredientsStrings.joined(separator: ", ")
            if ingredients.count > 3 { text += "..." }
            return text
        }
        return nil
    }
    
    private var displayWeightG: Double? {
        if food.isRecipe || food.isMenu { return food.totalWeightG }
        if let explicitWeight = food.other?.weightG?.value, explicitWeight > 0 { return explicitWeight }
        let p = food.macronutrients?.protein?.value ?? 0
        let f = food.macronutrients?.fat?.value ?? 0
        let c = food.macronutrients?.carbohydrates?.value ?? 0
        let calculated = p + f + c
        return calculated > 0 ? calculated : nil
    }

    private var displayKcal: Double? {
        if let explicitEnergy = food.totalEnergyKcal?.value, explicitEnergy > 0 { return explicitEnergy }
        let proteinKcal = (food.macronutrients?.protein?.value ?? 0) * 4
        let fatKcal = (food.macronutrients?.fat?.value ?? 0) * 9
        let carbsKcal = (food.macronutrients?.carbohydrates?.value ?? 0) * 4
        let calculatedKcal = proteinKcal + fatKcal + carbsKcal
        return calculatedKcal > 0 ? calculatedKcal : nil
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                customToolbar
                    .padding(.horizontal)

                ScrollView(showsIndicators: false) {
                    if mainUIImage != nil {
                        mainImageSection
                            .padding(.horizontal)
                            .padding(.top, 5)
                        
                        if galleryImages.count > 1 {
                            thumbnailGallery
                        }
                    } else {
                        noImageInfoSection
                            .padding(.top, 5)
                            .padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 24) {
                        textInfoSection
                        categorySection
                        dietsSection
                        macrosSection
                        phSection
                        ingredientsSection
                        vitaminsSection
                        mineralsSection
                        lipidsSection
                        aminoAcidsSection
                        carbDetailsSection
                        sterolsSection
                        otherCompoundsSection
                        allergensSection
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
            
            if let node = nodeToEdit, let profile = profile {
                NodeEditorView(profile: profile, node: node) {
                    withAnimation {
                        nodeToEdit = nil
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                .zIndex(10)
            }
        }
        .onAppear {
            if let diets = food.diets, !diets.isEmpty {
                let dietNames = diets.map { $0.name }.joined(separator: ", ")
                print("🥗 Food Item '\(food.name)' Diets: [\(dietNames)]")
            } else {
                print("🥗 Food Item '\(food.name)' has no associated diets.")
            }

            if selectedImageData == nil { selectedImageData = food.photo }
            if !showThumbnails {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.showThumbnails = true
                }
            }
            if self.mainUIImage == nil {
                Task { await loadImage(data: self.selectedImageData) }
            }
        }
        .task(id: selectedImageData) {
            await loadImage(data: selectedImageData)
        }
    }
    
    private func loadImage(data: Data?) async {
        if self.mainUIImage == nil, let prefill = food.foodImage(variant: "1024") {
            await MainActor.run { self.mainUIImage = prefill }
        }

        if let data = data, !data.isEmpty {
            let decoded: UIImage? = await Task.detached(priority: .high) {
                UIImage(data: data)
            }.value
            if let img = decoded {
                if !Task.isCancelled { await MainActor.run { self.mainUIImage = img } }
                return
            }
        }
        if self.mainUIImage == nil {
            let fallback = food.foodImage(variant: "1024")
            if !Task.isCancelled { await MainActor.run { self.mainUIImage = fallback } }
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
            
            Text("Food Details").font(.headline)
            
            Spacer()

            if (food.nodes?.count ?? 0) > 0 {
                Button {
                    withAnimation { isShowingLinkedNodes = true }
                } label: {
                    Image(systemName: "list.clipboard")
                        .font(.title2)
                        .frame(width: 28, height: 28)
                }
            }
            
            Button {
                withAnimation { food.isFavorite.toggle() }
                try? modelContext.save()
                
                // *** НАЧАЛО НА КОРЕКЦИЯТА ***
                SearchIndexStore.shared.updateFavoriteStatus(for: food.id, isFavorite: food.isFavorite)
                // *** КРАЙ НА КОРЕКЦИЯТА ***
                
                NotificationCenter.default.post(name: .foodFavoriteToggled, object: food)
            } label: {
                Image(systemName: food.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(.yellow)
                    .font(.title2)
                    .frame(width: 28, height: 28)
            }
        }
        .foregroundStyle(effectManager.currentGlobalAccentColor)
    }

    // ... (всички останали views и функции в този файл остават без промяна)
    
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
    
    @ViewBuilder
    private var noImageInfoSection: some View {
        ZStack {
            let color = effectManager.isLightRowTextColor ? Color.black.opacity(0.8) : Color.white.opacity(0.8)
            Color(color).opacity(0)
            
            HStack(spacing: 24) {
                if let kcal = displayKcal {
                    VStack(spacing: 4) {
                        Label { Text("Energy") } icon: {
                            Image(systemName: "flame.fill").foregroundColor(.orange)
                        }
                        .font(.subheadline)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                        Text("\(kcal.clean) kcal").font(.title.weight(.bold))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                }
                if let weight = displayWeightG {
                    VStack(spacing: 4) {
                        Text("Serving Size")
                            .font(.subheadline)
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                        Text(formattedWeight(weight))
                            .font(.title.weight(.bold))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                }
                if food.minAgeMonths > 0 {
                    VStack(spacing: 4) {
                        Label { Text("Min. Age") } icon: {
                            Image(systemName: "person.badge.clock.fill")
                                .symbolRenderingMode(.hierarchical)
                        }
                        .font(.subheadline)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                        
                        Text("\(food.minAgeMonths) mo")
                            .font(.title.weight(.bold))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                }
            }
        }
        .glassCardStyle(cornerRadius: 20)
        .frame(height: 250)
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

    private var textInfoSection: some View {
        VStack(spacing: 16) {
            Text(food.name)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, food.photo != nil ? 0 : 16)
                .foregroundStyle(effectManager.currentGlobalAccentColor)

            if let desc = descriptionOrIngredientsText, !desc.isEmpty {
                Text(desc)
                    .font(.callout)
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if mainUIImage != nil {
                servingAndCalorieInfo
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var servingAndCalorieInfo: some View {
        HStack(spacing: 24) {
            if let weight = displayWeightG {
                VStack(spacing: 2) {
                    Text("Serving Size")
                        .font(.caption)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    Text(formattedWeight(weight))
                        .font(.headline)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                }
            }
            if let kcal = displayKcal {
                VStack(spacing: 2) {
                    Label { Text("Energy") } icon: { Image(systemName: "flame.fill").foregroundColor(.orange) }
                    .font(.caption)
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    Text("\(kcal.clean) kcal")
                        .font(.headline)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                }
            }
            if food.minAgeMonths > 0 {
                VStack(spacing: 2) {
                    Label { Text("Min. Age") } icon: {
                        Image(systemName: "person.badge.clock.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .font(.caption)
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    
                    Text("\(food.minAgeMonths) mo")
                        .font(.headline)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                }
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 10)
    }

    private var categorySection: some View {
        let items = (food.category ?? []).map { StaticTag(label: $0.rawValue, color: .purple) }
        return tagSectionView(title: "Category", tags: items)
    }
    
    private var dietsSection: some View {
        let items = (food.diets ?? []).map { StaticTag(label: $0.name, color: .blue) }
        return tagSectionView(title: "Diets", tags: items)
    }
    
    private var allergensSection: some View {
        let items = (food.allergens ?? []).map { StaticTag(label: $0.rawValue, color: .orange) }
        return tagSectionView(title: "Allergens", tags: items)
    }

    private var macrosSection: some View {
        let p = food.isRecipe || food.isMenu ? (food.totalProtein?.value ?? 0) : (food.macronutrients?.protein?.value ?? 0)
        let c = food.isRecipe || food.isMenu ? (food.totalCarbohydrates?.value ?? 0) : (food.macronutrients?.carbohydrates?.value ?? 0)
        let f = food.isRecipe || food.isMenu ? (food.totalFat?.value ?? 0) : (food.macronutrients?.fat?.value ?? 0)
        let totalWeight = self.displayWeightG ?? (p + c + f)
        return Group {
            if totalWeight > 0 {
                SectionView(title: "Macronutrients") {
                    MacroProportionBarView(protein: p, carbs: c, fat: f, totalWeight: totalWeight)
                }
                .padding()
                .glassCardStyle(cornerRadius: 20)
            }
        }
    }
    
    @ViewBuilder
    private var ingredientsSection: some View {
        if let ingredients = food.ingredients, !ingredients.isEmpty {
            SectionView(title: "Ingredients") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ingredients) { link in
                        if let ingredient = link.food {
                            HStack {
                                Text(ingredient.name)
                                    .foregroundColor(effectManager.currentGlobalAccentColor)
                                
                                Spacer()
                                
                                Text(formattedWeight(link.grams))
                                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                            }
                            .font(.subheadline)
                            if link.id != ingredients.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private var vitaminsSection: some View {
        let items = food.topVitamins(count: Int.max)
        return nutrientChipSectionView(title: "Vitamins", nutrients: items)
    }
    
    private var mineralsSection: some View {
        let items = food.topMinerals(count: Int.max)
        return nutrientChipSectionView(title: "Minerals", nutrients: items)
    }
    
    private var lipidsSection: some View {
        let items = food.allLipids()
        return nutrientChipSectionView(title: "Lipids", nutrients: items)
    }
    
    private var aminoAcidsSection: some View {
        let items = food.allAminoAcids()
        return nutrientChipSectionView(title: "Amino Acids", nutrients: items)
    }

    private var carbDetailsSection: some View {
        let items = food.allCarbDetails()
        return nutrientChipSectionView(title: "Carbohydrate Details", nutrients: items)
    }
    
    private var sterolsSection: some View {
        let items = food.allSterols()
        return nutrientChipSectionView(title: "Sterols", nutrients: items)
    }
    
    private var otherCompoundsSection: some View {
        let items = food.allOtherCompounds()
        return nutrientChipSectionView(title: "Other Compounds", nutrients: items)
    }
    
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

    @ViewBuilder
    private func nutrientChipSectionView(title: String, nutrients: [DisplayableNutrient]) -> some View {
        if !nutrients.isEmpty {
            SectionView(title: title) {
                CustomFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    if title == "Lipids"{
                        ForEach(nutrients) { nutrient in
                            NutrientChipView(name: nutrient.name, value: nutrient.value, unit: nutrient.unit, color: .yellow)
                        }
                    } else if title == "Other Compounds"{
                        ForEach(nutrients) { nutrient in
                            NutrientChipView(name: nutrient.name, value: nutrient.value, unit: nutrient.unit, color: .brown)
                        }
                    } else {
                        ForEach(nutrients) { nutrient in
                            NutrientChipView(name: nutrient.name, value: nutrient.value, unit: nutrient.unit, color: nutrient.color)
                        }
                    }
                }
            }
            .padding()
            .glassCardStyle(cornerRadius: 20)
        }
    }
    
    @ViewBuilder
    private var linkedNodesView: some View {
        let linkedNodes = food.nodes?.sorted { $0.date > $1.date } ?? []

        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    withAnimation { isShowingLinkedNodes = false }
                }) {
                    HStack {
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
                    description: Text("You haven't linked this food item to any notes yet.")
                )
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                .frame(maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(linkedNodes) { node in
                            Button(action: {
                                withAnimation(.easeInOut) {
                                    nodeToEdit = node
                                }
                            }) {
                                NodeRowView(node: node)
                            }
                            .buttonStyle(.plain)
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
    
    private var phSection: some View {
        let phValue = food.other?.alkalinityPH?.value
        return Group {
            if let ph = phValue, ph >= 0 {
                SectionView(title: "pH") {
                    PHScaleView(ph: ph)
                }
                .padding()
                .glassCardStyle(cornerRadius: 20)
            }
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
            
            if name == "pH" {
                Text(scaled.clean)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(effectManager.currentGlobalAccentColor)
            } else {
                Text("\(scaled.clean) \(finalUnit)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(effectManager.currentGlobalAccentColor)
            }
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

fileprivate struct MacroProportionBarView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let protein: Double, carbs: Double, fat: Double, totalWeight: Double
    private let macroSum: Double, other: Double
    init(protein: Double, carbs: Double, fat: Double, totalWeight: Double) {
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.totalWeight = totalWeight > 0 ? totalWeight : (protein + carbs + fat)
        self.macroSum = protein + carbs + fat
        self.other = max(0, self.totalWeight - self.macroSum)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if totalWeight > 0 {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Rectangle().fill(Color(hex: "4A86E8"))
                            .frame(width: geo.size.width * (protein / totalWeight))
                        Rectangle().fill(Color(hex: "FCC934"))
                            .frame(width: geo.size.width * (carbs / totalWeight))
                        Rectangle().fill(Color(hex: "34A853"))
                            .frame(width: geo.size.width * (fat / totalWeight))
                        if other > 0 {
                            Rectangle()
                                .fill(effectManager.currentGlobalAccentColor.opacity(0.8))
                                .frame(width: geo.size.width * (other / totalWeight))
                        }
                    }
                    .frame(height: 12)
                    .clipShape(Capsule())
                }
                .frame(height: 12)
            }
            HStack {
                legendItem(label: "Protein", value: protein, color: Color(hex: "4A86E8"))
                Spacer()
                legendItem(label: "Carbs", value: carbs, color: Color(hex: "FCC934"))
                Spacer()
                legendItem(label: "Fat", value: fat, color: Color(hex: "34A853"))
            }.font(.caption)
        }
    }
    @ViewBuilder private func legendItem(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color).frame(width: 8, height: 8)
            
            Text(label)
                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
            Text(value.clean + "g")
                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
        }
    }
}

fileprivate struct PHScaleView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let ph: Double
    private let phMin: Double = 0
    private let phMax: Double = 14
    
    private let acidicMark: Double = 0
    private let neutralMark: Double = 7
    private let alkalineMark: Double = 14
    
    private let barHeight: CGFloat = 12
    private var arrowBelowY: CGFloat { barHeight + 4 }
    private var textBelowY:  CGFloat { barHeight + 16 }
    private var arrowAboveY: CGFloat { -10 }
    private var textAboveY:  CGFloat { -16 }

    private let gradientColors = [
        Color(hex: "DA7C70"),
        Color(hex: "E5B456"),
        Color(hex: "A6C368"),
        Color(hex: "6E9BC1"),
        Color(hex: "707BAA")
    ]

    @State private var currentValueLabelWidth: CGFloat = 0
    private struct CurrentValueWidthKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    private func xFor(_ value: Double, width: CGFloat, edgePadding: CGFloat) -> CGFloat {
        let innerWidth = width - edgePadding * 2
        return edgePadding + innerWidth * CGFloat(value / phMax)
    }

    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let W = geo.size.width
                let edgePadding: CGFloat = 8

                let acidicX    = xFor(acidicMark,   width: W, edgePadding: edgePadding)
                let neutralX   = xFor(neutralMark,  width: W, edgePadding: edgePadding)
                let alkalineX  = xFor(alkalineMark, width: W, edgePadding: edgePadding)
                let currentX   = xFor(ph,           width: W, edgePadding: edgePadding)

                ZStack(alignment: .leading) {
                    LinearGradient(
                        gradient: Gradient(colors: gradientColors),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: barHeight)
                    .clipShape(Capsule())

                    TriangleUp()
                        .fill(effectManager.currentGlobalAccentColor)
                        .frame(width: 10, height: 6)
                        .offset(x: currentX - 5, y: arrowAboveY)
                }
                .overlay(alignment: .topLeading) {
                    Triangle()
                        .fill(effectManager.currentGlobalAccentColor.opacity(0.9))
                        .frame(width: 8, height: 6)
                        .position(x: acidicX, y: arrowBelowY)
                    Text("0")
                        .font(.caption2)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                        .position(x: acidicX, y: textBelowY)

                    Triangle()
                        .fill(effectManager.currentGlobalAccentColor.opacity(0.9))
                        .frame(width: 8, height: 6)
                        .position(x: neutralX, y: arrowBelowY)
                    Text("7")
                        .font(.caption2)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                        .position(x: neutralX, y: textBelowY)

                    Triangle()
                        .fill(effectManager.currentGlobalAccentColor.opacity(0.9))
                        .frame(width: 8, height: 6)
                        .position(x: alkalineX, y: arrowBelowY)
                    Text("14")
                        .font(.caption2)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                        .position(x: alkalineX, y: textBelowY)

                    Text("Acidic")
                        .font(.caption2)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
                        .position(x: acidicX + 20, y: textBelowY + 12)
                    Text("Neutral")
                        .font(.caption2)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
                        .position(x: neutralX, y: textBelowY + 12)
                    Text("Alkaline")
                        .font(.caption2)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
                        .position(x: alkalineX - 24, y: textBelowY + 12)

                    let roundedPH = (ph * 10).rounded() / 10
                    let phText: String = (floor(roundedPH) == roundedPH) ? String(format: "%.0f", roundedPH) : String(format: "%.1f", roundedPH)
                    
                    Text(phText)
                        .font(.caption.bold())
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(key: CurrentValueWidthKey.self, value: g.size.width)
                            }
                        )
                        .onPreferenceChange(CurrentValueWidthKey.self) { width in
                            currentValueLabelWidth = width
                        }
                        .position(x: currentX, y: textAboveY)
                }
            }
            .padding(.top, 20)
            .frame(height: barHeight + 52)
        }
        .padding(.horizontal, 8)
    }
}
