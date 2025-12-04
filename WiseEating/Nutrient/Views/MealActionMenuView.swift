import SwiftUI

// MARK: - MealActionMenuView.swift

struct MealActionMenuView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // Callbacks
    let onDismiss: () -> Void
    let onCopyToNewPlan: () -> Void
    let onAddToExistingPlan: () -> Void
    let onGenerateWithAI: () -> Void
    let onScanBarcode: () -> Void
    let onNodesTapped: () -> Void // <-- ДОБАВЕТЕ ТОВА

    @State private var showAIAlert = false
    @State private var aiAlertText = ""

    private func message(for status: GlobalState.AIAvailabilityStatus) -> String {
        // ... (без промяна)
        switch status {
        case .available:
            return ""
        case .deviceNotEligible:
            return "This device doesn’t support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is turned off. Enable it in Settings to use AI meal generation."
        case .modelNotReady:
            return "The model is downloading or preparing. Please try again in a bit."
        case .unavailableUnsupportedOS:
            return "Apple Intelligence requires iOS 26 or newer. Update your OS to use this feature."
        case .unavailableOther:
            return "Apple Intelligence is currently unavailable for an unknown reason."
        }
    }

    var body: some View {
            VStack(spacing: 0) {
                // MARK: - Toolbar
                HStack {
                    Button("Cancel", action: onDismiss)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .glassCardStyle(cornerRadius: 20)

                    Spacer()
                    Text("Meal Actions").font(.headline)
                    Spacer()

                    Button("Cancel") {}.hidden()
                        .padding(.horizontal, 10).padding(.vertical, 5)
                }
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .padding()

                // MARK: - Action Buttons
                VStack(spacing: 12) {
                    
                    Button(action: { onScanBarcode() }) {
                        Label("Scan Barcode", systemImage: "barcode.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .glassCardStyle(cornerRadius: 20)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                    
                    // +++ НАЧАЛО НА ПРОМЯНАТА +++
                    Button(action: { onNodesTapped() }) {
                        Label("Notes", systemImage: "list.clipboard")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .glassCardStyle(cornerRadius: 20)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                    // +++ КРАЙ НА ПРОМЯНАТА +++

                    if GlobalState.aiAvailability != .deviceNotEligible {
                        Button(action: {
                            let status = GlobalState.aiAvailability
                            if status == .available {
                                onGenerateWithAI()
                            } else {
                                aiAlertText = message(for: status)
                                showAIAlert = true
                            }
                        }) {
                            Label("Generate with AI", systemImage: "sparkles")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .padding()
                        .glassCardStyle(cornerRadius: 20)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                    }

                    Button(action: { onCopyToNewPlan() }) {
                        Label("Copy to New Meal Plan", systemImage: "doc.on.doc")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .glassCardStyle(cornerRadius: 20)
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                    Button(action: { onAddToExistingPlan() }) {
                        Label("Add to Existing Meal Plan", systemImage: "plus.rectangle.on.rectangle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .glassCardStyle(cornerRadius: 20)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .alert("Error", isPresented: $showAIAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(aiAlertText)
            }
        }
}
