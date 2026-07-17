import AppKit

@MainActor
final class ElementActivator {
    private let ax: AXService
    private let input: InputSynthesizer

    init(ax: AXService = AXService(), input: InputSynthesizer = InputSynthesizer()) {
        self.ax = ax
        self.input = input
    }

    func activate(_ target: UIElementHint, targetedMouseConfirmation: Bool = false) {
        let activationID = String(UUID().uuidString.prefix(8)).lowercased()
        diagnosticLog("activation=\(activationID) target role=\(target.role) subrole=\(target.subrole)")
        if editableRoles.contains(target.role) {
            let result = ax.setFocused(target.element)
            record(activationID, method: .focus, dispatch: activationDispatchOutcome(for: result))
        } else if clickableRoles.contains(target.role) {
            activateClickable(
                target,
                activationID: activationID,
                targetedMouseConfirmation: targetedMouseConfirmation
            )
        } else {
            let result = ax.perform(kAXPressAction as String, on: target.element)
            record(activationID, method: .axPress, dispatch: activationDispatchOutcome(for: result))
            if result != .success {
                let posted = input.clickGlobal(at: center(of: target.frame), processIdentifier: target.processIdentifier)
                record(activationID, method: .globalMouse, dispatch: posted ? .accepted : .unavailable)
            }
        }
    }

    func activateByMouse(_ target: UIElementHint) {
        let activationID = String(UUID().uuidString.prefix(8)).lowercased()
        let point = center(of: target.frame)
        let activated = NSRunningApplication(processIdentifier: target.processIdentifier)?.activate(
            options: [.activateAllWindows, .activateIgnoringOtherApps]
        ) ?? false
        diagnosticLog(
            "activation=\(activationID) target role=\(target.role) "
                + "method=coordinate activate=\(activated)"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.prepareCoordinateClick(
                at: point,
                processIdentifier: target.processIdentifier,
                activationID: activationID,
                attemptsRemaining: 3
            )
        }
    }

    private func prepareCoordinateClick(
        at point: CGPoint,
        processIdentifier: pid_t,
        activationID: String,
        attemptsRemaining: Int
    ) {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        guard frontmostPID == processIdentifier else {
            diagnosticLog(
                "activation=\(activationID) coordinate waiting targetPid=\(processIdentifier) "
                    + "frontmostPid=\(frontmostPID) attemptsRemaining=\(attemptsRemaining)"
            )
            guard attemptsRemaining > 0 else {
                record(activationID, method: .globalMouse, dispatch: .unavailable)
                return
            }
            _ = NSRunningApplication(processIdentifier: processIdentifier)?.activate(
                options: [.activateAllWindows, .activateIgnoringOtherApps]
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.prepareCoordinateClick(
                    at: point,
                    processIdentifier: processIdentifier,
                    activationID: activationID,
                    attemptsRemaining: attemptsRemaining - 1
                )
            }
            return
        }

        input.moveMouse(to: point)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self else { return }
            let clickFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
            guard clickFrontmostPID == processIdentifier else {
                self.prepareCoordinateClick(
                    at: point,
                    processIdentifier: processIdentifier,
                    activationID: activationID,
                    attemptsRemaining: attemptsRemaining
                )
                return
            }
            let posted = self.input.clickGlobal(at: point, processIdentifier: processIdentifier)
            self.record(
                activationID,
                method: .globalMouse,
                dispatch: posted ? .accepted : .unavailable
            )
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

    private func activateClickable(
        _ target: UIElementHint,
        activationID: String,
        targetedMouseConfirmation: Bool
    ) {
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
                self.record(activationID, method: .select, dispatch: activationDispatchOutcome(for: result))
                if result == .success { return }
            }

            if let resolved = self.resolveActionTarget(at: point, target: target) {
                let result = self.ax.perform(resolved.action, on: resolved.element)
                diagnosticLog(
                    "AX action role=\(resolved.role) action=\(resolved.action) "
                    + "supported=\(resolved.supportedActions.joined(separator: ",")) result=\(result.rawValue)"
                )
                if let method = activationMethod(forAXAction: resolved.action) {
                    self.record(activationID, method: method, dispatch: activationDispatchOutcome(for: result))
                }
                if result == .success {
                    if targetedMouseConfirmation {
                        let posted = self.input.clickTargeted(at: point, processIdentifier: target.processIdentifier)
                        self.record(activationID, method: .targetedMouse, dispatch: posted ? .accepted : .unavailable)
                    }
                    return
                }
            } else {
                diagnosticLog("AX action unresolved role=\(target.role)")
            }

            if targetedMouseConfirmation {
                let posted = self.input.clickTargeted(at: point, processIdentifier: target.processIdentifier)
                self.record(activationID, method: .targetedMouse, dispatch: posted ? .accepted : .unavailable)
            } else {
                let posted = self.input.clickGlobal(at: point, processIdentifier: target.processIdentifier)
                self.record(activationID, method: .globalMouse, dispatch: posted ? .accepted : .unavailable)
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

    private func record(
        _ activationID: String,
        method: ActivationMethod,
        dispatch: ActivationDispatchOutcome,
        observation: ActivationObservation = .unknown
    ) {
        diagnosticLog(ActivationAttempt(
            activationID: activationID,
            method: method,
            dispatch: dispatch,
            observation: observation
        ).logMessage)
    }
}

struct AXActionCandidateSelection: Equatable {
    let candidateIndex: Int
    let action: String
}

func shouldSelectAXElement(role: String) -> Bool {
    role == "AXRow" || role == "AXCell"
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
