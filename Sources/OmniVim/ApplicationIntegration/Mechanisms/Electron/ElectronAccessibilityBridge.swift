import AppKit

final class ElectronAccessibilityBridge {
    private var attemptedProcessIdentifiers: Set<pid_t> = []

    func enableIfNeeded(in environment: AdapterEnvironment) {
        let context = environment.application
        guard attemptedProcessIdentifiers.insert(context.processIdentifier).inserted else { return }
        let result = AXUIElementSetAttributeValue(
            context.accessibilityElement,
            "AXManualAccessibility" as CFString,
            true as CFTypeRef
        )
        diagnosticLog(
            "adapter accessibility mechanism=electron pid=\(context.processIdentifier) "
                + "bundle=\(context.bundleIdentifier ?? "unknown") result=\(result.rawValue)"
        )
    }
}

final class ElectronEditorResolver: EditorResolving {
    private let bridge: ElectronAccessibilityBridge
    private let fallback: any EditorResolving

    init(
        bridge: ElectronAccessibilityBridge = ElectronAccessibilityBridge(),
        fallback: any EditorResolving = CompositeEditorResolver(resolvers: [
            AXEditorResolver(),
            AXEditorResolver(allowsInference: true)
        ])
    ) {
        self.bridge = bridge
        self.fallback = fallback
    }

    func resolve(in environment: AdapterEnvironment) -> EditorResolution? {
        bridge.enableIfNeeded(in: environment)
        return fallback.resolve(in: environment)
    }
}
