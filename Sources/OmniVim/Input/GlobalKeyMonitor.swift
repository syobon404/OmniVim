import AppKit

final class GlobalKeyMonitor {
    var onKey: ((KeyPress) -> Bool)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        diagnosticLog("creating CGEventTap")
        NSLog("[OmniVim] creating CGEventTap")
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<GlobalKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            if type == .keyDown {
                let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                var length = 0
                var buffer = [UniChar](repeating: 0, count: 4)
                event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buffer)
                let chars = String(utf16CodeUnits: buffer, count: Int(length)).lowercased()
                diagnosticLog("keyDown code=\(code) chars=\(chars)")
                NSLog("[OmniVim] keyDown code=%d chars=%@", code, chars)
                let handled = monitor.onKey?(KeyPress(keyCode: code, character: chars, flags: event.flags)) ?? false
                if handled { return nil }
            }
            return Unmanaged.passUnretained(event)
        }
        let unmanaged = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: unmanaged
        )
        guard let tap else {
            diagnosticLog("ERROR CGEventTap creation failed")
            NSLog("[OmniVim] ERROR: CGEventTap creation failed; check Accessibility/Input Monitoring permission")
            return
        }
        diagnosticLog("CGEventTap created successfully")
        NSLog("[OmniVim] CGEventTap created successfully")
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}
