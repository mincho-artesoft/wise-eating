import SwiftUI

struct DropdownMenu<Item: Identifiable & Hashable>: View {
    @ObservedObject private var effectManager = EffectManager.shared

    @Binding var selection: Set<Item.ID>
    var items: [Item]
    var label: (Item) -> String
    var selectAllBtn: Bool = true
    @State private var searchText = ""
    
    @State private var lastToggledItemID: Item.ID? = nil

    var isEditable: Bool = false
        var isDeletable: Bool = false
        var onEdit: ((Item) -> Void)? = nil
        var onDelete: ((Item) -> Void)? = nil
    
    private var filtered: [Item] {
        searchText.isEmpty ? items
                           : items.filter { label($0)
                               .localizedCaseInsensitiveContains(searchText) }
    }
    private var allSelected: Bool {
        !items.isEmpty && selection.count == items.count
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Секцията за търсене остава същата
                HStack(spacing: 8) {
                    TextField("Search…", text: $searchText, prompt: Text("Search...")
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6)))
                        .capsuleInput(height: 32)
                        .disableAutocorrection(true)
                        .autocapitalization(.none)

                    if selectAllBtn{
                        Button(allSelected ? "Deselect all" : "Select all") {
                            toggleAll()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 5)

                // --- НАЧАЛО НА ПРОМЯНАТА ---
                ScrollViewReader { proxy in
                    // Заменяме ScrollView с List
                    List {
                        ForEach(filtered, id: \.id) { item in
                            Button {
                                toggle(item)
                            } label: {
                                HStack {
                                    Text(label(item))
                                        .foregroundColor(effectManager.currentGlobalAccentColor)
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    Spacer()
                                    if selection.contains(item.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(effectManager.currentGlobalAccentColor)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .id(item.id) // ID за ScrollViewReader
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if isDeletable {
                                    Button(role: .destructive) {
                                        onDelete?(item)
                                    } label: {
                                        Image(systemName: "trash.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                                    }
                                    .tint(.clear)
                                    
                                }
                                if isEditable {
                                    Button(role: .destructive) {
                                        onEdit?(item)
                                    } label: {
                                        Image(systemName: "pencil")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                                    }
                                    .tint(.clear)
                                }
                            }
                            // Модификатори за стилизиране на реда в списъка
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                        }
                        
                        // Добавяме празно пространство в края на списъка
                        Color.clear
                            .frame(height: 150)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain) // Премахва стила по подразбиране
                    .scrollContentBackground(.hidden) // Прави фона на List прозрачен
                    .onChange(of: lastToggledItemID) { _, newItemID in
                        if let id = newItemID {
                            withAnimation(.easeInOut) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                            lastToggledItemID = nil
                        }
                    }
                }
                // --- КРАЙ НА ПРОМЯНАТА ---
            }
            .padding(4)
        }
    }

    // MARK: – helpers
    private func toggle(_ item: Item) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
            lastToggledItemID = item.id
        }
    }
    
    private func toggleAll() {
        if allSelected {
            selection.removeAll()
        } else {
            selection = Set(items.map(\.id))
        }
    }
}

private struct WidthKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
