import AppKit

struct FocusedEditableElement {
    let processIdentifier: pid_t
    let element: AXUIElement
    let frame: CGRect?
    let prefersPersistentIndicator: Bool

    func matches(_ other: FocusedEditableElement) -> Bool {
        processIdentifier == other.processIdentifier && CFEqual(element, other.element)
    }
}

final class FocusDetector {
    var focusedEditableElement: FocusedEditableElement? {
        guard AXIsProcessTrusted(), let focusedApplication = focusedApplication() else { return nil }
        let appElement = focusedApplication.element
        var focused: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused)
        guard let focused = focused else { return nil }
        let element = focused as! AXUIElement
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        guard ["AXTextField", "AXTextArea", "AXSearchField", "AXTextView"].contains(role as? String) else {
            return nil
        }
        let runningApplication = NSRunningApplication(
            processIdentifier: focusedApplication.processIdentifier
        )
        return FocusedEditableElement(
            processIdentifier: focusedApplication.processIdentifier,
            element: element,
            frame: frame(of: element),
            prefersPersistentIndicator: runningApplication.map {
                $0.activationPolicy != .regular
            } ?? false
        )
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        let positionValue = positionRef as! AXValue
        let sizeValue = sizeRef as! AXValue
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func focusedApplication() -> (processIdentifier: pid_t, element: AXUIElement)? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApplication: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApplication
        )
        if result == .success, let focusedApplication {
            let appElement = focusedApplication as! AXUIElement
            var processIdentifier: pid_t = 0
            if AXUIElementGetPid(appElement, &processIdentifier) == .success {
                return (processIdentifier, appElement)
            }
        }

        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return (
            app.processIdentifier,
            AXUIElementCreateApplication(app.processIdentifier)
        )
    }
}
