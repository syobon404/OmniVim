import AppKit

final class AccessibilityScanner {
    func elements() -> [UIElementHint] {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return [] }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)
        guard let windows = windows as? [AXUIElement] else { return [] }
        diagnosticLog("AX scan app=\(app.bundleIdentifier ?? app.localizedName ?? "unknown") windows=\(windows.count)")
        var queue: [(element: AXUIElement, depth: Int, clip: CGRect?)] = windows.map {
            (element: $0, depth: 0, clip: frame(of: $0))
        }
        var cursor = 0
        var visited = 0
        var result: [UIElementHint] = []
        while cursor < queue.count, visited < 5_000, result.count < 200 {
            let (element, depth, inheritedClip) = queue[cursor]
            cursor += 1
            visited += 1
            let role = role(of: element)
            let elementFrame = frame(of: element)
            let clippingRoles = ["AXScrollArea", "AXOutline", "AXTable", "AXList", "AXBrowser"]
            let effectiveClip: CGRect?
            if clippingRoles.contains(role), let elementFrame {
                effectiveClip = intersect(inheritedClip, elementFrame)
            } else {
                effectiveClip = inheritedClip
            }
            if let hint = makeHint(element, visibleClip: effectiveClip, processIdentifier: app.processIdentifier) {
                result.append(hint)
            }
            guard depth < 30 else { continue }
            let children = clippingRoles.contains(role)
                ? visibleChildren(of: element)
                : children(of: element)
            for child in children {
                queue.append((element: child, depth: depth + 1, clip: effectiveClip))
            }
        }
        diagnosticLog("AX scan visited=\(visited) actionable=\(result.count)")
        let deduplicated = result.filter { candidate in
            guard candidate.role != "AXRow", candidate.role != "AXCell" else { return true }
            return !result.contains { container in
                ["AXRow", "AXCell"].contains(container.role)
                    && container.frame.width > candidate.frame.width
                    && container.frame.contains(CGPoint(x: candidate.frame.midX, y: candidate.frame.midY))
            }
        }
        let hitTestVisible = deduplicated.filter { isActuallyVisible($0, in: appElement) }
        let presentationItems = hitTestVisible.map {
            HintDeduplicator.Item(role: $0.role, title: $0.title, frame: $0.frame)
        }
        let uniqueItems = HintDeduplicator().deduplicate(presentationItems)
        let uniqueKeys = Set(uniqueItems.map { "\($0.role)|\($0.title)|\($0.frame.origin.x)|\($0.frame.origin.y)|\($0.frame.width)|\($0.frame.height)" })
        var emittedKeys = Set<String>()
        let visibleHints = hitTestVisible.filter {
            let key = "\($0.role)|\($0.title)|\($0.frame.origin.x)|\($0.frame.origin.y)|\($0.frame.width)|\($0.frame.height)"
            guard uniqueKeys.contains(key), !emittedKeys.contains(key) else { return false }
            emittedKeys.insert(key)
            return true
        }
        diagnosticLog("AX visibility candidates=\(deduplicated.count) hitTestVisible=\(hitTestVisible.count) unique=\(visibleHints.count)")
        return visibleHints.sorted { lhs, rhs in
            if abs(lhs.frame.minY - rhs.frame.minY) > 8 { return lhs.frame.minY < rhs.frame.minY }
            return lhs.frame.minX < rhs.frame.minX
        }
    }

    private func makeHint(_ element: AXUIElement, visibleClip: CGRect?, processIdentifier: pid_t) -> UIElementHint? {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let supportedRoles = [
            "AXButton", "AXLink", "AXMenuItem", "AXTextField", "AXTextArea", "AXSearchField",
            "AXCheckBox", "AXRadioButton", "AXSwitch", "AXPopUpButton", "AXComboBox",
            "AXDisclosureTriangle", "AXRow", "AXCell", "AXSlider"
        ]
        guard let role = roleRef as? String, supportedRoles.contains(role) else { return nil }
        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        let subrole = (subroleRef as? String) ?? ""
        let windowControlSubroles = ["AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton"]
        guard !windowControlSubroles.contains(subrole) else { return nil }
        let title = readableLabel(for: element)
        guard let frame = frame(of: element), frame.width > 8, frame.height > 8 else { return nil }
        let visibleFrame = visibleClip.map { frame.intersection($0) } ?? frame
        guard !visibleFrame.isNull, visibleFrame.width > 8, visibleFrame.height > 8 else { return nil }
        return UIElementHint(
            element: element,
            processIdentifier: processIdentifier,
            role: role,
            subrole: subrole,
            title: title,
            frame: visibleFrame
        )
    }

    private func readableLabel(for element: AXUIElement) -> String {
        let attributes = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute]
        for attribute in attributes {
            if let value = stringAttribute(attribute as String, of: element), !value.isEmpty { return value }
        }
        return descendantText(of: element, depth: 0) ?? ""
    }

    private func descendantText(of element: AXUIElement, depth: Int) -> String? {
        guard depth < 3 else { return nil }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        if roleRef as? String == "AXStaticText" {
            return stringAttribute(kAXValueAttribute as String, of: element)
                ?? stringAttribute(kAXTitleAttribute as String, of: element)
        }
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        let labels = ((childrenRef as? [AXUIElement]) ?? []).compactMap { descendantText(of: $0, depth: depth + 1) }
        return labels.first { !$0.isEmpty }
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        if let string = value as? String { return string.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func role(of element: AXUIElement) -> String {
        stringAttribute(kAXRoleAttribute as String, of: element) ?? ""
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        let positionValue = positionRef as! AXValue
        let sizeValue = sizeRef as! AXValue
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private func visibleChildren(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXVisibleChildren" as CFString, &value) == .success,
           let visible = value as? [AXUIElement], !visible.isEmpty {
            return visible
        }
        return children(of: element)
    }

    private func intersect(_ lhs: CGRect?, _ rhs: CGRect) -> CGRect {
        lhs.map { $0.intersection(rhs) } ?? rhs
    }

    private func isActuallyVisible(_ hint: UIElementHint, in application: AXUIElement) -> Bool {
        let frame = hint.frame
        let insetX = min(2, frame.width / 4)
        let insetY = min(2, frame.height / 4)
        let points = [
            CGPoint(x: frame.midX, y: frame.midY),
            CGPoint(x: frame.minX + insetX, y: frame.minY + insetY),
            CGPoint(x: frame.maxX - insetX, y: frame.minY + insetY),
            CGPoint(x: frame.minX + insetX, y: frame.maxY - insetY),
            CGPoint(x: frame.maxX - insetX, y: frame.maxY - insetY)
        ]

        for point in points {
            var hitElement: AXUIElement?
            let result = AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &hitElement)
            guard result == .success, let hitElement else { continue }
            if isSameOrRelated(hitElement, hint.element) { return true }
        }
        return false
    }

    private func isSameOrRelated(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        if CFEqual(lhs, rhs) { return true }
        return hasAncestor(lhs, matching: rhs) || hasAncestor(rhs, matching: lhs)
    }

    private func hasAncestor(_ element: AXUIElement, matching target: AXUIElement) -> Bool {
        var current = element
        for _ in 0..<12 {
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parentRef else { return false }
            let parent = parentRef as! AXUIElement
            if CFEqual(parent, target) { return true }
            current = parent
        }
        return false
    }
}
