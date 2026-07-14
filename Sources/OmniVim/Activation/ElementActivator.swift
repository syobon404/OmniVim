import AppKit

@MainActor
final class ElementActivator {
    private let ax: AXService
    private let input: InputSynthesizer

    init(ax: AXService = AXService(), input: InputSynthesizer = InputSynthesizer()) {
        self.ax = ax
        self.input = input
    }

    func activate(_ target: UIElementHint) {
        diagnosticLog("activate role=\(target.role) subrole=\(target.subrole) title=\(target.title)")
        if editableRoles.contains(target.role) {
            let result = ax.setFocused(target.element)
            diagnosticLog("AX focus role=\(target.role) title=\(target.title) result=\(result.rawValue)")
        } else if clickableRoles.contains(target.role) {
            activateClickable(target)
        } else {
            let result = ax.perform(kAXPressAction as String, on: target.element)
            if result != .success {
                input.clickGlobal(at: center(of: target.frame), processIdentifier: target.processIdentifier)
            }
        }
    }

    private var editableRoles: Set<String> {
        ["AXTextField", "AXTextArea", "AXSearchField"]
    }

    private var clickableRoles: Set<String> {
        [
            "AXLink", "AXButton", "AXMenuItem", "AXRow", "AXCell",
            "AXRadioButton", "AXCheckBox", "AXSwitch", "AXPopUpButton",
            "AXComboBox", "AXDisclosureTriangle", "AXSlider"
        ]
    }

    private func activateClickable(_ target: UIElementHint) {
        let point = center(of: target.frame)
        let activated = NSRunningApplication(processIdentifier: target.processIdentifier)?.activate(
            options: [.activateIgnoringOtherApps]
        ) ?? false
        diagnosticLog("activate target pid=\(target.processIdentifier) success=\(activated)")
        input.moveMouse(to: point)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            if shouldSelectAXElement(role: target.role) {
                let result = self.ax.setSelected(target.element)
                diagnosticLog("AX select role=\(target.role) title=\(target.title) result=\(result.rawValue)")
                if result == .success { return }
            }

            if let resolved = self.resolveActionTarget(at: point, target: target) {
                let result = self.ax.perform(resolved.action, on: resolved.element)
                diagnosticLog(
                    "AX action role=\(resolved.role) action=\(resolved.action) "
                    + "supported=\(resolved.supportedActions.joined(separator: ",")) result=\(result.rawValue)"
                )
                if result == .success {
                    if requiresTargetedMouseConfirmation(processIdentifier: target.processIdentifier) {
                        self.input.clickTargeted(at: point, processIdentifier: target.processIdentifier)
                    }
                    return
                }
            } else {
                diagnosticLog("AX action unresolved role=\(target.role) title=\(target.title)")
            }

            if requiresTargetedMouseConfirmation(processIdentifier: target.processIdentifier) {
                self.input.clickTargeted(at: point, processIdentifier: target.processIdentifier)
            } else {
                self.input.clickGlobal(at: point, processIdentifier: target.processIdentifier)
            }
        }
    }

    private func resolveActionTarget(at point: CGPoint, target: UIElementHint) -> ResolvedAXAction? {
        let application = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 1.5)

        var candidates: [AXUIElement] = [target.element]
        let (hitResult, hitElement) = ax.element(at: point, in: application)
        if hitResult == .success, let hitElement {
            appendUnique(hitElement, to: &candidates)
            for ancestor in ax.ancestors(of: hitElement, limit: 12) {
                appendUnique(ancestor, to: &candidates)
            }
        }

        diagnosticLog("AX hit-test result=\(hitResult.rawValue) candidates=\(candidates.count)")
        let supportedActions = candidates.map(ax.actionNames)
        guard let selection = preferredAXActionCandidate(supportedActions) else { return nil }
        let candidate = candidates[selection.candidateIndex]
        return ResolvedAXAction(
            element: candidate,
            role: ax.stringAttribute(kAXRoleAttribute as String, of: candidate) ?? "",
            action: selection.action,
            supportedActions: supportedActions[selection.candidateIndex]
        )
    }

    private func appendUnique(_ element: AXUIElement, to candidates: inout [AXUIElement]) {
        guard !candidates.contains(where: { CFEqual($0, element) }) else { return }
        candidates.append(element)
    }

    private func center(of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }
}

struct AXActionCandidateSelection: Equatable {
    let candidateIndex: Int
    let action: String
}

func shouldSelectAXElement(role: String) -> Bool {
    role == "AXRow" || role == "AXCell"
}

func requiresTargetedMouseConfirmation(processIdentifier: pid_t) -> Bool {
    NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier == "com.openai.codex"
}

func preferredAXActionCandidate(_ supportedActionsByCandidate: [[String]]) -> AXActionCandidateSelection? {
    let actionPriority = [
        kAXPressAction as String,
        kAXPickAction as String,
        kAXShowMenuAction as String
    ]
    for action in actionPriority {
        if let candidateIndex = supportedActionsByCandidate.firstIndex(where: { $0.contains(action) }) {
            return AXActionCandidateSelection(candidateIndex: candidateIndex, action: action)
        }
    }
    return nil
}

private struct ResolvedAXAction {
    let element: AXUIElement
    let role: String
    let action: String
    let supportedActions: [String]
}
