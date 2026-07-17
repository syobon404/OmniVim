import AppKit

enum AXEditableRolePolicy {
    private static let standardRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXSearchField", "AXTextView"
    ]

    private static let inferredRoles: Set<String> = [
        "AXGroup", "AXWebArea", "AXGenericElement", "AXUnknown"
    ]

    static func accepts(role: String?, isEditable: Bool, allowsInference: Bool) -> Bool {
        if let role, standardRoles.contains(role) { return true }
        guard allowsInference, isEditable else { return false }
        guard let role else { return true }
        return inferredRoles.contains(role)
    }
}

struct AXEditorResolver: EditorResolving {
    let allowsInference: Bool

    init(allowsInference: Bool = false) {
        self.allowsInference = allowsInference
    }

    func resolve(in environment: AdapterEnvironment) -> EditorResolution? {
        guard let focusedElement = environment.focusedElement(),
              let editorElement = resolve(focusedElement: focusedElement) else { return nil }
        return EditorResolution(
            handle: .accessibility(editorElement),
            frame: frame(of: editorElement)
        )
    }

    func resolve(focusedElement: AXUIElement) -> AXUIElement? {
        if accepts(focusedElement) { return focusedElement }
        guard allowsInference else { return nil }

        for attribute in ["AXHighestEditableAncestor", "AXEditableAncestor"] {
            guard let ancestor = elementAttribute(attribute, of: focusedElement) else { continue }
            if accepts(ancestor) { return ancestor }
        }
        return nil
    }

    func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionRef
        ) == .success,
        AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeRef
        ) == .success,
        let positionRef,
        let sizeRef,
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

    private func accepts(_ element: AXUIElement) -> Bool {
        AXEditableRolePolicy.accepts(
            role: stringAttribute("AXRole", of: element),
            isEditable: boolAttribute("AXIsEditable", of: element),
            allowsInference: allowsInference
        )
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func boolAttribute(_ name: String, of element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return false
        }
        return (value as? Bool) == true
    }

    private func elementAttribute(_ name: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}

struct CompositeEditorResolver: EditorResolving {
    let resolvers: [any EditorResolving]

    func resolve(in environment: AdapterEnvironment) -> EditorResolution? {
        for resolver in resolvers {
            if let resolution = resolver.resolve(in: environment) { return resolution }
        }
        return nil
    }
}
