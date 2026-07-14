import AppKit
import Carbon.HIToolbox

@MainActor
final class OmniVimCoordinator {
    private let focus = FocusDetector()
    private let scanner = AccessibilityScanner()
    private let overlay = HintOverlayController()
    private let activator = ElementActivator()
    private let input = InputSynthesizer()
    private let keyMonitor = GlobalKeyMonitor()
    private let modeIndicator = ModeIndicatorController()
    private var state: InteractionState = .normal

    init() {
        overlay.onTargetSelected = { [weak self] target in
            self?.selectTarget(target)
        }
    }

    func start() {
        updateMode(.normal)
        diagnosticLog("coordinator start; AX trusted=\(AXIsProcessTrusted())")
        NSLog("[OmniVim] coordinator start; AX trusted=%@", AXIsProcessTrusted() ? "yes" : "no")
        keyMonitor.onKey = { [weak self] key in self?.handle(key) ?? false }
        keyMonitor.start()
        let promptOptions = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(promptOptions) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showPermissionNotice()
            }
        }
    }

    func showHints(searchOnly: Bool) {
        if case .hint = state { return }
        let elements = scanner.elements()
        let filtered = searchOnly
            ? elements.filter { ["AXTextField", "AXTextArea", "AXSearchField"].contains($0.role) }
            : elements
        guard overlay.show(elements: filtered) else { return }
        updateMode(.hint(returnTo: state.baseMode))
    }

    private func handle(_ key: KeyPress) -> Bool {
        if case .hint = state {
            if key.isEscape { finishHintMode(); return true }
            if key.isBackspace {
                if !overlay.popPrefix() { finishHintMode() }
                return true
            }
            if let character = key.character, let target = overlay.push(character) {
                selectTarget(target)
            }
            return true
        }

        if key.isEscape { updateMode(.normal); return true }
        if key.isControlF { showHints(searchOnly: false); return true }
        guard state == .normal, focus.isEditableFocused else { return false }

        switch key.character {
        case "i", "a": updateMode(.insert); return true
        case "h": input.sendKey(CGKeyCode(kVK_LeftArrow))
        case "j": input.sendKey(CGKeyCode(kVK_DownArrow))
        case "k": input.sendKey(CGKeyCode(kVK_UpArrow))
        case "l": input.sendKey(CGKeyCode(kVK_RightArrow))
        case "w": input.sendKey(CGKeyCode(kVK_RightArrow), modifiers: [.option])
        case "b": input.sendKey(CGKeyCode(kVK_LeftArrow), modifiers: [.option])
        case "0": input.sendKey(CGKeyCode(kVK_LeftArrow))
        case "$": input.sendKey(CGKeyCode(kVK_RightArrow), modifiers: [.command])
        default:
            return key.character != nil
                && !key.flags.contains(.maskCommand)
                && !key.flags.contains(.maskControl)
                && !key.flags.contains(.maskAlternate)
        }
        return true
    }

    private func selectTarget(_ target: UIElementHint) {
        finishHintMode()
        activator.activate(target)
    }

    private func finishHintMode() {
        guard case let .hint(returnTo) = state else { return }
        overlay.dismiss()
        updateMode(returnTo == .normal ? .normal : .insert)
    }

    private func updateMode(_ newState: InteractionState) {
        state = newState
        modeIndicator.update(newState.label)
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
