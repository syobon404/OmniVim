enum VimOperator: Equatable {
    case delete
    case change

    var indicatorLabel: String {
        switch self {
        case .delete: "DELETE…"
        case .change: "CHANGE…"
        }
    }

    var indicatorGlyph: String {
        switch self {
        case .delete: "D"
        case .change: "C"
        }
    }
}

enum VimMotion: Equatable {
    case characterLeft
    case characterRight
    case lineDown
    case lineUp
    case wordForward
    case wordBackward
    case lineStart
    case lineEnd
    case wholeLine
}

enum VimCommand: Equatable {
    case move(VimMotion)
    case operate(VimOperator, VimMotion)
    case enterInsert
}

enum VimResolution: Equatable {
    case passThrough
    case consume
    case pending(VimOperator)
    case execute(VimCommand)
}

struct VimEngine {
    private(set) var pendingOperator: VimOperator?

    mutating func handle(character: String?) -> VimResolution {
        guard let character, !character.isEmpty else { return .passThrough }

        if let pendingOperator {
            self.pendingOperator = nil
            if operatorForCharacter(character) == pendingOperator {
                return .execute(.operate(pendingOperator, .wholeLine))
            }
            if let motion = motionForCharacter(character) {
                return .execute(.operate(pendingOperator, motion))
            }
            return .consume
        }

        if let pendingOperator = operatorForCharacter(character) {
            self.pendingOperator = pendingOperator
            return .pending(pendingOperator)
        }
        if character == "i" || character == "a" {
            return .execute(.enterInsert)
        }
        if let motion = motionForCharacter(character) {
            return .execute(.move(motion))
        }
        return .consume
    }

    @discardableResult
    mutating func cancelPending() -> Bool {
        let hadPendingOperator = pendingOperator != nil
        pendingOperator = nil
        return hadPendingOperator
    }

    private func operatorForCharacter(_ character: String) -> VimOperator? {
        switch character {
        case "d": .delete
        case "c": .change
        default: nil
        }
    }

    private func motionForCharacter(_ character: String) -> VimMotion? {
        switch character {
        case "h": .characterLeft
        case "j": .lineDown
        case "k": .lineUp
        case "l": .characterRight
        case "w": .wordForward
        case "b": .wordBackward
        case "0": .lineStart
        case "$": .lineEnd
        default: nil
        }
    }
}
