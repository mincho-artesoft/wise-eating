import SwiftUI

/// A proposed write: what will change, what the app's own check found, and
/// the person's confirm or cancel. Grams can be changed before confirming.
struct AssistantPreviewCard: View {
    let action: AssistantPendingAction
    @ObservedObject var session: AssistantSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(action.title).font(.headline)

            if case let .logFoods(_, _, items) = action.payload {
                ForEach(items) { item in
                    AssistantGramsRow(item: item) { grams in
                        Task { await session.updateGrams(actionID: action.id, foodID: item.foodID, grams: grams) }
                    }
                }
                let kcal = items.reduce(0) { $0 + $1.kcal }
                let protein = items.reduce(0) { $0 + $1.proteinG }
                Text("About \(DietaryUnits.format(kcal.rounded())) kcal, \(DietaryUnits.format((protein * 10).rounded() / 10)) g protein")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if case let .constraints(list) = action.payload {
                // Extracted constraints: the person keeps only what is right.
                ForEach(list) { c in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.summary).font(.subheadline)
                            if let note = c.note, !note.isEmpty {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button { session.removeConstraint(actionID: action.id, constraintID: c.id) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .accessibilityLabel(Text("Remove"))
                    }
                }
                Text("You can change these later in Settings → Dietary constraints.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(action.lines, id: \.self) { line in
                    Text(line).font(.subheadline)
                }
            }

            if let report = action.report, !report.violations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(report.violations) { v in
                        Label { Text(v.message) } icon: {
                            Image(systemName: v.isBlocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        }
                        .font(.footnote)
                        .foregroundStyle(v.isBlocking ? .red : .orange)
                    }
                }
            }

            HStack {
                Button(role: .cancel) {
                    session.discard(action.id)
                } label: { Text("Cancel") }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    Task { await session.confirm(action.id) }
                } label: {
                    if action.needsSecondConfirmation {
                        Text("Log anyway")
                    } else {
                        Text("Confirm")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(action.report?.isBlocked ?? false)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct AssistantGramsRow: View {
    let item: AssistantProposedItem
    let onChange: (Double) -> Void
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(item.name).font(.subheadline).lineLimit(2)
            Spacer()
            TextField("g", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
            Text("g").foregroundStyle(.secondary)
            Button {
                onChange(0)
            } label: { Image(systemName: "minus.circle") }
            .accessibilityLabel(Text("Remove"))
        }
        .onAppear { text = DietaryUnits.format(item.grams) }
        .onChange(of: item.grams) { _, g in text = DietaryUnits.format(g) }
    }

    private func commit() {
        guard let grams = GlobalState.double(from: text) ?? Double(text), grams != item.grams else { return }
        onChange(grams)
    }
}
