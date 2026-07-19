import AppKit

@MainActor
final class HintOverlayController {
    private let hintCharacters = Array("sadfjklewcmpgh")
    private let preferences: HintOverlayPreferenceStore
    private var panels: [CGDirectDisplayID: HintPanel] = [:]
    private var markers: [String: HintMarkerView] = [:]
    private var detectionOutlines: [String: HintDetectionOutlineView] = [:]
    private var hints: [String: UIElementHint] = [:]
    private var assignments: [HintAssignment] = []
    private var activeAppearance = HintOverlayAppearance.adaptiveGlass
    private var activePalette = HintColorPalette.amber
    private var activePlacement = HintOverlayPlacement.topLeft
    private var showsTargetGuides = true
    private var typedPrefix = ""

    var onTargetSelected: ((UIElementHint) -> Void)?
    var isVisible: Bool { !panels.isEmpty }

    init(preferences: HintOverlayPreferenceStore = .shared) {
        self.preferences = preferences
    }

    @discardableResult
    func show(elements: [UIElementHint]) -> Bool {
        dismiss()
        guard !elements.isEmpty else {
            diagnosticLog("show overlay; no elements")
            return false
        }

        activeAppearance = preferences.appearance
        activePalette = preferences.palette
        activePlacement = preferences.placement
        showsTargetGuides = preferences.showsTargetGuides
        diagnosticLog(
            "hint appearance selected=\(activeAppearance.rawValue) "
                + "resolvedInitial=\(String(describing: activeAppearance.resolved(isNarrowed: false))) "
                + "palette=\(activePalette.rawValue) placement=\(activePlacement.rawValue)"
        )
        let orderedElements = elements.sorted(by: isBeforeInReadingOrder)
        let codes = HintCodeGenerator(characters: hintCharacters).generate(count: orderedElements.count)
        assignments = zip(codes, orderedElements).compactMap { code, hint -> HintAssignment? in
            guard let displayID = targetDisplayID(for: hint.frame) else { return nil }
            return HintAssignment(code: code, hint: hint, displayID: displayID)
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
                  assignments.contains(where: { $0.displayID == displayID }) else { continue }
            panels[displayID] = HintPanel(screen: screen)
        }

        for assignment in assignments {
            guard let panel = panels[assignment.displayID],
                  let contentView = panel.contentView else { continue }
            if assignment.hint.subrole == "GPAInteractiveElement" {
                let outline = HintDetectionOutlineView()
                outline.frame = localTargetFrame(
                    assignment.hint.frame,
                    displayID: assignment.displayID,
                    panel: panel
                )
                outline.isHidden = true
                contentView.addSubview(outline)
                detectionOutlines[assignment.code] = outline
            }
            let marker = HintMarkerView(
                code: assignment.code,
                hint: assignment.hint,
                appearance: activeAppearance.resolved(isNarrowed: false),
                palette: activePalette
            ) { [weak self] hint in
                self?.onTargetSelected?(hint)
            }
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
        assignments.removeAll()
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
        let narrowed = !typedPrefix.isEmpty
        let appearance = activeAppearance.resolved(isNarrowed: narrowed)
        if narrowed {
            diagnosticLog(
                "hint appearance prefix=\(typedPrefix) selected=\(activeAppearance.rawValue) "
                    + "resolved=\(String(describing: appearance))"
            )
        }
        for (code, marker) in markers {
            let hidden = !code.hasPrefix(typedPrefix)
            marker.isHidden = hidden
            let outline = detectionOutlines[code]
            let emphasizeTarget = showsTargetGuides && narrowed && !hidden
            outline?.isHidden = !emphasizeTarget
            outline?.setEmphasized(
                emphasizeTarget,
                appearance: appearance,
                palette: activePalette
            )
            marker.update(
                matchingPrefixLength: typedPrefix.count,
                appearance: appearance,
                palette: activePalette
            )
        }

        for (displayID, panel) in panels {
            let visibleAssignments = assignments.filter {
                $0.displayID == displayID && $0.code.hasPrefix(typedPrefix)
            }
            let preferred = visibleAssignments.compactMap { assignment in
                placement(
                    for: assignment.hint.frame,
                    codeLength: assignment.code.count,
                    displayID: displayID,
                    placement: activePlacement,
                    appearance: appearance
                ).map { (assignment, $0) }
            }
            let resolvedFrames = HintLayoutEngine().place(
                preferredFrames: preferred.map(\.1),
                within: panel.frame
            )
            for ((assignment, _), globalFrame) in zip(preferred, resolvedFrames) {
                markers[assignment.code]?.frame = globalFrame.offsetBy(
                    dx: -panel.frame.minX,
                    dy: -panel.frame.minY
                )
            }
        }
    }

    private func isBeforeInReadingOrder(_ lhs: UIElementHint, _ rhs: UIElementHint) -> Bool {
        let rowHeight: CGFloat = 10
        let lhsRow = Int(floor(lhs.frame.midY / rowHeight))
        let rhsRow = Int(floor(rhs.frame.midY / rowHeight))
        if lhsRow != rhsRow {
            return lhsRow < rhsRow
        }
        if lhs.frame.midX != rhs.frame.midX {
            return lhs.frame.midX < rhs.frame.midX
        }
        return lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
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

    private func targetDisplayID(for targetFrame: CGRect) -> CGDirectDisplayID? {
        let targetPoint = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        return NSScreen.screens.compactMap { displayID(for: $0) }.first {
            CGDisplayBounds($0).contains(targetPoint)
        }
    }

    private func placement(
        for axFrame: CGRect,
        codeLength: Int,
        displayID: CGDirectDisplayID,
        placement: HintOverlayPlacement,
        appearance: HintBadgeAppearance
    ) -> CGRect? {
        guard let screen = NSScreen.screens.first(where: { self.displayID(for: $0) == displayID }) else {
            return nil
        }
        let displayBounds = CGDisplayBounds(displayID)
        let size = markerSize(codeLength: codeLength, appearance: appearance)
        let targetMinX = screen.frame.minX + axFrame.minX - displayBounds.minX
        let targetMaxX = screen.frame.minX + axFrame.maxX - displayBounds.minX
        let targetTop = screen.frame.maxY - (axFrame.minY - displayBounds.minY)
        let targetBottom = screen.frame.maxY - (axFrame.maxY - displayBounds.minY)
        let origin: CGPoint
        switch placement {
        case .dockedEdge:
            if axFrame.width >= axFrame.height * 2 {
                origin = CGPoint(
                    x: targetMaxX - 4,
                    y: (targetTop + targetBottom - size.height) / 2
                )
            } else {
                origin = CGPoint(
                    x: (targetMinX + targetMaxX - size.width) / 2,
                    y: targetBottom - size.height + 4
                )
            }
        case .aboveCenter:
            origin = CGPoint(
                x: (targetMinX + targetMaxX - size.width) / 2,
                y: targetTop + 5
            )
        case .topLeft:
            origin = CGPoint(
                x: targetMinX + 4,
                y: targetTop - size.height - 4
            )
        case .topRight:
            origin = CGPoint(
                x: targetMaxX - size.width - 4,
                y: targetTop - size.height - 4
            )
        case .sideRight:
            origin = CGPoint(
                x: targetMaxX + 5,
                y: (targetTop + targetBottom - size.height) / 2
            )
        case .bottomRight:
            origin = CGPoint(
                x: targetMaxX - size.width - 4,
                y: targetBottom + 4
            )
        }
        return CGRect(origin: origin, size: size)
    }

    private func markerSize(
        codeLength: Int,
        appearance: HintBadgeAppearance
    ) -> CGSize {
        switch appearance {
        case .liquidGlass:
            return CGSize(width: max(30, CGFloat(codeLength * 9 + 12)), height: 22)
        case .keycap:
            return CGSize(width: max(24, CGFloat(codeLength * 9 + 8)), height: 20)
        }
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
    let displayID: CGDirectDisplayID
}
