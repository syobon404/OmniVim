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
final class HintDetectionOutlineView: NSView {
    private var isEmphasized = false
    private var currentAppearance = HintBadgeAppearance.keycap
    private var currentPalette = HintColorPalette.amber

    var renderedAppearance: HintBadgeAppearance { currentAppearance }
    var renderedPalette: HintColorPalette { currentPalette }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setEmphasized(
        _ emphasized: Bool,
        appearance: HintBadgeAppearance,
        palette: HintColorPalette
    ) {
        guard isEmphasized != emphasized
                || currentAppearance != appearance
                || currentPalette != palette else { return }
        isEmphasized = emphasized
        currentAppearance = appearance
        currentPalette = palette
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isEmphasized, bounds.width >= 8, bounds.height >= 8 else { return }

        let guideStyle = (
            color: currentPalette.accentColor.withAlphaComponent(
                currentAppearance == .liquidGlass ? 0.62 : 0.9
            ),
            lineWidth: currentAppearance == .liquidGlass ? CGFloat(1) : CGFloat(1.5)
        )
        guideStyle.color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = guideStyle.lineWidth
        let insetBounds = bounds.insetBy(dx: 1, dy: 1)
        let cornerLength = min(8, min(insetBounds.width, insetBounds.height) * 0.35)

        path.move(to: CGPoint(x: insetBounds.minX, y: insetBounds.minY + cornerLength))
        path.line(to: CGPoint(x: insetBounds.minX, y: insetBounds.minY))
        path.line(to: CGPoint(x: insetBounds.minX + cornerLength, y: insetBounds.minY))
        path.move(to: CGPoint(x: insetBounds.maxX - cornerLength, y: insetBounds.minY))
        path.line(to: CGPoint(x: insetBounds.maxX, y: insetBounds.minY))
        path.line(to: CGPoint(x: insetBounds.maxX, y: insetBounds.minY + cornerLength))
        path.move(to: CGPoint(x: insetBounds.maxX, y: insetBounds.maxY - cornerLength))
        path.line(to: CGPoint(x: insetBounds.maxX, y: insetBounds.maxY))
        path.line(to: CGPoint(x: insetBounds.maxX - cornerLength, y: insetBounds.maxY))
        path.move(to: CGPoint(x: insetBounds.minX + cornerLength, y: insetBounds.maxY))
        path.line(to: CGPoint(x: insetBounds.minX, y: insetBounds.maxY))
        path.line(to: CGPoint(x: insetBounds.minX, y: insetBounds.maxY - cornerLength))
        path.stroke()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class HintMarkerView: NSVisualEffectView {
    private let code: String
    private let hint: UIElementHint
    private let action: (UIElementHint) -> Void
    private var matchingPrefixLength = 0
    private var currentAppearance: HintBadgeAppearance?
    private var currentPalette: HintColorPalette?
    private var textColor = NSColor.white
    private var prefixTextColor = NSColor.systemYellow
    private let codeLabel = NSTextField(labelWithString: "")

    var renderedAppearance: HintBadgeAppearance? { currentAppearance }
    var renderedPalette: HintColorPalette? { currentPalette }

    init(
        code: String,
        hint: UIElementHint,
        appearance: HintBadgeAppearance,
        palette: HintColorPalette,
        action: @escaping (UIElementHint) -> Void
    ) {
        self.code = code
        self.hint = hint
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        layer?.shadowRadius = 2
        layer?.shadowOpacity = 0.45
        codeLabel.alignment = .center
        codeLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        codeLabel.isSelectable = false
        codeLabel.setAccessibilityElement(false)
        codeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(codeLabel)
        NSLayoutConstraint.activate([
            codeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            codeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            codeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            codeLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
        apply(appearance: appearance, palette: palette)
        currentAppearance = appearance
        currentPalette = palette
        updateCodeLabel()
        toolTip = hint.title.isEmpty ? hint.role : hint.title
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Hint \(code.uppercased())")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        matchingPrefixLength: Int,
        appearance: HintBadgeAppearance,
        palette: HintColorPalette
    ) {
        self.matchingPrefixLength = matchingPrefixLength
        if currentAppearance != appearance || currentPalette != palette {
            apply(appearance: appearance, palette: palette)
            currentAppearance = appearance
            currentPalette = palette
        }
        let emphasizesKeycap = appearance == .keycap && matchingPrefixLength > 0
        layer?.borderWidth = emphasizesKeycap ? 1.5 : 1
        layer?.shadowOpacity = emphasizesKeycap ? 0.7 : 0.45
        updateCodeLabel()
    }

    private func apply(appearance: HintBadgeAppearance, palette: HintColorPalette) {
        switch appearance {
        case .liquidGlass:
            material = .hudWindow
            blendingMode = .behindWindow
            state = .active
            layer?.backgroundColor = palette.accentColor.withAlphaComponent(0.18).cgColor
            layer?.borderColor = palette.accentColor.withAlphaComponent(0.72).cgColor
            layer?.cornerRadius = 10
            textColor = .white
            prefixTextColor = .white
        case .keycap:
            material = .contentBackground
            blendingMode = .withinWindow
            layer?.backgroundColor = palette.keycapBackgroundColor.cgColor
            layer?.borderColor = palette.accentColor.withAlphaComponent(0.9).cgColor
            layer?.cornerRadius = 5
            textColor = palette.textColor
            prefixTextColor = palette.prefixTextColor
        }
    }

    private func updateCodeLabel() {
        let text = code.uppercased()
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        let attributedText = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: textColor
        ])
        let prefixLength = min(matchingPrefixLength, text.count)
        if prefixLength > 0 {
            attributedText.addAttribute(
                .foregroundColor,
                value: prefixTextColor,
                range: NSRange(location: 0, length: prefixLength)
            )
        }
        codeLabel.attributedStringValue = attributedText
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) { action(hint) }
}
