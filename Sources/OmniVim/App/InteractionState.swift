enum BaseVimMode: Equatable {
    case normal
    case insert

    var label: String {
        switch self {
        case .normal: "NORMAL"
        case .insert: "INSERT"
        }
    }
}

enum InteractionState: Equatable {
    case normal
    case insert
    case hint(returnTo: BaseVimMode)

    var baseMode: BaseVimMode {
        switch self {
        case .normal: .normal
        case .insert: .insert
        case let .hint(returnTo): returnTo
        }
    }

    var label: String {
        switch self {
        case .normal: "NORMAL"
        case .insert: "INSERT"
        case .hint: "HINT"
        }
    }
}
