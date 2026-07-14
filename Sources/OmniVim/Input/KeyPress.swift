import AppKit
import Carbon.HIToolbox

struct KeyPress {
    let keyCode: CGKeyCode
    let character: String?
    let flags: CGEventFlags

    var isEscape: Bool { keyCode == kVK_Escape }
    var isBackspace: Bool { keyCode == kVK_Delete }
    var isControlF: Bool { keyCode == CGKeyCode(kVK_ANSI_F) && flags.contains(.maskControl) }
}
