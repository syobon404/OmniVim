import AppKit

/// A target that the Hints feature can label and activate.
///
/// Accessibility and visual discovery currently share this compatibility model. The activation
/// strategy determines whether `element` or the target coordinates are used.
struct UIElementHint {
    let element: AXUIElement
    let processIdentifier: pid_t
    let role: String
    let subrole: String
    let title: String
    let frame: CGRect
}
