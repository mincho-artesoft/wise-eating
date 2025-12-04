import SwiftUI

/// A custom layout that arranges views in a flow, from left to right,
/// wrapping to the next line when the container width is exceeded.
/// This implementation ensures all rows are left-aligned.
@available(iOS 16.0, macOS 13.0, *)
struct CustomFlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    init(horizontalSpacing: CGFloat = 8, verticalSpacing: CGFloat = 8) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }
    
    // The main function to arrange the subviews
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        let maxWidth = bounds.width

        // Group subviews into rows based on available width
        let rows = generateRows(maxWidth: maxWidth, proposal: proposal, subviews: subviews)
        
        for row in rows {
            // Reset the X origin for each new row to ensure left alignment
            origin.x = bounds.origin.x
            
            for view in row {
                let viewSize = view.sizeThatFits(proposal)
                view.place(at: origin, proposal: proposal)
                origin.x += viewSize.width + horizontalSpacing
            }
            
            // Move the Y origin down for the next row
            origin.y += (row.first?.sizeThatFits(proposal).height ?? 0) + verticalSpacing
        }
    }
    
    // Calculates the required size for the entire layout
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = generateRows(maxWidth: proposal.width ?? 0, proposal: proposal, subviews: subviews)
        let height = rows.reduce(0) { partialResult, row in
            partialResult + (row.first?.sizeThatFits(proposal).height ?? 0)
        } + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        
        return .init(width: proposal.width ?? 0, height: height)
    }
    
    /// A helper function to break the list of subviews into rows.
    private func generateRows(maxWidth: CGFloat, proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        var row: [LayoutSubviews.Element] = []
        var rows: [[LayoutSubviews.Element]] = []
        var origin = CGRect.zero.origin

        for view in subviews {
            let viewSize = view.sizeThatFits(proposal)
            
            if origin.x + viewSize.width + horizontalSpacing > maxWidth {
                rows.append(row)
                row = []
                origin.x = 0
            }
            
            row.append(view)
            origin.x += viewSize.width + horizontalSpacing
        }
        
        if !row.isEmpty {
            rows.append(row)
        }
        
        return rows
    }
}
