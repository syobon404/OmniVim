import AppKit

struct EditorResolution {
    let handle: EditorHandle
    let frame: CGRect?
}

protocol EditorResolving {
    func resolve(in environment: AdapterEnvironment) -> EditorResolution?
}

protocol AdapterCommandExecuting {
    var identifier: String { get }
    var requiresTerminalSession: Bool { get }

    func allowsInput(terminalContext: TerminalProgramContext?) -> Bool
    @MainActor
    func execute(
        _ command: VimCommand,
        terminalContext: TerminalProgramContext?,
        services: CommandExecutionServices
    ) -> BaseVimMode?
    @MainActor
    func cancelPending(using services: CommandExecutionServices)
}

protocol AdapterHintProviding {
    var discoveryLimitation: HintDiscoveryLimitation? { get }
    @MainActor
    func hints(searchOnly: Bool, scanner: AccessibilityScanner) -> [UIElementHint]
}

enum HintDiscoveryLimitation: Hashable {
    case screenRecordingPermissionRequired(applicationName: String)
}

extension AdapterHintProviding {
    var discoveryLimitation: HintDiscoveryLimitation? { nil }
}

@MainActor
protocol AdapterElementActivating {
    func activate(_ target: UIElementHint, using activator: ElementActivator)
}

struct AdapterCapabilities {
    let editorResolver: any EditorResolving
    let commandExecutor: any AdapterCommandExecuting
    let hintProvider: any AdapterHintProviding
    let activator: any AdapterElementActivating

    init(
        editorResolver: any EditorResolving,
        commandExecutor: any AdapterCommandExecuting = SyntheticAdapterCommandExecutor(),
        hintProvider: any AdapterHintProviding = AccessibilityHintProvider(),
        activator: any AdapterElementActivating = AccessibilityElementActivator()
    ) {
        self.editorResolver = editorResolver
        self.commandExecutor = commandExecutor
        self.hintProvider = hintProvider
        self.activator = activator
    }
}
