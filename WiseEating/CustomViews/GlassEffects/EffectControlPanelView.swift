// FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth/WiseEating/CustomViews/GlassEffects/EffectControlPanelView.swift
import SwiftUI

struct EffectControlPanelView: View {
    @ObservedObject var effectManager = EffectManager.shared

    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Live Effect Controls").font(.headline)
                Spacer()
                Button(action: { effectManager.resetToDefaults() }) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .tint(effectManager.currentGlobalAccentColor.opacity(0.8))
            }
            
            Group {
                HStack {
                    Text("Saturation").frame(width: 100, alignment: .leading)
                    Slider(value: $effectManager.config.saturation, in: 0...2)
                    Text("\(effectManager.config.saturation, specifier: "%.2f")").frame(width: 50, alignment: .trailing)
                }
                HStack {
                    Text("Brightness").frame(width: 100, alignment: .leading)
                    Slider(value: $effectManager.config.brightness, in: -0.5...0.5)
                    Text("\(effectManager.config.brightness, specifier: "%.2f")").frame(width: 50, alignment: .trailing)
                }
                if !effectManager.config.useAppleMaterial {
                    HStack {
                        Text("Opacity").frame(width: 100, alignment: .leading)
                        Slider(value: $effectManager.config.customGlassOpacity, in: 0...0.5)
                        Text("\(effectManager.config.customGlassOpacity, specifier: "%.2f")").frame(width: 50, alignment: .trailing)
                    }
                }
                Toggle("Use Apple Material", isOn: $effectManager.config.useAppleMaterial.animation())

                Toggle("Contrast Scrim", isOn: $effectManager.config.useScrim)

            }
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal)
    }
}
