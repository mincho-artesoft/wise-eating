import SwiftUI

struct ProductCard: View {
    @Binding var product: EditableProduct
    var focusedBatchID: FocusState<UUID?>.Binding
    @ObservedObject private var effectManager = EffectManager.shared
    let onDeleteProduct: () -> Void
    let onAddBatch: () -> Void
    let onDeleteBatch: (UUID) -> Void
    let onShouldDismissGlobalSearch: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(product.food.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                Spacer()
                Button(role: .destructive, action: onDeleteProduct) {
                    Image(systemName: "trash.circle.fill")
                        .font(.title2)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                }
                .buttonStyle(.plain)
            }
            
            Divider()

            ForEach($product.batches) { $batch in
                if !batch.isMarkedForDeletion {
                    BatchEditRow(
                        batch: $batch,
                        product: $product,
                        focusedBatchID: focusedBatchID,
                        onDelete: { onDeleteBatch(batch.id) },
                        onInteract: onShouldDismissGlobalSearch
                    )

                    let visibleBatches = product.batches.filter { !$0.isMarkedForDeletion }
                    if batch.id != visibleBatches.last?.id {
                        Divider().padding(.horizontal, 8)
                    }
                }
            }
            
            Button(action: onAddBatch) {
                Label("Add Batch", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
            }
            .buttonStyle(.borderless)
            .padding(.top, 8)
        }
        .padding()
    }
}
