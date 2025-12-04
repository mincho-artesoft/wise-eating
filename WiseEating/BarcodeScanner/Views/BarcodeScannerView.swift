import SwiftUI
import SwiftData
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import Network

enum BarcodeScannerMode {
    case shoppingList
    case nutritionLog
}

struct BarcodeScannerView: View {
    let mode: BarcodeScannerMode
    var onBarcodeSelect: (DetectedObjectEntity) -> Void
    let onAddFoodItem: (FoodItem) -> Void
    let profile: Profile?

    @State private var showAlert = false
    @State private var alertMessage = ""

    @State private var scannedItems: [ScannedItem] = []
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext

    @State private var permissionStatus: AVAuthorizationStatus = .notDetermined
    @ObservedObject private var effectManager = EffectManager.shared

    @State private var isShowingCameraPicker = false
    @State private var isShowingPhotoLibraryPicker = false
    @State private var isProcessingImage = false

    @State private var isLivePreviewOn = true
    @State private var showPermissionAlert = false

    @State private var isShowingDeleteScannedItemAlert = false
    @State private var scannedItemToDelete: ScannedItem? = nil

    @State private var itemForConfirmation: ScannedItem? = nil
    @State private var showAddConfirmation = false

    // +++ START OF CHANGE +++
    @State private var showAIGenerationToast = false
    @State private var toastTimer: Timer? = nil
    @State private var toastProgress: Double = 0.0
    // +++ END OF CHANGE +++

    init(mode: BarcodeScannerMode, profile: Profile?, onBarcodeSelect: @escaping (DetectedObjectEntity) -> Void, onAddFoodItem: @escaping (FoodItem) -> Void) {
        self.mode = mode
        self.profile = profile
        self.onBarcodeSelect = onBarcodeSelect
        self.onAddFoodItem = onAddFoodItem
    }

    var body: some View {
        // Проверката за интернет е премахната. Директно проверяваме за камера.
        switch permissionStatus {
        case .authorized:
            scannerContent
        case .denied, .restricted:
            PermissionDeniedView(type: .camera, hasBackground: false, onTryAgain: checkCameraPermission)
        case .notDetermined:
            VStack(spacing: 8) {
                Text("Requesting Camera Access…")
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.85))
                ProgressView()
                    .tint(effectManager.currentGlobalAccentColor)
            }
            .onAppear(perform: checkCameraPermission)
        @unknown default:
            EmptyView()
        }
    }

    private var scannerContent: some View {
        VStack(spacing: 0) {
            ZStack {
                if isLivePreviewOn {
                    LiveCameraView { newResults in
                        handleScanResults(newResults)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal)
                } else {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme,effectManager.isLightRowTextColor ? .dark : .light) // 👈 Това принуждава материала да е тъмен
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "barcode.viewfinder")
                                    .font(.title2)
                                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.9))
                                Text("Live preview is OFF")
                                    .font(.subheadline)
                                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                                Text("Tap “Live Off” to enable camera")
                                    .font(.footnote)
                                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6))
                            }
                            .padding()
                        )
                        .padding(.horizontal)
                }

                VStack {
                    Spacer()
                    HStack(spacing: 0) {
                        Spacer()
                        scanOptionButton(
                            icon: "barcode.viewfinder",
                            text: isLivePreviewOn ? "Live On" : "Live Off"
                        ) {
                            toggleLivePreview()
                        }

                        Spacer()

                        scanOptionButton(icon: "camera.fill", text: "Camera") {
                            isShowingCameraPicker = true
                        }

                        Spacer()

                        scanOptionButton(icon: "photo.on.rectangle.angled", text: "Upload") {
                            isShowingPhotoLibraryPicker = true
                        }
                        Spacer()
                    }
                }

                if isProcessingImage {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding(20)
                        .glassCardStyle(cornerRadius: 20)
                }
            }
            .frame(height: 240)
            .padding(.top)

            VStack(alignment: .leading, spacing: 12) {
                Text("Scanned")
                    .font(.headline)
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                if scannedItems.isEmpty {
                    VStack {
                        Spacer()
                        Text("No scanned barcodes")
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.75))
                        Spacer()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(scannedItems) { item in
                            BarcodeRowView(
                                item: item,
                                onSelect: {
                                    if item.resolvedFoodItem != nil || item.productName != nil {
                                        itemForConfirmation = item
                                        showAddConfirmation = true
                                    } else {
                                        onBarcodeSelect(item.entity)
                                    }
                                },
                                onOpenURL: { url in openURL(url) }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .padding(.bottom, 8)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    if #available(iOS 26.0, *) {
                                        withAnimation { deleteScannedItem(item) }
                                    } else {
                                        scannedItemToDelete = item
                                        isShowingDeleteScannedItemAlert = true
                                    }
                                } label: {
                                    Image(systemName: "trash.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                                }
                                .tint(.clear)
                            }
                        }

                        Color.clear.frame(height: 50)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
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
            .padding(.top, 12)
            .padding(.horizontal)
            .background(Color.clear)
        }
        .padding(.bottom, 50)
        .background(Color.clear)
        .sheet(isPresented: $isShowingCameraPicker) {
            CameraPicker { image in
                processImage(image)
            }
            .presentationCornerRadius(20)
        }
        .sheet(isPresented: $isShowingPhotoLibraryPicker) {
            PhotoLibraryPicker { image in
                processImage(image)
            }
            .presentationCornerRadius(20)
        }
        .alert("Camera access needed", isPresented: $showPermissionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("To use the live preview, allow camera access in Settings.")
        }
        .alert("Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }.foregroundColor(effectManager.currentGlobalAccentColor)
        } message: { Text(alertMessage) }
        .alert("Delete Item", isPresented: $isShowingDeleteScannedItemAlert) {
            Button("Delete", role: .destructive) {
                if let item = scannedItemToDelete {
                    withAnimation { deleteScannedItem(item) }
                }
                scannedItemToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                scannedItemToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this scanned barcode?")
        }
        .confirmationDialog(
            "Add Item?",
            isPresented: $showAddConfirmation,
            presenting: itemForConfirmation
        ) { item in
            if let foodItem = item.resolvedFoodItem {
                Button("Add \"\(foodItem.name)\"") {
                    onAddFoodItem(foodItem)
                    withAnimation { deleteScannedItem(item) }
                }
            }

            if let productName = item.productName, !productName.isEmpty {
                Button("Create New Food: \"\(productName)\"") {
                    createNewFoodItemAndAdd(from: item)
                }
            }
            if GlobalState.aiAvailability != .deviceNotEligible {
                if let productName = item.productName, !productName.isEmpty {
                    Button("Create New Food with AI: \"\(productName)\"") {
                        createNewFoodItemWithAIAndAdd(from: item)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                itemForConfirmation = nil
            }
        } message: { item in
            let destination = (mode == .shoppingList) ? "your shopping list" : "your meal"
            if let foodItem = item.resolvedFoodItem {
                Text("Found \"\(foodItem.name)\" in your database. You can add it, or create a new entry for \"\(item.productName ?? "this product")\".")
            } else if let productName = item.productName {
                Text("\"\(productName)\" was not found in your database. You can create a new entry for it.")
            } else {
                Text("Add this item to \(destination)?")
            }
        }
        // +++ START OF CHANGE +++
        .overlay {
            if showAIGenerationToast {
                aiGenerationToast
            }
        }
        // +++ END OF CHANGE +++
    }

    @ViewBuilder
    private func scanOptionButton(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(text)
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .foregroundColor(effectManager.currentGlobalAccentColor)
        }
        .buttonStyle(.plain)
        .glassCardStyle(cornerRadius: 12)
    }

    private func deleteScannedItem(_ item: ScannedItem) {
        if let idx = scannedItems.firstIndex(where: { $0.id == item.id }) {
            scannedItems.remove(at: idx)
        }
    }

    private func deleteScannedItem(at offsets: IndexSet) {
        scannedItems.remove(atOffsets: offsets)
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: self.permissionStatus = .authorized
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.permissionStatus = granted ? .authorized : .denied
                }
            }
        case .denied, .restricted: self.permissionStatus = .denied
        @unknown default: self.permissionStatus = .denied
        }
    }

    private func toggleLivePreview() {
        if isLivePreviewOn {
            isLivePreviewOn = false
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isLivePreviewOn = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.permissionStatus = granted ? .authorized : .denied
                    if granted {
                        self.isLivePreviewOn = true
                    } else {
                        self.showPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showPermissionAlert = true
        @unknown default:
            showPermissionAlert = true
        }
    }

    private func handleScanResults(_ newResults: [DetectedObjectEntity]) {
        let newBarcodes = newResults.filter {
            ($0.category?.contains("Barcode") ?? false) || ($0.category?.contains("QR") ?? false)
        }
        guard !newBarcodes.isEmpty else { return }

        let existing = Set(self.scannedItems.map { $0.entity.title })
        for barcodeEntity in newBarcodes where !existing.contains(barcodeEntity.title) {
            let newItem = ScannedItem(entity: barcodeEntity)
            self.scannedItems.insert(newItem, at: 0)
            newItem.performProductLookup(container: modelContext.container)
        }
    }

    @MainActor
    private func processImage(_ image: UIImage) {
        isProcessingImage = true
        Task {
            defer { isProcessingImage = false }

            guard let cgImage = image.cgImage else {
                print("Could not create CGImage from UIImage.")
                return
            }

            let orientation = CGImagePropertyOrientation(image.imageOrientation)

            do {
                let results = try await VisualExplainService.shared.classify(cgImage: cgImage, orientation: orientation)
                handleScanResults(results)
            } catch {
                print("Error processing image: \(error)")
            }
        }
    }

    private func createNewFoodItemAndAdd(from scannedItem: ScannedItem) {
        guard let productName = scannedItem.productName else { return }

        let nextID: Int
        do {
            var desc = FetchDescriptor<FoodItem>()
            desc.sortBy = [SortDescriptor(\.id, order: .reverse)]
            desc.fetchLimit = 1
            let maxID = (try modelContext.fetch(desc).first?.id) ?? 0
            nextID = maxID + 1
        } catch {
            nextID = (try? modelContext.fetch(FetchDescriptor<FoodItem>()).count) ?? 0 + 1000000
        }

        let newFoodItem = FoodItem(id: nextID, name: productName)


        modelContext.insert(newFoodItem)
        do {
            try modelContext.save()
            onAddFoodItem(newFoodItem)
            withAnimation { deleteScannedItem(scannedItem) }
        } catch {
            print("Failed to save new food item from barcode: \(error)")
        }
    }

    // +++ START OF CHANGE +++
    private func createNewFoodItemWithAIAndAdd(from scannedItem: ScannedItem) {
        guard let productName = scannedItem.productName else { return }
        guard ensureAIAvailableOrShowMessage() else { return }

        let nextID: Int
        do {
            var desc = FetchDescriptor<FoodItem>()
            desc.sortBy = [SortDescriptor(\.id, order: .reverse)]
            desc.fetchLimit = 1
            let maxID = (try modelContext.fetch(desc).first?.id) ?? 0
            nextID = maxID + 1
        } catch {
            nextID = (try? modelContext.fetch(FetchDescriptor<FoodItem>()).count) ?? 0 + 1000000
        }

        let newFoodItem = FoodItem(id: nextID, name: productName)


        modelContext.insert(newFoodItem)
               do {
                   try modelContext.save()
                   onAddFoodItem(newFoodItem)
                   withAnimation { deleteScannedItem(scannedItem) }
               } catch {
                   print("Failed to save new food item from barcode: \(error)")
               }
        AIManager.shared.startEmptyFoodGeneration(for: profile, foodItem: newFoodItem)
        
        triggerAIGenerationToast()
                
        withAnimation { deleteScannedItem(scannedItem) }
    }
        
    
    @ViewBuilder
    private var aiGenerationToast: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Generation Scheduled")
                        .fontWeight(.bold)
                    Text("You'll be notified when your food is ready.")
                        .font(.caption)

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
                .buttonStyle(.borderless).foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .padding()
            .glassCardStyle(cornerRadius: 20)
            .padding()
            .transition(.move(edge: .top).combined(with: .opacity))
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.keyboard)
    }

    private func triggerAIGenerationToast() {
        toastTimer?.invalidate()
        toastProgress = 0.0
        withAnimation {
            showAIGenerationToast = true
        }

        let totalDuration = 5.0
        let updateInterval = 0.1
        let progressIncrement = updateInterval / totalDuration

        toastTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { timer in
            DispatchQueue.main.async {
                self.toastProgress = min(1.0, self.toastProgress + progressIncrement)
                if self.toastProgress >= 1.0 {
                    timer.invalidate()
                    self.toastTimer = nil
                    withAnimation {
                        self.showAIGenerationToast = false
                    }
                }
            }
        }
    }
    // +++ END OF CHANGE +++

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
}
