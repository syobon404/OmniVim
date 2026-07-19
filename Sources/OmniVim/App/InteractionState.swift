enum InteractionState: Equatable {
    case inactive
    case normal
    case insert
    case hint(returnTo: BaseVimMode?)

    var baseMode: BaseVimMode? {
        switch self {
        case .inactive: nil
        case .normal: .normal
        case .insert: .insert
        case let .hint(returnTo): returnTo
        }
    }

    var label: String {
        switch self {
        case .inactive: "INACTIVE"
        case .normal: "NORMAL"
        case .insert: "INSERT"
        case .hint: "HINT"
        }
    }

    var consumesEscape: Bool {
        if case .hint = self { return true }
        return false
    }
}
