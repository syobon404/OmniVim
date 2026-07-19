import AppKit

final class AXService {
    func setFocused(_ element: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    func setSelected(_ element: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(element, kAXSelectedAttribute as CFString, kCFBooleanTrue)
    }

    func perform(_ action: String, on element: AXUIElement) -> AXError {
        let firstResult = AXUIElementPerformAction(element, action as CFString)
        guard firstResult == .cannotComplete else { return firstResult }
        AXUIElementSetMessagingTimeout(element, 2.0)
        return AXUIElementPerformAction(element, action as CFString)
    }

    func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    func element(at point: CGPoint, in application: AXUIElement) -> (AXError, AXUIElement?) {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &element)
        return (result, element)
    }

    func ancestors(of element: AXUIElement, limit: Int) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var current = element
        for _ in 0..<limit {
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parentRef,
                  CFGetTypeID(parentRef) == AXUIElementGetTypeID() else { break }
            let parent = parentRef as! AXUIElement
            result.append(parent)
            current = parent
        }
        return result
    }
}
