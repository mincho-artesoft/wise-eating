import SwiftUI

struct StorageBatchEditorContent: View {
    @Bindable var item: StorageItem
    @ObservedObject private var effectManager = EffectManager.shared

    @Environment(\.modelContext) private var modelContext

    @FocusState private var focusedField: Batch.ID?
    
    @State private var isShowingDeleteConfirmation = false
    @State private var batchToDelete: Batch? = nil
    
    var body: some View {
        // --- НАЧАЛО НА ПРОМЯНАТА (1/4): Добавяме ScrollViewReader ---
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    
                    ForEach(item.batches) { batch in
                        BatchCardView(
                            batch: batch,
                            deleteAction: {
                                // --- НАЧАЛО НА ПРОМЯНАТА ---
                                if #available(iOS 26.0, *) {
                                    delete(batch: batch)
                                } else {
                                    self.batchToDelete = batch
                                    self.isShowingDeleteConfirmation = true
                                }
                                // --- КРАЙ НА ПРОМЯНАТА ---
                            },
                            onQuantityChanged: { change in logManualCorrection(quantityChange: change) },
                            focusedField: $focusedField
                        )
                        .glassCardStyle(cornerRadius: 20)
                        // --- НАЧАЛО НА ПРОМЯНАТА (2/4): Добавяме ID на картата ---
                        .id(batch.id)
                    }
                    
                    if item.batches.isEmpty {
                        Text("No batches found. Add a new one to get started.")
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                            .padding()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    
                    Button(action: addBatch) {
                        Label("Add Another Batch", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    .glassCardStyle(cornerRadius: 20)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    
                    Spacer(minLength: 150)
                }
                .padding()
            }
            // --- НАЧАЛО НА ПРОМЯНАТА (3/4): Добавяме .onChange за FocusState ---
            .onChange(of: focusedField) { _, newValue in
                guard let focusedID = newValue else { return }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(focusedID, anchor: .top)
                    }
                }
            }
            // --- КРАЙ НА ПРОМЯНАТА (3/4) ---
        } // --- КРАЙ НА ПРОМЯНАТА (1/4): Край на ScrollViewReader
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
        .alert("Delete Batch", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let batch = batchToDelete {
                    delete(batch: batch)
                }
                batchToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                batchToDelete = nil
            }
        } message: {
            let quantityDisplay = UnitConversion.formatGramsToGramsOrOunces(batchToDelete?.quantity ?? 0)
            let expirationString = batchToDelete?.expirationDate?.formatted(date: .abbreviated, time: .omitted) ?? "no expiration"
            Text("Are you sure you want to delete this batch (\(quantityDisplay.value) \(quantityDisplay.unit), expires: \(expirationString))? This action cannot be undone.")
        }
    }

    private func addBatch() {
        withAnimation {
            let defaultQuantityInGrams = GlobalState.measurementSystem == "Imperial" ? UnitConversion.ozToG(4.0) : 100.0
            
            let newBatch = Batch(
                quantity: defaultQuantityInGrams,
                expirationDate: Calendar.current.date(byAdding: .day, value: 7, to: .now)!
            )
            
            newBatch.storageItem = item
            item.batches.append(newBatch)
            
            let transaction = StorageTransaction(
                date: Date(),
                type: .addition,
                quantityChange: newBatch.quantity,
                profile: item.owner,
                food: item.food
            )
            modelContext.insert(transaction)
        }
    }
    
    private func delete(batch: Batch) {
        focusedField = nil
            
        DispatchQueue.main.async {
            let transaction = StorageTransaction(
                date: Date(),
                type: .manualRemoval,
                quantityChange: -batch.quantity,
                profile: self.item.owner,
                food: self.item.food
            )
            self.modelContext.insert(transaction)
        
            self.item.batches.removeAll { $0.id == batch.id }
            if batch.storageItem != nil {
                 self.modelContext.delete(batch)
            }
        }
    }
    
    private func logManualCorrection(quantityChange: Double) {
        guard quantityChange != 0 else { return }
        let transaction = StorageTransaction(
            date: Date(),
            type: .manualCorrection,
            quantityChange: quantityChange,
            profile: item.owner,
            food: item.food
        )
        modelContext.insert(transaction)
    }
}
