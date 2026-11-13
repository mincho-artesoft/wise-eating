import SwiftUI

struct BannerAdRowView: View {
    var body: some View {
    #if !targetEnvironment(macCatalyst)
        AdRowView()
    #endif
    }
}
