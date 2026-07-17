import AppKit

struct AXHitTestSamplingGrid {
    static func points(
        in frame: CGRect,
        step: CGFloat = 18,
        limit: Int = 6_000
    ) -> [CGPoint] {
        guard !frame.isNull,
              !frame.isEmpty,
              frame.width.isFinite,
              frame.height.isFinite,
              limit > 0 else { return [] }

        let spacing = max(8, step)
        var result: [CGPoint] = []
        var y = frame.minY + spacing / 2
        while y < frame.maxY, result.count < limit {
            var x = frame.minX + spacing / 2
            while x < frame.maxX, result.count < limit {
                result.append(CGPoint(x: x, y: y))
                x += spacing
            }
            y += spacing
        }
        return result
    }
}

func isAXHitTestHintCandidate(
    role: String,
    subrole: String,
    actions: [String]
) -> Bool {
    let excludedSubroles: Set<String> = [
        "AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton"
    ]
    guard !excludedSubroles.contains(subrole) else { return false }

    let supportedRoles: Set<String> = [
        "AXButton", "AXLink", "AXMenuItem", "AXTextField", "AXTextArea", "AXSearchField",
        "AXCheckBox", "AXRadioButton", "AXSwitch", "AXPopUpButton", "AXComboBox",
        "AXDisclosureTriangle", "AXRow", "AXCell", "AXSlider"
    ]
    if supportedRoles.contains(role) { return true }

    let meaningfulActions: Set<String> = [
        kAXPressAction as String,
        kAXPickAction as String,
        kAXShowMenuAction as String,
        "AXConfirm"
    ]
    let excludedRoles: Set<String> = [
        "AXApplication", "AXWindow", "AXMenuBar", "AXMenu", "AXToolbar"
    ]
    return !excludedRoles.contains(role) && !meaningfulActions.isDisjoint(with: actions)
}

@MainActor
final class AXHitTestHintScanner {
    private let samplingStep: CGFloat
    private let maximumSamples: Int
    private let ancestorLimit: Int

    init(
        samplingStep: CGFloat = 18,
        maximumSamples: Int = 6_000,
        ancestorLimit: Int = 12
    ) {
        self.samplingStep = samplingStep
        self.maximumSamples = maximumSamples
        self.ancestorLimit = ancestorLimit
    }

    func elements(processIdentifier explicitProcessIdentifier: pid_t? = nil) -> [UIElementHint] {
        guard AXIsProcessTrusted() else { return [] }
        let processIdentifier = explicitProcessIdentifier
            ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let processIdentifier else { return [] }

        let startedAt = CFAbsoluteTimeGetCurrent()
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.25)
        let windows = elementsAttribute(kAXWindowsAttribute as String, of: application)
        var sampleCount = 0
        var successfulHitCount = 0
        var discovered: [UIElementHint] = []

        if let focused = elementAttribute(kAXFocusedUIElementAttribute as String, of: application),
           let focusedFrame = frame(of: focused),
           let windowFrame = windows.compactMap({ frame(of: $0) }).first(where: {
               $0.intersects(focusedFrame)
           }) {
            appendNearestCandidate(
                from: focused,
                at: CGPoint(x: focusedFrame.midX, y: focusedFrame.midY),
                clippedTo: windowFrame,
                processIdentifier: processIdentifier,
                discovered: &discovered
            )
        }

        for window in windows {
            guard let windowFrame = frame(of: window),
                  windowFrame.width > 8,
                  windowFrame.height > 8 else { continue }
            let remaining = maximumSamples - sampleCount
            guard remaining > 0 else { break }
            let points = AXHitTestSamplingGrid.points(
                in: windowFrame,
                step: samplingStep,
                limit: remaining
            )
            for point in points {
                sampleCount += 1
                var hitElement: AXUIElement?
                let result = AXUIElementCopyElementAtPosition(
                    application,
                    Float(point.x),
                    Float(point.y),
                    &hitElement
                )
                guard result == .success, let hitElement else { continue }
                successfulHitCount += 1
                appendNearestCandidate(
                    from: hitElement,
                    at: point,
                    clippedTo: windowFrame,
                    processIdentifier: processIdentifier,
                    discovered: &discovered
                )
            }
        }

        let unique = presentationDeduplicated(discovered)
        let elapsedMilliseconds = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
        diagnosticLog(
            "AX hit-test scan pid=\(processIdentifier) windows=\(windows.count) "
                + "samples=\(sampleCount) hits=\(successfulHitCount) "
                + "candidates=\(discovered.count) unique=\(unique.count) "
                + "elapsedMs=\(elapsedMilliseconds)"
        )
        return unique.sorted { lhs, rhs in
            if abs(lhs.frame.minY - rhs.frame.minY) > 8 { return lhs.frame.minY < rhs.frame.minY }
            return lhs.frame.minX < rhs.frame.minX
        }
    }

    private func appendNearestCandidate(
        from hitElement: AXUIElement,
        at point: CGPoint,
        clippedTo windowFrame: CGRect,
        processIdentifier: pid_t,
        discovered: inout [UIElementHint]
    ) {
        var current: AXUIElement? = hitElement
        for _ in 0...ancestorLimit {
            guard let element = current else { return }
            let role = stringAttribute(kAXRoleAttribute as String, of: element) ?? ""
            let subrole = stringAttribute(kAXSubroleAttribute as String, of: element) ?? ""
            let actions = actionNames(of: element)
            if isAXHitTestHintCandidate(role: role, subrole: subrole, actions: actions),
               boolAttribute(kAXEnabledAttribute as String, of: element) != false,
               let elementFrame = frame(of: element),
               elementFrame.contains(point) {
                let visibleFrame = elementFrame.intersection(windowFrame)
                guard !visibleFrame.isNull,
                      visibleFrame.width > 8,
                      visibleFrame.height > 8 else { return }
                guard !discovered.contains(where: {
                    CFEqual($0.element, element) && $0.frame == visibleFrame
                }) else { return }
                discovered.append(UIElementHint(
                    element: element,
                    processIdentifier: processIdentifier,
                    role: role,
                    subrole: subrole,
                    title: readableLabel(for: element),
                    frame: visibleFrame
                ))
                return
            }
            current = elementAttribute(kAXParentAttribute as String, of: element)
        }
    }

    private func presentationDeduplicated(_ hints: [UIElementHint]) -> [UIElementHint] {
        let items = hints.map {
            HintDeduplicator.Item(role: $0.role, title: $0.title, frame: $0.frame)
        }
        let uniqueItems = HintDeduplicator().deduplicate(items)
        let uniqueKeys = Set(uniqueItems.map(key(for:)))
        var emitted = Set<String>()
        return hints.filter {
            let hintKey = key(for: HintDeduplicator.Item(
                role: $0.role,
                title: $0.title,
                frame: $0.frame
            ))
            guard uniqueKeys.contains(hintKey), !emitted.contains(hintKey) else { return false }
            emitted.insert(hintKey)
            return true
        }
    }

    private func key(for item: HintDeduplicator.Item) -> String {
        "\(item.role)|\(item.title)|\(item.frame.origin.x)|\(item.frame.origin.y)|"
            + "\(item.frame.width)|\(item.frame.height)"
    }

    private func readableLabel(for element: AXUIElement) -> String {
        for attribute in [
            kAXTitleAttribute as String,
            kAXDescriptionAttribute as String,
            kAXHelpAttribute as String,
            kAXValueAttribute as String
        ] {
            if let value = stringAttribute(attribute, of: element), !value.isEmpty { return value }
        }
        return ""
    }

    private func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    private func elementsAttribute(_ name: String, of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return []
        }
        return (value as? [AXUIElement]) ?? []
    }

    private func elementAttribute(_ name: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func boolAttribute(_ name: String, of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return (value as? NSNumber)?.boolValue
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        AXEditorResolver().frame(of: element)
    }
}

struct AXHitTestHintProvider: AdapterHintProviding {
    @MainActor
    func hints(searchOnly: Bool, scanner: AccessibilityScanner) -> [UIElementHint] {
        let elements = AXHitTestHintScanner().elements()
        guard searchOnly else { return elements }
        return elements.filter {
            ["AXTextField", "AXTextArea", "AXSearchField"].contains($0.role)
        }
    }
}
