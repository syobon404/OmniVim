import AppKit

struct RunningApplicationContext {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let activationPolicy: NSApplication.ActivationPolicy
    let accessibilityElement: AXUIElement
}

struct AdapterEnvironment {
    let application: RunningApplicationContext
    let capabilityReport: ApplicationCapabilityReport?

    init(
        application: RunningApplicationContext,
        capabilityReport: ApplicationCapabilityReport? = nil
    ) {
        self.application = application
        self.capabilityReport = capabilityReport
    }

    func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application.accessibilityElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
