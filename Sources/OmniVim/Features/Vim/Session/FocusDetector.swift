import AppKit

final class FocusDetector {
    private let integrationRuntime: ApplicationIntegrationRuntime

    init(integrationRuntime: ApplicationIntegrationRuntime = ApplicationIntegrationRuntime()) {
        self.integrationRuntime = integrationRuntime
    }

    var focusedEditorTarget: EditorTarget? {
        guard let integration = focusedApplicationIntegration else { return nil }
        let context = integration.environment.application
        guard let resolution = integration.capabilities.editorResolver.resolve(
            in: integration.environment
        ) else { return nil }

        return EditorTarget(
            processIdentifier: context.processIdentifier,
            bundleIdentifier: context.bundleIdentifier,
            adapterIdentifier: integration.adapterIdentifier,
            capabilities: integration.capabilities,
            handle: resolution.handle,
            frame: resolution.frame,
            prefersPersistentIndicator: context.activationPolicy != .regular
        )
    }

    var focusedApplicationCapabilities: AdapterCapabilities? {
        focusedApplicationIntegration?.capabilities
    }

    private var focusedApplicationIntegration: ApplicationIntegrationResolution? {
        guard AXIsProcessTrusted(), let focusedApplication = focusedApplication() else { return nil }
        let runningApplication = NSRunningApplication(
            processIdentifier: focusedApplication.processIdentifier
        )
        let context = RunningApplicationContext(
            processIdentifier: focusedApplication.processIdentifier,
            bundleIdentifier: runningApplication?.bundleIdentifier,
            activationPolicy: runningApplication?.activationPolicy ?? .regular,
            accessibilityElement: focusedApplication.element
        )
        return integrationRuntime.resolve(context: context)
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
