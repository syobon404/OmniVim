import AppKit
import Darwin

@MainActor
final class InputSynthesizer {
    private let mouseEventSource = CGEventSource(stateID: .privateState)
    private let mouseClickDuration: TimeInterval = 0.2

    func sendKey(_ keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        var flags = CGEventFlags()
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        down?.flags = flags
        up?.flags = flags
        markAsSynthesized(down)
        markAsSynthesized(up)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    func sendKeyDown(_ key: KeyPress) {
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: true)
        event?.flags = key.flags
        event?.setIntegerValueField(.keyboardEventAutorepeat, value: key.isRepeat ? 1 : 0)
        markAsSynthesized(event)
        event?.post(tap: .cghidEventTap)
    }

    func moveMouse(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        diagnosticLog("mouse move x=\(point.x) y=\(point.y) method=warp")
    }

    @discardableResult
    func clickGlobal(at point: CGPoint, processIdentifier: pid_t? = nil) -> Bool {
        let down = mouseEvent(source: mouseEventSource, type: .leftMouseDown, at: point)
        let up = mouseEvent(source: mouseEventSource, type: .leftMouseUp, at: point)
        guard let down, let up else {
            diagnosticLog(
                "mouse click x=\(point.x) y=\(point.y) targetPid=\(processIdentifier ?? 0) "
                    + "mode=global created=false"
            )
            return false
        }
        down.post(tap: .cgSessionEventTap)
        usleep(1_000)
        diagnosticLog(
            "mouse click x=\(point.x) y=\(point.y) targetPid=\(processIdentifier ?? 0) "
                + "mode=global source=private phase=down posted=true"
        )
        usleep(useconds_t(mouseClickDuration * 1_000_000))
        up.post(tap: .cgSessionEventTap)
        usleep(1_000)
        diagnosticLog(
            "mouse click x=\(point.x) y=\(point.y) targetPid=\(processIdentifier ?? 0) "
                + "mode=global source=private phase=up posted=true"
        )
        return true
    }

    @discardableResult
    func clickTargeted(at point: CGPoint, processIdentifier: pid_t) -> Bool {
        let down = mouseEvent(source: mouseEventSource, type: .leftMouseDown, at: point)
        let up = mouseEvent(source: mouseEventSource, type: .leftMouseUp, at: point)
        guard let down, let up else {
            diagnosticLog(
                "mouse click x=\(point.x) y=\(point.y) targetPid=\(processIdentifier) "
                    + "mode=targeted created=false"
            )
            return false
        }
        down.postToPid(processIdentifier)
        usleep(1_000)
        diagnosticLog(
            "mouse click x=\(point.x) y=\(point.y) targetPid=\(processIdentifier) "
                + "mode=targeted source=private phase=down posted=true"
        )
        usleep(useconds_t(mouseClickDuration * 1_000_000))
        up.postToPid(processIdentifier)
        usleep(1_000)
        diagnosticLog(
            "mouse click x=\(point.x) y=\(point.y) targetPid=\(processIdentifier) "
                + "mode=targeted source=private phase=up posted=true"
        )
        return true
    }

    private func mouseEvent(source: CGEventSource?, type: CGEventType, at point: CGPoint) -> CGEvent? {
        let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        event?.flags = []
        return event
    }

    private func markAsSynthesized(_ event: CGEvent?) {
        event?.setIntegerValueField(.eventSourceUserData, value: OmniVimInputEvent.synthesizedTag)
    }
}
