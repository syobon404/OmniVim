import AppKit

@MainActor
final class HintPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        contentView = HintCanvasView(frame: CGRect(origin: .zero, size: screen.frame.size))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class HintCanvasView: NSView {
    override var isFlipped: Bool { false }
}

@MainActor
final class HintMarkerView: NSView {
    private let code: String
    private let hint: UIElementHint
    private let action: (UIElementHint) -> Void
    private var matchingPrefixLength = 0

    init(code: String, hint: UIElementHint, action: @escaping (UIElementHint) -> Void) {
        self.code = code
        self.hint = hint
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.96).cgColor
        layer?.cornerRadius = 5
        layer?.borderColor = NSColor.black.withAlphaComponent(0.35).cgColor
        layer?.borderWidth = 1
        toolTip = hint.title.isEmpty ? hint.role : hint.title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(matchingPrefixLength: Int) {
        self.matchingPrefixLength = matchingPrefixLength
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let text = code.uppercased() as NSString
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let textSize = text.size(withAttributes: baseAttributes)
        let origin = CGPoint(
            x: bounds.midX - textSize.width / 2,
            y: bounds.midY - textSize.height / 2
        )
        text.draw(at: origin, withAttributes: baseAttributes)

        let prefixLength = min(matchingPrefixLength, text.length)
        if prefixLength > 0 {
            let prefix = text.substring(with: NSRange(location: 0, length: prefixLength)) as NSString
            prefix.draw(at: origin, withAttributes: [
                .font: font,
                .foregroundColor: NSColor.white
            ])
        }
    }

    override func mouseDown(with event: NSEvent) { action(hint) }
}
