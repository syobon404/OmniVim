import AppKit
import XCTest
@testable import OmniVim

final class ApplicationAdapterTests: XCTestCase {
    func testTerminalAdapterRecognizesOnlyTerminalBundles() {
        let adapter = TerminalApplicationAdapter()

        XCTAssertTrue(adapter.matches(applicationContext("net.kovidgoyal.kitty")))
        XCTAssertTrue(adapter.matches(applicationContext("com.apple.Terminal")))
        XCTAssertFalse(adapter.matches(applicationContext("com.apple.Notes")))
        XCTAssertFalse(adapter.matches(applicationContext(nil)))
    }

    func testRegistrySelectsAppSpecificAdapters() {
        let registry = ApplicationAdapterRegistry()
        let adapters = [
            ("com.openai.codex", "codex"),
            ("com.tencent.xinWeChat", "wechat"),
            ("com.electron.lark", "lark"),
            ("ru.keepcoder.Telegram", "telegram")
        ]

        for (bundleIdentifier, expectedIdentifier) in adapters {
            XCTAssertEqual(
                registry.adapter(for: applicationContext(bundleIdentifier)).identifier,
                expectedIdentifier
            )
        }
    }

    func testCodexOwnsTargetedMouseActivationCapability() {
        let environment = adapterEnvironment("com.openai.codex")
        let adapter = ApplicationAdapterRegistry().adapter(for: environment.application)
        let capabilities = adapter.capabilities(for: environment)

        XCTAssertTrue(capabilities.activator is TargetedMouseElementActivator)
    }

    func testLarkOwnsElectronAccessibilityCapability() {
        let environment = adapterEnvironment("com.electron.lark")
        let adapter = ApplicationAdapterRegistry().adapter(for: environment.application)
        let capabilities = adapter.capabilities(for: environment)

        XCTAssertTrue(capabilities.editorResolver is ElectronEditorResolver)
        XCTAssertEqual(capabilities.commandExecutor.identifier, "synthetic")
    }

    func testTelegramOwnsHitTestHintDiscoveryCapability() {
        let environment = adapterEnvironment("ru.keepcoder.Telegram")
        let adapter = ApplicationAdapterRegistry().adapter(for: environment.application)
        let capabilities = adapter.capabilities(for: environment)

        let provider = capabilities.hintProvider as? GPAHintProvider
        XCTAssertEqual(provider?.configuration, .telegram)
        XCTAssertTrue(capabilities.activator is CoordinateElementActivator)
    }

    func testTelegramReportsScreenRecordingLimitationWhenVisualCaptureIsUnavailable() {
        let provider = GPAHintProvider(
            configuration: .telegram,
            hasScreenCaptureAccess: { false }
        )

        XCTAssertEqual(
            provider.discoveryLimitation,
            .screenRecordingPermissionRequired(applicationName: "Telegram")
        )
    }

    func testTelegramHasNoHintDiscoveryLimitationWhenVisualCaptureIsAvailable() {
        let provider = GPAHintProvider(
            configuration: .telegram,
            hasScreenCaptureAccess: { true }
        )

        XCTAssertNil(provider.discoveryLimitation)
    }

    func testWeChatOwnsVisualHintDiscoveryAndCoordinateActivation() {
        let environment = adapterEnvironment("com.tencent.xinWeChat")
        let adapter = ApplicationAdapterRegistry().adapter(for: environment.application)
        let capabilities = adapter.capabilities(for: environment)

        let provider = capabilities.hintProvider as? GPAHintProvider
        XCTAssertEqual(provider?.configuration, .weChat)
        XCTAssertTrue(capabilities.activator is CoordinateElementActivator)
    }

    func testWeChatReportsScreenRecordingLimitationWhenVisualCaptureIsUnavailable() {
        let provider = GPAHintProvider(
            configuration: .weChat,
            hasScreenCaptureAccess: { false }
        )

        XCTAssertEqual(
            provider.discoveryLimitation,
            .screenRecordingPermissionRequired(applicationName: "WeChat")
        )
    }

    func testHitTestCandidateAcceptsActionableUnknownRole() {
        XCTAssertTrue(isAXHitTestHintCandidate(
            role: "AXGroup",
            subrole: "",
            actions: [kAXPressAction as String]
        ))
        XCTAssertFalse(isAXHitTestHintCandidate(
            role: "AXStaticText",
            subrole: "",
            actions: []
        ))
        XCTAssertFalse(isAXHitTestHintCandidate(
            role: "AXButton",
            subrole: "AXCloseButton",
            actions: [kAXPressAction as String]
        ))
    }

    func testHitTestSamplingGridStaysInsideFrameAndHonorsLimit() {
        let frame = CGRect(x: 100, y: 200, width: 80, height: 60)
        let points = AXHitTestSamplingGrid.points(in: frame, step: 10, limit: 20)

        XCTAssertEqual(points.count, 20)
        XCTAssertTrue(points.allSatisfy(frame.contains))
    }

    func testRegistryFallsBackToGenericAXCapabilities() {
        let environment = adapterEnvironment("com.apple.Notes")
        let adapter = ApplicationAdapterRegistry().adapter(for: environment.application)
        let capabilities = adapter.capabilities(for: environment)

        XCTAssertEqual(adapter.identifier, "generic-ax")
        XCTAssertTrue(capabilities.editorResolver is AXEditorResolver)
        XCTAssertEqual(capabilities.commandExecutor.identifier, "synthetic")
    }

    func testTerminalAdapterSelectsTerminalCommandCapability() {
        let environment = adapterEnvironment("net.kovidgoyal.kitty")
        let adapter = ApplicationAdapterRegistry().adapter(for: environment.application)
        let capabilities = adapter.capabilities(for: environment)

        XCTAssertEqual(adapter.identifier, "terminal")
        XCTAssertEqual(capabilities.commandExecutor.identifier, "terminal")
        XCTAssertTrue(capabilities.commandExecutor.requiresTerminalSession)
    }

    func testEditorTargetIdentityBelongsToSpecificEditor() {
        let firstElement = AXUIElementCreateApplication(10)
        let sameElement = AXUIElementCreateApplication(10)
        let otherElement = AXUIElementCreateApplication(11)
        let first = editorTarget(element: firstElement, processIdentifier: 10)

        XCTAssertTrue(first.matches(editorTarget(
            element: sameElement,
            processIdentifier: 10
        )))
        XCTAssertFalse(first.matches(editorTarget(
            element: otherElement,
            processIdentifier: 11
        )))
    }

    func testAXEditableRolePolicyAlwaysAcceptsStandardTextRoles() {
        XCTAssertTrue(AXEditableRolePolicy.accepts(
            role: "AXTextArea",
            isEditable: false,
            allowsInference: false
        ))
    }

    func testAXEditableRolePolicyRequiresExplicitInference() {
        XCTAssertTrue(AXEditableRolePolicy.accepts(
            role: "AXGroup",
            isEditable: true,
            allowsInference: true
        ))
        XCTAssertFalse(AXEditableRolePolicy.accepts(
            role: "AXGroup",
            isEditable: true,
            allowsInference: false
        ))
        XCTAssertFalse(AXEditableRolePolicy.accepts(
            role: "AXGroup",
            isEditable: false,
            allowsInference: true
        ))
    }

    private func applicationContext(_ bundleIdentifier: String?) -> RunningApplicationContext {
        adapterEnvironment(bundleIdentifier).application
    }

    private func adapterEnvironment(_ bundleIdentifier: String?) -> AdapterEnvironment {
        AdapterEnvironment(application: RunningApplicationContext(
            processIdentifier: 1,
            bundleIdentifier: bundleIdentifier,
            activationPolicy: .regular,
            accessibilityElement: AXUIElementCreateApplication(1)
        ))
    }

    private func editorTarget(
        element: AXUIElement,
        processIdentifier: pid_t
    ) -> EditorTarget {
        EditorTarget(
            processIdentifier: processIdentifier,
            bundleIdentifier: "test.editor",
            adapterIdentifier: "generic-ax",
            capabilities: AdapterCapabilities(editorResolver: AXEditorResolver()),
            handle: .accessibility(element),
            frame: nil,
            prefersPersistentIndicator: false
        )
    }
}
