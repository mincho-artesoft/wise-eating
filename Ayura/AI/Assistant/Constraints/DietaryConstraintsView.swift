import SwiftUI

/// The person's own dietary constraints: what the assistant recorded and what
/// they added here. Each can be edited or deleted.
struct DietaryConstraintsView: View {
    let profileID: UUID
    @State private var constraints: [DietaryConstraint] = []
    @State private var editing: DietaryConstraint?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                if constraints.isEmpty {
                    Text("No constraints yet. Add one, or tell the assistant, for example \"protein at most 20 g a day\" or \"no tomatoes\".")
                        .foregroundStyle(.secondary)
                }
                ForEach(constraints) { c in
                    Button { editing = c } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.summary).foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                Text(c.source.displayName)
                                if let note = c.note, !note.isEmpty { Text("· \(note)") }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets { DietaryConstraintStore.remove(id: constraints[i].id, for: profileID) }
                    reload()
                }
            } footer: {
                Text("The app checks your logged meals and plans against these and warns you. They are your own constraints; the app does not give medical advice and never changes a prescription.")
            }
        }
        .navigationTitle(Text("Dietary constraints"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Text("Close") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = DietaryConstraint(kind: .nutrientMax, nutrient: NutrientType.protein.rawValue, amount: 50, unit: "g")
                } label: { Label { Text("Add") } icon: { Image(systemName: "plus") } }
            }
        }
        .sheet(item: $editing) { c in
            NavigationStack {
                DietaryConstraintEditor(constraint: c) { saved in
                    var all = DietaryConstraintStore.constraints(for: profileID)
                    if let i = all.firstIndex(where: { $0.id == saved.id }) { all[i] = saved } else { all.append(saved) }
                    DietaryConstraintStore.save(all, for: profileID)
                    reload()
                }
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .dietaryConstraintsDidChange)) { _ in reload() }
    }

    private func reload() {
        constraints = DietaryConstraintStore.constraints(for: profileID)
    }
}

private struct DietaryConstraintEditor: View {
    @State var constraint: DietaryConstraint
    let onSave: (DietaryConstraint) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""

    init(constraint: DietaryConstraint, onSave: @escaping (DietaryConstraint) -> Void) {
        _constraint = State(initialValue: constraint)
        self.onSave = onSave
        _amountText = State(initialValue: constraint.amount.map(DietaryUnits.format) ?? "")
    }

    var body: some View {
        Form {
            Picker(selection: $constraint.kind) {
                Text("At most").tag(DietaryConstraint.Kind.nutrientMax)
                Text("At least").tag(DietaryConstraint.Kind.nutrientMin)
                Text("Avoid a food").tag(DietaryConstraint.Kind.excludeFood)
                Text("Prefer a food").tag(DietaryConstraint.Kind.preferFood)
            } label: { Text("Type") }

            if constraint.isNutrientRule {
                Picker(selection: Binding(
                    get: { constraint.nutrient ?? NutrientType.protein.rawValue },
                    set: {
                        constraint.nutrient = $0
                        constraint.unit = NutrientType(rawValue: $0).map(FoodItem.canonicalUnit(for:))
                    })) {
                    ForEach(DietaryNutrientNames.common, id: \.rawValue) { n in
                        Text(DietaryNutrientNames.displayName(n)).tag(n.rawValue)
                    }
                } label: { Text("Nutrient") }
                HStack {
                    TextField(String(localized: "Amount"), text: $amountText)
                        .keyboardType(.decimalPad)
                    Text(constraint.unit ?? constraint.nutrientType.map(FoodItem.canonicalUnit(for:)) ?? "g")
                        .foregroundStyle(.secondary)
                }
                Picker(selection: $constraint.period) {
                    Text("A day").tag(DietaryConstraint.Period.day)
                    Text("Per meal").tag(DietaryConstraint.Period.meal)
                } label: { Text("Period") }
            } else {
                TextField(String(localized: "Food, e.g. tomato"), text: Binding(
                    get: { constraint.foodTerm ?? "" },
                    set: { constraint.foodTerm = $0 }))
            }

            Picker(selection: $constraint.source) {
                ForEach(DietaryConstraint.Source.allCases, id: \.self) { s in
                    Text(s.displayName).tag(s)
                }
            } label: { Text("Source") }

            TextField(String(localized: "Note"), text: Binding(
                get: { constraint.note ?? "" },
                set: { constraint.note = $0.isEmpty ? nil : $0 }), axis: .vertical)
        }
        .navigationTitle(Text("Constraint"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Text("Cancel") }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    var c = constraint
                    if c.isNutrientRule {
                        c.amount = GlobalState.double(from: amountText) ?? Double(amountText)
                        if c.unit == nil { c.unit = c.nutrientType.map(FoodItem.canonicalUnit(for:)) }
                        c.foodTerm = nil
                    } else {
                        c.nutrient = nil; c.amount = nil; c.unit = nil
                    }
                    onSave(c)
                    dismiss()
                } label: { Text("Save") }
                .disabled({
                    var c = constraint
                    if c.isNutrientRule { c.amount = GlobalState.double(from: amountText) ?? Double(amountText) }
                    return !c.isValid
                }())
            }
        }
    }
}
