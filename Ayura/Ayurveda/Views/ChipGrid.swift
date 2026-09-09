import SwiftUI

struct ChipGrid<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    CustomFlowLayout(horizontalSpacing: 9, verticalSpacing: 9) {
      content
    }
  }
}
