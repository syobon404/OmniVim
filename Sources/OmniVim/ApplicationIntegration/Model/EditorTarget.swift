import AppKit

enum EditorHandle {
    case accessibility(AXUIElement)
    case visualRegion(windowIdentifier: CGWindowID, frame: CGRect)
}

struct EditorTarget {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let adapterIdentifier: String
    let capabilities: AdapterCapabilities
    let handle: EditorHandle
    let frame: CGRect?
    let prefersPersistentIndicator: Bool

    func matches(_ other: EditorTarget) -> Bool {
        guard processIdentifier == other.processIdentifier,
              adapterIdentifier == other.adapterIdentifier else { return false }
        switch (handle, other.handle) {
        case let (.accessibility(lhs), .accessibility(rhs)):
            return CFEqual(lhs, rhs)
        case let (.visualRegion(lhsWindow, lhsFrame), .visualRegion(rhsWindow, rhsFrame)):
            return lhsWindow == rhsWindow && lhsFrame == rhsFrame
        default:
            return false
        }
    }
}
