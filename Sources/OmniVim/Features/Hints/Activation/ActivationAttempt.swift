import AppKit

enum ActivationMethod: String, Equatable {
    case focus
    case select
    case axPress
    case axPick
    case axShowMenu
    case globalMouse
    case targetedMouse
}

enum ActivationDispatchOutcome: Equatable {
    case accepted
    case rejected(code: Int)
    case unavailable

    var logValue: String {
        switch self {
        case .accepted: "accepted"
        case let .rejected(code): "rejected(\(code))"
        case .unavailable: "unavailable"
        }
    }
}

enum ActivationObservation: String, Equatable {
    case unknown
    case confirmed
    case unchanged
}

struct ActivationAttempt: Equatable {
    let activationID: String
    let method: ActivationMethod
    let dispatch: ActivationDispatchOutcome
    let observation: ActivationObservation

    var logMessage: String {
        "activation=\(activationID) method=\(method.rawValue) dispatch=\(dispatch.logValue) observation=\(observation.rawValue)"
    }
}

func activationMethod(forAXAction action: String) -> ActivationMethod? {
    if action == kAXPressAction as String { return .axPress }
    if action == kAXPickAction as String { return .axPick }
    if action == kAXShowMenuAction as String { return .axShowMenu }
    return nil
}

func activationDispatchOutcome(for error: AXError) -> ActivationDispatchOutcome {
    error == .success ? .accepted : .rejected(code: Int(error.rawValue))
}
