import AppKit

@MainActor
final class HintOverlayController {
    private let hintCharacters = Array("sadfjklewcmpgh")
    private var panels: [CGDirectDisplayID: HintPanel] = [:]
    private var markers: [String: HintMarkerView] = [:]
    private var detectionOutlines: [String: HintDetectionOutlineView] = [:]
    private var hints: [String: UIElementHint] = [:]
    private var typedPrefix = ""

    var onTargetSelected: ((UIElementHint) -> Void)?
    var isVisible: Bool { !panels.isEmpty }

    @discardableResult
    func show(elements: [UIElementHint]) -> Bool {
        dismiss()
        guard !elements.isEmpty else {
            diagnosticLog("show overlay; no elements")
            return false
        }

        let codes = HintCodeGenerator(characters: hintCharacters).generate(count: elements.count)
        let assignments = zip(codes, elements).compactMap { code, hint -> HintAssignment? in
            guard let placement = placement(for: hint.frame, codeLength: code.count) else { return nil }
            return HintAssignment(code: code, hint: hint, placement: placement)
        }
        diagnosticLog("show overlay; elements=\(elements.count) assignments=\(assignments.count) maxCodeLength=\(codes.map(\.count).max() ?? 0)")
        for assignment in assignments {
            let frame = assignment.hint.frame.integral
            diagnosticLog(
                "hint assignment code=\(assignment.code) role=\(assignment.hint.role) "
                    + "frame=(\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height)))"
            )
        }

        for screen in NSScreen.screens {
            guard let displayID = displayID(for: screen),
                  assignments.contains(where: { $0.placement.displayID == displayID }) else { continue }
            panels[displayID] = HintPanel(screen: screen)
        }

        var resolvedFrames: [String: CGRect] = [:]
        for (displayID, panel) in panels {
            let localAssignments = assignments.filter { $0.placement.displayID == displayID }
            let placed = HintLayoutEngine().place(
                preferredFrames: localAssignments.map(\.placement.globalFrame),
                within: panel.frame
            )
            for (assignment, frame) in zip(localAssignments, placed) {
                resolvedFrames[assignment.code] = frame
            }
        }

        for assignment in assignments {
            guard let panel = panels[assignment.placement.displayID],
                  let contentView = panel.contentView,
                  let resolvedGlobalFrame = resolvedFrames[assignment.code] else { continue }
            let localFrame = resolvedGlobalFrame.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
            if assignment.hint.subrole == "GPAInteractiveElement" {
                let outline = HintDetectionOutlineView()
                outline.frame = localTargetFrame(
                    assignment.hint.frame,
                    displayID: assignment.placement.displayID,
                    panel: panel
                )
                contentView.addSubview(outline)
                detectionOutlines[assignment.code] = outline
            }
            let marker = HintMarkerView(code: assignment.code, hint: assignment.hint) { [weak self] hint in
                self?.onTargetSelected?(hint)
            }
            marker.frame = localFrame
            contentView.addSubview(marker)
            markers[assignment.code] = marker
            hints[assignment.code] = assignment.hint
        }

        panels.values.forEach { $0.orderFrontRegardless() }
        updateVisibleMarkers()
        diagnosticLog("overlay visible panels=\(panels.count) markers=\(markers.count)")
        return !panels.isEmpty
    }

    func dismiss() {
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        markers.removeAll()
        detectionOutlines.removeAll()
        hints.removeAll()
        typedPrefix = ""
    }

    func push(_ key: String) -> UIElementHint? {
        guard let character = key.lowercased().first, hintCharacters.contains(character) else { return nil }
        let candidatePrefix = typedPrefix + String(character)
        guard hints.keys.contains(where: { $0.hasPrefix(candidatePrefix) }) else { return nil }
        typedPrefix = candidatePrefix
        diagnosticLog("hint prefix=\(typedPrefix)")
        updateVisibleMarkers()

        let matches = hints.keys.filter { $0.hasPrefix(typedPrefix) }
        guard matches.count == 1, let code = matches.first else { return nil }
        return hints[code]
    }

    func popPrefix() -> Bool {
        guard !typedPrefix.isEmpty else { return false }
        typedPrefix.removeLast()
        diagnosticLog("hint prefix=\(typedPrefix)")
        updateVisibleMarkers()
        return true
    }

    private func updateVisibleMarkers() {
        for (code, marker) in markers {
            let hidden = !code.hasPrefix(typedPrefix)
            marker.isHidden = hidden
            detectionOutlines[code]?.isHidden = hidden
            marker.update(matchingPrefixLength: typedPrefix.count)
        }
    }

    private func localTargetFrame(
        _ targetFrame: CGRect,
        displayID: CGDirectDisplayID,
        panel: HintPanel
    ) -> CGRect {
        let displayBounds = CGDisplayBounds(displayID)
        return CGRect(
            x: targetFrame.minX - displayBounds.minX,
            y: panel.frame.height - (targetFrame.maxY - displayBounds.minY),
            width: targetFrame.width,
            height: targetFrame.height
        ).intersection(CGRect(origin: .zero, size: panel.frame.size))
    }

    private func placement(for axFrame: CGRect, codeLength: Int) -> HintPlacement? {
        let targetPoint = CGPoint(x: axFrame.midX, y: axFrame.midY)
        for screen in NSScreen.screens {
            guard let displayID = displayID(for: screen) else { continue }
            let displayBounds = CGDisplayBounds(displayID)
            guard displayBounds.contains(targetPoint) else { continue }

            let size = CGSize(width: max(28, CGFloat(codeLength * 11 + 12)), height: 24)
            let x = screen.frame.minX + (targetPoint.x - displayBounds.minX) - size.width / 2
            let yFromTop = targetPoint.y - displayBounds.minY
            let y = screen.frame.maxY - yFromTop - size.height / 2
            return HintPlacement(
                displayID: displayID,
                globalFrame: CGRect(origin: CGPoint(x: x, y: y), size: size)
            )
        }
        return nil
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.uint32Value
        }
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

private struct HintAssignment {
    let code: String
    let hint: UIElementHint
    let placement: HintPlacement
}

private struct HintPlacement {
    let displayID: CGDirectDisplayID
    let globalFrame: CGRect
}
