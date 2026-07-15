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
    private let keyMonitor = GlobalKeyMonitor()
    private let modeIndicator = ModeIndicatorController()
    private let configuration: ModeConfiguration
    private var exitChord: OrderedKeyChord
    private var vimEngine = VimEngine()
    private var state: InteractionState
    private var focusedEditor: FocusedEditableElement?
    private var focusTimer: Timer?

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
        let elements = scanner.elements()
        let filtered = searchOnly
            ? elements.filter { ["AXTextField", "AXTextArea", "AXSearchField"].contains($0.role) }
            : elements
        guard overlay.show(elements: filtered) else { return }
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
            showHints(searchOnly: false)
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
            let executorName: String
            let resultingMode: BaseVimMode?
            if focusedEditor?.isTerminalSurface == true {
                executorName = "terminal"
                resultingMode = terminalCommandExecutor.execute(command)
            } else {
                executorName = "synthetic"
                resultingMode = commandExecutor.execute(command)
            }
            guard let resultingMode else { return true }
            diagnosticLog("vim command=\(command) executor=\(executorName)")
            updateMode(resultingMode.interactionState, forcePresentation: true)
            return true
        }
    }

    private func selectTarget(_ target: UIElementHint) {
        finishHintMode()
        activator.activate(target)
    }

    private func finishHintMode() {
        guard case let .hint(returnTo) = state else { return }
        overlay.dismiss()
        updateMode(returnTo?.interactionState ?? .inactive)
    }

    private func synchronizeEditingSession() {
        if case .hint = state { return }
        guard let current = focus.focusedEditableElement else {
            if focusedEditor != nil || state != .inactive {
                focusedEditor = nil
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
            return
        }
        focusedEditor = current
        exitChord.resetPendingKey()
        vimEngine.cancelPending()
        let frameDescription = current.frame.map {
            "x=\(Int($0.minX)) y=\(Int($0.minY)) w=\(Int($0.width)) h=\(Int($0.height))"
        } ?? "unavailable"
        diagnosticLog(
            "focus editor pid=\(current.processIdentifier) "
                + "bundle=\(current.bundleIdentifier ?? "unknown") "
                + "terminal=\(current.isTerminalSurface) "
                + "persistentIndicator=\(current.prefersPersistentIndicator) "
                + "frame=\(frameDescription)"
        )
        updateMode(configuration.initialMode.interactionState, forcePresentation: true)
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
}
