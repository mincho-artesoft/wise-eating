import SwiftUI
import SwiftData

struct PromptEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var effectManager = EffectManager.shared

    let promptType: PromptType
    let onDismiss: (Prompt?) -> Void

    // НОВО: Свойство за съхранение на промпта за редакция
    let promptToEdit: Prompt?
    private var isEditing: Bool { promptToEdit != nil }

    @State private var text: String

    private var isSaveDisabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // Актуализиран инициализатор, който приема опционален promptToEdit
    init(promptType: PromptType, promptToEdit: Prompt? = nil, onDismiss: @escaping (Prompt?) -> Void) {
        self.promptType = promptType
        self.promptToEdit = promptToEdit
        self.onDismiss = onDismiss
        
        // Задаваме първоначалната стойност на текста
        if let prompt = promptToEdit {
            _text = State(initialValue: prompt.text)
        } else {
            _text = State(initialValue: "")
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ThemeBackgroundView().ignoresSafeArea()

                VStack(spacing: 0) {
                    // Toolbar
                    HStack {
                        Button("Cancel") { onDismiss(nil) }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .glassCardStyle(cornerRadius: 20)

                        Spacer()
                        // Динамично заглавие
                        Text(isEditing ? "Edit Prompt" : "New Prompt").font(.headline)
                        Spacer()

                        // Динамичен текст на бутона
                        Button(isEditing ? "Update" : "Save", action: savePrompt)
                            .disabled(isSaveDisabled)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .glassCardStyle(cornerRadius: 20)
                            .foregroundStyle(isSaveDisabled ? effectManager.currentGlobalAccentColor.opacity(0.4) : effectManager.currentGlobalAccentColor)
                    }
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                    .padding()

                    // Text Editor (остава без промяна)
                    VStack {
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $text)
                                .scrollContentBackground(.hidden)
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                                .onChange(of: text) { _, newValue in
                                    let allowed = newValue.unicodeScalars.filter { s in
                                        (0x20...0x7E).contains(Int(s.value)) || s == "\n" || s == "\t"
                                    }
                                    let filtered = String(String.UnicodeScalarView(allowed))
                                    if filtered != newValue { text = filtered }
                                }

                            if text.isEmpty {
                                Text("Generate a vegan weekly menu")
                                    .font(.body)
                                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.45))
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                        .padding()
                    }
                    .glassCardStyle(cornerRadius: 20)
                    .padding()
                    .frame(height: geometry.size.height * 0.8)

                    Spacer()
                }
            }
            .navigationBarBackButtonHidden(true)
        }
    }

    /// Актуализирана функция за запис, която обработва и двата случая
    private func savePrompt() {
        if let prompt = promptToEdit {
            // РЕЖИМ РЕДАКЦИЯ: Променяме текста на съществуващия обект
            prompt.text = text
            // SwiftData ще запази промените автоматично при следващия save cycle,
            // но ние извикваме onDismiss, за да затворим екрана.
            onDismiss(prompt)
        } else {
            // РЕЖИМ СЪЗДАВАНЕ: Създаваме нов обект
            let newPrompt = Prompt(text: text, type: promptType)
            modelContext.insert(newPrompt)
            do {
                try modelContext.save()
                onDismiss(newPrompt)
            } catch {
                print("Failed to save new prompt: \(error)")
                onDismiss(nil)
            }
        }
    }
}
