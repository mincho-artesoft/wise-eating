import SwiftUI
import SwiftData

// Main Detail View with Picker
struct StorageItemDetailView: View {
    @Bindable var item: StorageItem
    let viewModel: StorageListVM // To call consume action
    @ObservedObject private var effectManager = EffectManager.shared

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // 1. Променяме състоянието да пази индекс (Int), а не самия Tab.
    // Започваме от 0, което съответства на първия елемент - .consume
    @State private var selectedTab: Tab = .consume

    @Binding var detailMenuState: MenuState

    enum Tab: String, CaseIterable, Identifiable, Hashable {
        case consume = "Consume"
        case edit = "Edit Batches"
        case history = "History"

        var id: String { self.rawValue }

        var systemImage: String {
            switch self {
            case .consume: "minus.circle.fill"
            case .edit: "pencil.circle.fill"
            case .history: "list.bullet.rectangle.portrait.fill"
            }
        }
    }

    var body: some View {
            VStack(spacing: 0) {
                HStack {
                    HStack{
                        Button("Close") {  detailMenuState = .collapsed }
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 20)
                    
                  
                    Spacer()
                    
                    Text(item.food?.name ?? "Item Details")
                        .font(.headline)
                        .foregroundColor(effectManager.currentGlobalAccentColor)

                    Spacer()
                    // За да бъде центрирането перфектно, трябва да имаме "невидим" елемент
                    // отдясно, който е със същата ширина като бутона вляво.
                    HStack{
                        Button("Close") {  detailMenuState = .collapsed }
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    .hidden()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)

                }
                .frame(height: 44)
                .padding(.horizontal)
                
                WrappingSegmentedControl(selection: $selectedTab, layoutMode: .wrap)
                    .padding(.horizontal)
                    .padding(.vertical)
               
                Group {
                    // switch операторът продължава да работи, защото използва
                    // изчисляемата променлива 'selectedTab'.
                    switch selectedTab {
                    case .consume:
                        ConsumeStockViewContent(itemForDisplay: item, onConsume: { quantity in
                            viewModel.consume(quantity: quantity, from: item)
                            // След консумация, изгледът ще бъде затворен от onCancel() в ConsumeStockViewContent
                        }, onCancel: { dismiss() }) // onCancel тук се използва от бутона "Close" и след консумация
                        .environment(\.modelContext, modelContext)

                    case .edit:
                        StorageBatchEditorContent(item: item)
                            .environment(\.modelContext, modelContext)

                    case .history:
                        TransactionHistoryContent(item: item)
                            .environment(\.modelContext, modelContext)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
    }
    
}
