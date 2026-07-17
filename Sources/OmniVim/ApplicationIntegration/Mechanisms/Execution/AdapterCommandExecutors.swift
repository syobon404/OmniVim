import AppKit

@MainActor
struct CommandExecutionServices {
    let synthetic: SyntheticVimCommandExecutor
    let terminal: TerminalVimCommandExecutor
    let readlineTUI: ReadlineTUIVimCommandExecutor
}

struct SyntheticAdapterCommandExecutor: AdapterCommandExecuting {
    let identifier = "synthetic"
    let requiresTerminalSession = false

    func allowsInput(terminalContext: TerminalProgramContext?) -> Bool { true }

    @MainActor
    func execute(
        _ command: VimCommand,
        terminalContext: TerminalProgramContext?,
        services: CommandExecutionServices
    ) -> BaseVimMode? {
        services.synthetic.execute(command)
    }

    @MainActor
    func cancelPending(using services: CommandExecutionServices) {}
}

struct TerminalAdapterCommandExecutor: AdapterCommandExecuting {
    let identifier = "terminal"
    let requiresTerminalSession = true

    func allowsInput(terminalContext: TerminalProgramContext?) -> Bool {
        terminalContext?.behavior.allowsOmniVim == true
    }

    @MainActor
    func execute(
        _ command: VimCommand,
        terminalContext: TerminalProgramContext?,
        services: CommandExecutionServices
    ) -> BaseVimMode? {
        switch terminalContext?.behavior {
        case .shellPrompt:
            services.terminal.execute(command)
        case .adaptedTUI(.readlineTUI):
            services.readlineTUI.execute(command)
        case .nativeModal, .passThrough, nil:
            nil
        }
    }

    @MainActor
    func cancelPending(using services: CommandExecutionServices) {
        services.terminal.cancelPendingCommand()
    }
}

struct AccessibilityHintProvider: AdapterHintProviding {
    @MainActor
    func hints(searchOnly: Bool, scanner: AccessibilityScanner) -> [UIElementHint] {
        let elements = scanner.elements()
        guard searchOnly else { return elements }
        return elements.filter {
            ["AXTextField", "AXTextArea", "AXSearchField"].contains($0.role)
        }
    }
}

struct AccessibilityElementActivator: AdapterElementActivating {
    @MainActor
    func activate(_ target: UIElementHint, using activator: ElementActivator) {
        activator.activate(target)
    }
}

struct TargetedMouseElementActivator: AdapterElementActivating {
    @MainActor
    func activate(_ target: UIElementHint, using activator: ElementActivator) {
        activator.activate(target, targetedMouseConfirmation: true)
    }
}

struct CoordinateElementActivator: AdapterElementActivating {
    @MainActor
    func activate(_ target: UIElementHint, using activator: ElementActivator) {
        activator.activateByMouse(target)
    }
}
