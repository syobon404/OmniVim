import Carbon.HIToolbox

enum BaseVimMode: Equatable {
    case normal
    case insert

    var label: String {
        switch self {
        case .normal: "NORMAL"
        case .insert: "INSERT"
        }
    }

    var interactionState: InteractionState {
        switch self {
        case .normal: .normal
        case .insert: .insert
        }
    }
}

struct ModeConfiguration: Equatable {
    var initialMode: BaseVimMode = .insert
    var insertExitChord = OrderedKeyChordDefinition(
        first: CGKeyCode(kVK_ANSI_J),
        second: CGKeyCode(kVK_ANSI_K)
    )
}
