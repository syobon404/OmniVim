import AppKit
import Carbon.HIToolbox

enum KeyEventPhase: Equatable {
    case down
    case up
}

struct KeyPress {
    let keyCode: CGKeyCode
    let character: String?
    let flags: CGEventFlags
    let phase: KeyEventPhase
    let isRepeat: Bool

    init(
        keyCode: CGKeyCode,
        character: String?,
        flags: CGEventFlags,
        phase: KeyEventPhase = .down,
        isRepeat: Bool = false
    ) {
        self.keyCode = keyCode
        self.character = character
        self.flags = flags
        self.phase = phase
        self.isRepeat = isRepeat
    }

    var isEscape: Bool { keyCode == kVK_Escape }
    var isBackspace: Bool { keyCode == kVK_Delete }
    var isControlF: Bool { keyCode == CGKeyCode(kVK_ANSI_F) && flags.contains(.maskControl) }

    var hasChordModifier: Bool {
        !flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
    }
}

enum OmniVimInputEvent {
    static let synthesizedTag: Int64 = 0x4F4D4E4956494D
}

struct OrderedKeyChordDefinition: Equatable {
    let first: CGKeyCode
    let second: CGKeyCode
}

enum OrderedKeyChordResolution: Equatable {
    case passThrough
    case consume
    case trigger
    case replayFirst
    case replayFirstAndCurrent
}

struct OrderedKeyChord {
    private let definition: OrderedKeyChordDefinition
    private var firstIsPending = false
    private var suppressedKeyUps: Set<CGKeyCode> = []

    init(definition: OrderedKeyChordDefinition) {
        self.definition = definition
    }

    mutating func handle(_ key: KeyPress, enabled: Bool) -> OrderedKeyChordResolution {
        if key.phase == .up, suppressedKeyUps.remove(key.keyCode) != nil {
            return .consume
        }

        guard enabled else {
            firstIsPending = false
            return .passThrough
        }

        if firstIsPending {
            if key.phase == .up, key.keyCode == definition.first {
                firstIsPending = false
                return .replayFirst
            }

            guard key.phase == .down else { return .passThrough }
            firstIsPending = false

            if key.keyCode == definition.second, !key.hasChordModifier, !key.isRepeat {
                suppressedKeyUps.insert(definition.first)
                suppressedKeyUps.insert(definition.second)
                return .trigger
            }
            return .replayFirstAndCurrent
        }

        if key.phase == .down,
           key.keyCode == definition.first,
           !key.hasChordModifier,
           !key.isRepeat {
            firstIsPending = true
            return .consume
        }
        return .passThrough
    }

    mutating func resetPendingKey() {
        firstIsPending = false
    }
}
