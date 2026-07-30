enum ThemeEditorState: Identifiable {
    case new
    case edit(Theme)
    
    var id: String {
        switch self {
        case .new:
            return "new"
        case .edit(let theme):
            return theme.id.uuidString
        }
    }
}
