import AppKit

@MainActor
final class OmniVimCoordinator {
    private let focus = FocusDetector()
    private let scanner = AccessibilityScanner()
    private let overlay = HintOverlayController()
    private let activator = ElementActivator()
    private let input = InputSynthesizer()
    private lazy var commandExecutor = SyntheticVimCommandExecutor(input: input)
    private lazy var terminalCommandExecutor = TerminalVimCommandExecutor(input: input)
    private lazy var readlineTUICommandExecutor = ReadlineTUIVimCommandExecutor(input: input)
    private lazy var commandExecutionServices = CommandExecutionServices(
        synthetic: commandExecutor,
        terminal: terminalCommandExecutor,
        readlineTUI: readlineTUICommandExecutor
    )
    private let terminalSessionResolver = TerminalSessionResolver()
    private let keyMonitor = GlobalKeyMonitor()
    private let modeIndicator = ModeIndicatorController()
    private let configuration: ModeConfiguration
    private var exitChord: OrderedKeyChord
    private var vimEngine = VimEngine()
    private var state: InteractionState
    private var focusedEditor: EditorTarget?
    private var activeHintActivator: (any AdapterElementActivating)?
    private var terminalProgramContext: TerminalProgramContext?
    private var terminalResolutionTask: Task<Void, Never>?
    private var lastTerminalResolutionDate = Date.distantPast
    private var focusTimer: Timer?
    private var acknowledgedHintLimitations: Set<HintDiscoveryLimitation> = []

    init(configuration: ModeConfiguration = ModeConfiguration()) {
        self.configuration = configuration
        self.exitChord = OrderedKeyChord(definition: configuration.insertExitChord)
        self.state = .inactive
        overlay.onTargetSelected = { [weak self] target in
            self?.selectTarget(target)
        }
    }

    func start() {
        updateMode(.inactive)
        diagnosticLog("coordinator start; AX trusted=\(AXIsProcessTrusted())")
        NSLog("[OmniVim] coordinator start; AX trusted=%@", AXIsProcessTrusted() ? "yes" : "no")
        keyMonitor.onKey = { [weak self] key in self?.handle(key) ?? false }
        keyMonitor.start()
        synchronizeEditingSession()
        startFocusMonitoring()
        let promptOptions = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(promptOptions) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showPermissionNotice()
            }
        }
    }

    func showHints(searchOnly: Bool) {
        if case .hint = state { return }
        exitChord.resetPendingKey()
        vimEngine.cancelPending()
        let applicationCapabilities = focus.focusedApplicationCapabilities
        let provider = applicationCapabilities?.hintProvider
            ?? focusedEditor?.capabilities.hintProvider
            ?? AccessibilityHintProvider()
        if !searchOnly,
           let limitation = provider.discoveryLimitation,
           !acknowledgedHintLimitations.contains(limitation),
           !resolveHintDiscoveryLimitation(limitation) {
            return
        }
        guard overlay.show(elements: provider.hints(searchOnly: searchOnly, scanner: scanner)) else {
            return
        }
        activeHintActivator = applicationCapabilities?.activator
            ?? focusedEditor?.capabilities.activator
        updateMode(.hint(returnTo: state.baseMode))
    }

    private func handle(_ key: KeyPress) -> Bool {
        if case .hint = state {
            guard key.phase == .down else { return true }
            if key.isEscape, state.consumesEscape { finishHintMode(); return true }
            if key.isBackspace {
                if !overlay.popPrefix() { finishHintMode() }
                return true
            }
            if let character = key.character, let target = overlay.push(character) {
                selectTarget(target)
            }
            return true
        }

        synchronizeEditingSession()

        if let focusedEditor,
           !focusedEditor.capabilities.commandExecutor.allowsInput(
               terminalContext: terminalProgramContext
           ) {
            return false
        }

        switch exitChord.handle(key, enabled: state == .insert && focusedEditor != nil) {
        case .passThrough:
            break
        case .consume:
            return true
        case .trigger:
            updateMode(.normal)
            return true
        case .replayFirst:
            input.sendKey(configuration.insertExitChord.first)
            return true
        case .replayFirstAndCurrent:
            input.sendKey(configuration.insertExitChord.first)
            input.sendKeyDown(key)
            return true
        }

        guard key.phase == .down else { return false }
        if key.isEscape {
            if vimEngine.cancelPending() { presentMode() }
            return false
        }
        if key.isControlF {
            vimEngine.cancelPending()
            diagnosticLog("hint discovery scheduled")
            DispatchQueue.main.async { [weak self] in
                self?.showHints(searchOnly: false)
            }
            return true
        }
        guard state == .normal, focusedEditor != nil else { return false }

        if key.flags.contains(.maskCommand)
            || key.flags.contains(.maskControl)
            || key.flags.contains(.maskAlternate) {
            if vimEngine.cancelPending() { presentMode() }
            return false
        }

        switch vimEngine.handle(character: key.character) {
        case .passThrough:
            return false
        case .consume:
            presentMode()
            return true
        case let .pending(vimOperator):
            diagnosticLog("operator pending=\(vimOperator.indicatorLabel)")
            presentMode()
            return true
        case let .execute(command):
            guard let focusedEditor else { return false }
            let executor = focusedEditor.capabilities.commandExecutor
            let resultingMode = executor.execute(
                command,
                terminalContext: terminalProgramContext,
                services: commandExecutionServices
            )
            guard let resultingMode else { return true }
            diagnosticLog("vim command=\(command) executor=\(executor.identifier)")
            updateMode(resultingMode.interactionState, forcePresentation: true)
            return true
        }
    }

    private func selectTarget(_ target: UIElementHint) {
        let targetActivator = activeHintActivator ?? focusedEditor?.capabilities.activator
        finishHintMode()
        (targetActivator ?? AccessibilityElementActivator()).activate(target, using: activator)
    }

    private func finishHintMode() {
        guard case let .hint(returnTo) = state else { return }
        overlay.dismiss()
        activeHintActivator = nil
        updateMode(returnTo?.interactionState ?? .inactive)
    }

    private func synchronizeEditingSession() {
        if case .hint = state { return }
        guard let current = focus.focusedEditorTarget else {
            if focusedEditor != nil || state != .inactive {
                if let focusedEditor {
                    focusedEditor.capabilities.commandExecutor.cancelPending(
                        using: commandExecutionServices
                    )
                }
                focusedEditor = nil
                terminalProgramContext = nil
                terminalResolutionTask?.cancel()
                terminalResolutionTask = nil
                exitChord.resetPendingKey()
                vimEngine.cancelPending()
                updateMode(.inactive)
            }
            return
        }

        if let focusedEditor, focusedEditor.matches(current) {
            if focusedEditor.frame != current.frame {
                self.focusedEditor = current
                modeIndicator.reposition(anchorAXFrame: current.frame)
            }
            requestTerminalResolutionIfNeeded(for: current)
            return
        }
        terminalResolutionTask?.cancel()
        terminalResolutionTask = nil
        terminalProgramContext = nil
        focusedEditor = current
        exitChord.resetPendingKey()
        vimEngine.cancelPending()
        let frameDescription = current.frame.map {
            "x=\(Int($0.minX)) y=\(Int($0.minY)) w=\(Int($0.width)) h=\(Int($0.height))"
        } ?? "unavailable"
        diagnosticLog(
            "focus editor pid=\(current.processIdentifier) "
                + "bundle=\(current.bundleIdentifier ?? "unknown") "
                + "adapter=\(current.adapterIdentifier) "
                + "executor=\(current.capabilities.commandExecutor.identifier) "
                + "persistentIndicator=\(current.prefersPersistentIndicator) "
                + "frame=\(frameDescription)"
        )
        if current.capabilities.commandExecutor.requiresTerminalSession {
            current.capabilities.commandExecutor.cancelPending(using: commandExecutionServices)
            updateMode(.inactive, forcePresentation: true)
            requestTerminalResolutionIfNeeded(for: current, force: true)
        } else {
            updateMode(configuration.initialMode.interactionState, forcePresentation: true)
        }
    }

    private func requestTerminalResolutionIfNeeded(
        for editor: EditorTarget,
        force: Bool = false
    ) {
        guard editor.capabilities.commandExecutor.requiresTerminalSession,
              terminalResolutionTask == nil else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastTerminalResolutionDate) >= 0.4 else { return }
        lastTerminalResolutionDate = now
        let processIdentifier = editor.processIdentifier
        let bundleIdentifier = editor.bundleIdentifier

        terminalResolutionTask = Task { [weak self] in
            guard let self else { return }
            let context = await terminalSessionResolver.resolve(
                bundleIdentifier: bundleIdentifier,
                terminalProcessIdentifier: processIdentifier
            )
            guard !Task.isCancelled else { return }
            terminalResolutionTask = nil
            applyTerminalProgramContext(context, expectedTerminalPID: processIdentifier)
        }
    }

    private func applyTerminalProgramContext(
        _ context: TerminalProgramContext?,
        expectedTerminalPID: pid_t
    ) {
        guard let focusedEditor,
              focusedEditor.capabilities.commandExecutor.requiresTerminalSession,
              focusedEditor.processIdentifier == expectedTerminalPID,
              terminalProgramContext != context else { return }

        terminalProgramContext = context
        exitChord.resetPendingKey()
        vimEngine.cancelPending()

        if context?.behavior != .shellPrompt {
            focusedEditor.capabilities.commandExecutor.cancelPending(using: commandExecutionServices)
        }

        if let context {
            diagnosticLog(
                "terminal session window=\(context.identity.windowIdentifier) "
                    + "foregroundPid=\(context.identity.foregroundProcessIdentifier) "
                    + "executable=\(context.executableName) "
                    + "behavior=\(context.behavior)"
            )
        } else {
            diagnosticLog("terminal session unresolved pid=\(expectedTerminalPID) behavior=passThrough")
        }

        let nextState = context?.behavior.allowsOmniVim == true
            ? configuration.initialMode.interactionState
            : .inactive
        updateMode(nextState, forcePresentation: true)
    }

    private func startFocusMonitoring() {
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.synchronizeEditingSession()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        focusTimer = timer
    }

    private func updateMode(_ newState: InteractionState, forcePresentation: Bool = false) {
        guard state != newState else {
            if forcePresentation {
                modeIndicator.update(
                    newState,
                    anchorAXFrame: focusedEditor?.frame,
                    persistentInsert: focusedEditor?.prefersPersistentIndicator == true,
                    pendingOperator: vimEngine.pendingOperator
                )
            }
            return
        }
        state = newState
        modeIndicator.update(
            newState,
            anchorAXFrame: focusedEditor?.frame,
            persistentInsert: focusedEditor?.prefersPersistentIndicator == true,
            pendingOperator: vimEngine.pendingOperator
        )
        diagnosticLog("mode=\(newState.label)")
    }

    private func presentMode() {
        modeIndicator.update(
            state,
            anchorAXFrame: focusedEditor?.frame,
            persistentInsert: focusedEditor?.prefersPersistentIndicator == true,
            pendingOperator: vimEngine.pendingOperator
        )
    }

    private func showPermissionNotice() {
        let alert = NSAlert()
        alert.messageText = "OmniVim needs Accessibility access"
        alert.informativeText = "Allow OmniVim in System Settings → Privacy & Security → Accessibility to read focus, inspect UI elements, and receive global shortcuts."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    private func resolveHintDiscoveryLimitation(_ limitation: HintDiscoveryLimitation) -> Bool {
        switch limitation {
        case let .screenRecordingPermissionRequired(applicationName):
            let alert = NSAlert()
            alert.messageText = "Enable full UI hints for \(applicationName)"
            alert.informativeText = "\(applicationName) does not expose its main interface through macOS Accessibility. OmniVim needs Screen Recording access to discover visible rows and controls. Screenshots are processed locally and are not saved."
            alert.addButton(withTitle: "Request Access")
            alert.addButton(withTitle: "Continue with Limited Hints")
            alert.addButton(withTitle: "Cancel")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let granted = CGRequestScreenCaptureAccess()
                diagnosticLog("screen capture permission requested from hint discovery granted=\(granted)")
                if !granted {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                    )
                }
                return granted
            case .alertSecondButtonReturn:
                acknowledgedHintLimitations.insert(limitation)
                diagnosticLog("hint discovery limitation acknowledged application=\(applicationName)")
                return true
            default:
                diagnosticLog("hint discovery cancelled application=\(applicationName)")
                return false
            }
        }
    }
}
