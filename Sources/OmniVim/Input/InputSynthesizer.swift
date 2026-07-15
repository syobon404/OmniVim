import AppKit

@MainActor
final class InputSynthesizer {
    func sendKey(_ keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        var flags = CGEventFlags()
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
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
        diagnosticLog("mouse move x=\(point.x) y=\(point.y)")
    }

    @discardableResult
    func clickGlobal(at point: CGPoint, processIdentifier: pid_t? = nil) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = mouseEvent(source: source, type: .leftMouseDown, at: point)
        let up = mouseEvent(source: source, type: .leftMouseUp, at: point)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        diagnosticLog("mouse click x=\(point.x) y=\(point.y) targetPid=\(processIdentifier ?? 0) mode=global down=\(down != nil) up=\(up != nil)")
        return down != nil && up != nil
    }

    @discardableResult
    func clickTargeted(at point: CGPoint, processIdentifier: pid_t) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = mouseEvent(source: source, type: .leftMouseDown, at: point)
        let up = mouseEvent(source: source, type: .leftMouseUp, at: point)
        down?.postToPid(processIdentifier)
        diagnosticLog("mouse click x=\(point.x) y=\(point.y) targetPid=\(processIdentifier) mode=targeted phase=down created=\(down != nil)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            up?.postToPid(processIdentifier)
            diagnosticLog("mouse click x=\(point.x) y=\(point.y) targetPid=\(processIdentifier) mode=targeted phase=up created=\(up != nil)")
        }
        return down != nil && up != nil
    }

    private func mouseEvent(source: CGEventSource?, type: CGEventType, at point: CGPoint) -> CGEvent? {
        let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        event?.setIntegerValueField(.mouseEventClickState, value: 1)
        return event
    }

    private func markAsSynthesized(_ event: CGEvent?) {
        event?.setIntegerValueField(.eventSourceUserData, value: OmniVimInputEvent.synthesizedTag)
    }
}
