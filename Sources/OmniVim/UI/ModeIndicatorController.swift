import AppKit

@MainActor
final class ModeIndicatorController {
    private let panel: NSPanel
    private let label: NSTextField

    init() {
        label = NSTextField(labelWithString: "NORMAL")
        label.alignment = .center
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false

        panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 112, height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.78)
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 6
        panel.contentView?.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor, constant: -4)
        ])
    }

    func update(_ mode: String) {
        label.stringValue = mode
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.minX + 16, y: screen.visibleFrame.minY + 16))
        panel.orderFrontRegardless()
    }
}
