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
}

enum OmniVimInputEvent {
    static let synthesizedTag: Int64 = 0x4F4D4E4956494D
}
