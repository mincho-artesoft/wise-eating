import SwiftUI

struct MultiSelectButton<Item: Identifiable & Hashable>: View {
    @Binding var selection: Set<Item.ID>
    var items: [Item]
    var label: (Item) -> String
    var prompt: String
    var displayLimit: Int? = nil // НОВ ПАРАМЕТЪР
    @ObservedObject private var effectManager = EffectManager.shared

    var isExpanded: Bool
    @State var disabled: Bool = false
    
    // Сортираме избраните елементи за по-консистентен изглед
    private var sortedSelection: [Item] {
        items.filter { selection.contains($0.id) }
             .sorted { label($0).localizedCompare(label($1)) == .orderedAscending }
    }
        
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)

            if !disabled {
                chevron
            }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if selection.isEmpty {
            promptView
        } else {
            selectedItemsView
        }
    }

    private var promptView: some View {
        Text(prompt)
            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
    }

    private var selectedItemsView: some View {
        FlowLayout(spacing: 8) {
            // ----- 👇 НАЧАЛО НА ПРОМЯНАТА 👇 -----
            let displayedItems = sortedSelection
            let limit = displayLimit ?? displayedItems.count
            
            ForEach(Array(displayedItems.prefix(limit))) { item in
                TagView(label: label(item), disabled: disabled) {
                    selection.remove(item.id)
                }
                .buttonStyle(.plain)
            }
            
            if displayedItems.count > limit {
                let remaining = displayedItems.count - limit
                Text("+ \(remaining) more")
                    .font(.system(size: 16))
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .glassCardStyle(cornerRadius: 20)
            }
            // ----- 👆 КРАЙ НА ПРОМЯНАТА 👆 -----
        }
    }

    private var chevron: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .animation(.easeInOut(duration: 0.2), value: isExpanded)
            .padding(.top, 4)
    }
}


private struct TagView: View {
    let label: String
    var disabled = false
    let onRemove: () -> Void

    @ObservedObject private var effectManager = EffectManager.shared

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 16))
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .lineLimit(1)                  // 👉 не повече от 1 ред
                .truncationMode(.tail)         // 👉 добавя "…" ако не стига място
                

            if !disabled {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            effectManager.currentGlobalAccentColor,
                            effectManager.isLightRowTextColor ? .black.opacity(0.2) : .white.opacity(0.2)
                        )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassCardStyle(cornerRadius: 20)
        .frame(maxWidth: UIScreen.main.bounds.width * 0.6, alignment: .leading)
    }
}


// MARK: – FlowLayout (Unchanged)
@available(iOS 16.0, macOS 13.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        var size = CGSize.zero
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)

            if rowWidth + s.width > maxWidth {
                size.width = max(size.width, rowWidth)
                size.height += rowHeight + spacing
                rowWidth  = s.width
                rowHeight = s.height
            } else {
                rowWidth  += (rowWidth == 0 ? 0 : spacing) + s.width
                rowHeight  = max(rowHeight, s.height)
            }
        }

        size.width  = max(size.width, rowWidth)
        size.height += rowHeight
        return size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        var origin = CGPoint(x: bounds.minX, y: bounds.minY)
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)

            if origin.x + s.width > bounds.maxX {
                origin.x  = bounds.minX
                origin.y += rowHeight + spacing
                rowHeight = 0
            }

            sub.place(
                at: origin,
                proposal: ProposedViewSize(width: s.width, height: s.height)
            )

            origin.x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
