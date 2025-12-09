//
//  BannerAdRowView.swift
//  WiseEating
//
//  Created by Aleksandar Svinarov on 9/12/25.
//


import SwiftUI

struct BannerAdRowView: View {
    @State private var isAdLoaded: Bool = true   // или false, както ти е по-ок

    var body: some View {
        BannerAdView(adsBool: $isAdLoaded, bucket: .large)
            .frame(maxWidth: .infinity)
            .frame(height: 120)   // скриваме, ако не е заредена
            .opacity(isAdLoaded ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: isAdLoaded)
    }
}
