import AppKit

enum HintOverlayPlacement: String, CaseIterable, Equatable {
    case topLeft
    case dockedEdge
    case aboveCenter
    case topRight
    case sideRight
    case bottomRight

    var displayName: String {
        switch self {
        case .topLeft: return "Inside Top Left"
        case .dockedEdge: return "Docked Edge"
        case .aboveCenter: return "Above Center"
        case .topRight: return "Inside Top Right"
        case .sideRight: return "Outside Right"
        case .bottomRight: return "Inside Bottom Right"
        }
    }

    var detail: String {
        switch self {
        case .topLeft:
            return "Overlaps the target's top-left corner, matching Vimium behavior."
        case .dockedEdge:
            return "Attaches to the target boundary with only 4 points of overlap."
        case .aboveCenter:
            return "Floats just above the target without covering its content."
        case .topRight:
            return "Sits inside the target's top-right corner."
        case .sideRight:
            return "Attaches outside the target's right edge."
        case .bottomRight:
            return "Sits inside the target's bottom-right corner."
        }
    }
}

enum HintBadgeAppearance: Equatable {
    case liquidGlass
    case keycap
}

enum HintOverlayAppearance: String, CaseIterable, Equatable {
    case adaptiveGlass
    case liquidGlass
    case keycap

    var displayName: String {
        switch self {
        case .adaptiveGlass: return "Adaptive: Glass → Keycap"
        case .liquidGlass: return "Liquid Glass"
        case .keycap: return "Keycap"
        }
    }

    var detail: String {
        switch self {
        case .adaptiveGlass:
            return "Starts as soft glass, then sharpens into a keycap after the first key."
        case .liquidGlass:
            return "Soft translucent glass with a bright border."
        case .keycap:
            return "Compact solid badges; choose their colors separately below."
        }
    }

    func resolved(isNarrowed: Bool) -> HintBadgeAppearance {
        switch self {
        case .adaptiveGlass: return isNarrowed ? .keycap : .liquidGlass
        case .liquidGlass: return .liquidGlass
        case .keycap: return .keycap
        }
    }
}

enum HintColorPalette: String, CaseIterable, Equatable {
    case amber
    case mint
    case violet

    var displayName: String {
        switch self {
        case .amber: return "Amber"
        case .mint: return "Mint"
        case .violet: return "Violet"
        }
    }

    var detail: String {
        switch self {
        case .amber: return "Graphite badges with warm amber accents."
        case .mint: return "Deep green badges with clear mint accents."
        case .violet: return "Rich violet badges with soft lavender accents."
        }
    }

    var accentColor: NSColor {
        switch self {
        case .amber: return .systemYellow
        case .mint: return .systemMint
        case .violet: return NSColor(calibratedRed: 0.77, green: 0.70, blue: 1, alpha: 1)
        }
    }

    var keycapBackgroundColor: NSColor {
        switch self {
        case .amber: return NSColor(calibratedWhite: 0.04, alpha: 0.96)
        case .mint: return NSColor(calibratedRed: 0.06, green: 0.19, blue: 0.15, alpha: 0.98)
        case .violet: return NSColor(calibratedRed: 0.40, green: 0.27, blue: 0.93, alpha: 0.96)
        }
    }

    var textColor: NSColor {
        switch self {
        case .amber, .violet: return .white
        case .mint: return NSColor(calibratedRed: 0.75, green: 1, blue: 0.91, alpha: 1)
        }
    }

    var prefixTextColor: NSColor {
        switch self {
        case .amber: return .systemYellow
        case .mint: return .white
        case .violet: return NSColor(calibratedRed: 1, green: 0.85, blue: 1, alpha: 1)
        }
    }
}

private enum LegacyHintOverlayStyle: String {
    case adaptiveGlass
    case liquidGlass
    case precisionKeycap
    case edgeTab
    case chromaticCorner
    case vimiumKeycap

    var preferences: (
        appearance: HintOverlayAppearance,
        palette: HintColorPalette,
        placement: HintOverlayPlacement
    ) {
        switch self {
        case .adaptiveGlass: return (.adaptiveGlass, .amber, .dockedEdge)
        case .liquidGlass: return (.liquidGlass, .amber, .aboveCenter)
        case .precisionKeycap: return (.keycap, .amber, .topRight)
        case .edgeTab: return (.keycap, .mint, .sideRight)
        case .chromaticCorner: return (.keycap, .violet, .bottomRight)
        case .vimiumKeycap: return (.keycap, .amber, .topLeft)
        }
    }
}

@MainActor
final class HintOverlayPreferenceStore {
    static let shared = HintOverlayPreferenceStore()

    private enum Key {
        static let appearance = "HintOverlayAppearance"
        static let palette = "HintOverlayColorPalette"
        static let placement = "HintOverlayPosition"
        static let legacyStyle = "HintOverlayStyle"
        static let showsTargetGuides = "HintOverlayShowsTargetGuides"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateLegacyStyleIfNeeded()
        migrateSeparatedAppearanceIfNeeded()
        defaults.register(defaults: [
            Key.appearance: HintOverlayAppearance.adaptiveGlass.rawValue,
            Key.palette: HintColorPalette.amber.rawValue,
            Key.placement: HintOverlayPlacement.topLeft.rawValue,
            Key.showsTargetGuides: true
        ])
    }

    var appearance: HintOverlayAppearance {
        get {
            guard let rawValue = defaults.string(forKey: Key.appearance),
                  let appearance = HintOverlayAppearance(rawValue: rawValue) else {
                return .adaptiveGlass
            }
            return appearance
        }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }

    var placement: HintOverlayPlacement {
        get {
            guard let rawValue = defaults.string(forKey: Key.placement),
                  let placement = HintOverlayPlacement(rawValue: rawValue) else {
                return .topLeft
            }
            return placement
        }
        set { defaults.set(newValue.rawValue, forKey: Key.placement) }
    }

    var palette: HintColorPalette {
        get {
            guard let rawValue = defaults.string(forKey: Key.palette),
                  let palette = HintColorPalette(rawValue: rawValue) else {
                return .amber
            }
            return palette
        }
        set { defaults.set(newValue.rawValue, forKey: Key.palette) }
    }

    var showsTargetGuides: Bool {
        get { defaults.bool(forKey: Key.showsTargetGuides) }
        set { defaults.set(newValue, forKey: Key.showsTargetGuides) }
    }

    private func migrateLegacyStyleIfNeeded() {
        guard let rawValue = defaults.string(forKey: Key.legacyStyle),
              let legacyStyle = LegacyHintOverlayStyle(rawValue: rawValue) else { return }
        let migrated = legacyStyle.preferences
        defaults.set(migrated.appearance.rawValue, forKey: Key.appearance)
        defaults.set(migrated.palette.rawValue, forKey: Key.palette)
        defaults.set(migrated.placement.rawValue, forKey: Key.placement)
        defaults.removeObject(forKey: Key.legacyStyle)
    }

    private func migrateSeparatedAppearanceIfNeeded() {
        guard let rawValue = defaults.string(forKey: Key.appearance) else { return }
        let migratedPalette: HintColorPalette
        switch rawValue {
        case "precisionKeycap": migratedPalette = .amber
        case "edgeTab": migratedPalette = .mint
        case "chromaticCorner": migratedPalette = .violet
        default: return
        }
        defaults.set(HintOverlayAppearance.keycap.rawValue, forKey: Key.appearance)
        defaults.set(migratedPalette.rawValue, forKey: Key.palette)
    }
}

@MainActor
final class OmniVimPreferencesWindowController: NSWindowController {
    private let store: HintOverlayPreferenceStore
    private let appearancePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let palettePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let placementPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let appearanceDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let paletteDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let placementDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let targetGuidesCheckbox = NSButton(
        checkboxWithTitle: "Show subtle target corners after the first key",
        target: nil,
        action: nil
    )
    private let preview: HintStylePreviewView

    init(store: HintOverlayPreferenceStore = .shared) {
        self.store = store
        self.preview = HintStylePreviewView(
            appearance: store.appearance,
            palette: store.palette,
            placement: store.placement
        )

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "OmniVim Preferences"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        refresh()
        showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Hint overlay")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitle = NSTextField(
            wrappingLabelWithString: "Choose badge style, color palette, and preferred position independently. Changes apply the next time you press Control-F."
        )
        subtitle.textColor = .secondaryLabelColor

        appearancePopup.addItems(withTitles: HintOverlayAppearance.allCases.map(\.displayName))
        appearancePopup.target = self
        appearancePopup.action = #selector(appearanceChanged)

        let appearanceLabel = NSTextField(labelWithString: "Appearance")
        appearanceLabel.font = .systemFont(ofSize: 13, weight: .medium)
        appearanceLabel.setContentHuggingPriority(.required, for: .horizontal)
        let appearanceRow = NSStackView(views: [appearanceLabel, appearancePopup])
        appearanceRow.orientation = .horizontal
        appearanceRow.alignment = .centerY
        appearanceRow.spacing = 16

        appearanceDetailLabel.textColor = .secondaryLabelColor
        appearanceDetailLabel.font = .systemFont(ofSize: 12)

        palettePopup.addItems(withTitles: HintColorPalette.allCases.map(\.displayName))
        palettePopup.target = self
        palettePopup.action = #selector(paletteChanged)

        let paletteLabel = NSTextField(labelWithString: "Color palette")
        paletteLabel.font = .systemFont(ofSize: 13, weight: .medium)
        paletteLabel.setContentHuggingPriority(.required, for: .horizontal)
        let paletteRow = NSStackView(views: [paletteLabel, palettePopup])
        paletteRow.orientation = .horizontal
        paletteRow.alignment = .centerY
        paletteRow.spacing = 16

        paletteDetailLabel.textColor = .secondaryLabelColor
        paletteDetailLabel.font = .systemFont(ofSize: 12)

        placementPopup.addItems(withTitles: HintOverlayPlacement.allCases.map(\.displayName))
        placementPopup.target = self
        placementPopup.action = #selector(placementChanged)

        let placementLabel = NSTextField(labelWithString: "Position")
        placementLabel.font = .systemFont(ofSize: 13, weight: .medium)
        placementLabel.setContentHuggingPriority(.required, for: .horizontal)
        let placementRow = NSStackView(views: [placementLabel, placementPopup])
        placementRow.orientation = .horizontal
        placementRow.alignment = .centerY
        placementRow.spacing = 16

        placementDetailLabel.textColor = .secondaryLabelColor
        placementDetailLabel.font = .systemFont(ofSize: 12)

        targetGuidesCheckbox.target = self
        targetGuidesCheckbox.action = #selector(targetGuidesChanged)

        let stack = NSStackView(views: [
            title,
            subtitle,
            appearanceRow,
            appearanceDetailLabel,
            paletteRow,
            paletteDetailLabel,
            placementRow,
            placementDetailLabel,
            preview,
            targetGuidesCheckbox
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            appearancePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 230),
            palettePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 230),
            placementPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 230),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preview.heightAnchor.constraint(equalToConstant: 190)
        ])

        refresh()
    }

    private func refresh() {
        let appearance = store.appearance
        let palette = store.palette
        let placement = store.placement
        appearancePopup.selectItem(
            at: HintOverlayAppearance.allCases.firstIndex(of: appearance) ?? 0
        )
        placementPopup.selectItem(
            at: HintOverlayPlacement.allCases.firstIndex(of: placement) ?? 0
        )
        palettePopup.selectItem(at: HintColorPalette.allCases.firstIndex(of: palette) ?? 0)
        appearanceDetailLabel.stringValue = appearance.detail
        paletteDetailLabel.stringValue = palette.detail
        placementDetailLabel.stringValue = placement.detail
        preview.badgeAppearance = appearance
        preview.palette = palette
        preview.placement = placement
        targetGuidesCheckbox.state = store.showsTargetGuides ? .on : .off
    }

    @objc private func appearanceChanged() {
        let index = appearancePopup.indexOfSelectedItem
        guard HintOverlayAppearance.allCases.indices.contains(index) else { return }
        store.appearance = HintOverlayAppearance.allCases[index]
        refresh()
    }

    @objc private func placementChanged() {
        let index = placementPopup.indexOfSelectedItem
        guard HintOverlayPlacement.allCases.indices.contains(index) else { return }
        store.placement = HintOverlayPlacement.allCases[index]
        refresh()
    }

    @objc private func paletteChanged() {
        let index = palettePopup.indexOfSelectedItem
        guard HintColorPalette.allCases.indices.contains(index) else { return }
        store.palette = HintColorPalette.allCases[index]
        refresh()
    }

    @objc private func targetGuidesChanged() {
        store.showsTargetGuides = targetGuidesCheckbox.state == .on
    }
}

@MainActor
private final class HintStylePreviewView: NSView {
    var badgeAppearance: HintOverlayAppearance {
        didSet { needsDisplay = true }
    }
    var placement: HintOverlayPlacement {
        didSet { needsDisplay = true }
    }
    var palette: HintColorPalette {
        didSet { needsDisplay = true }
    }

    init(
        appearance: HintOverlayAppearance,
        palette: HintColorPalette,
        placement: HintOverlayPlacement
    ) {
        self.badgeAppearance = appearance
        self.palette = palette
        self.placement = placement
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.055, green: 0.078, blue: 0.11, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()

        drawSample(
            in: CGRect(x: 24, y: 24, width: bounds.width / 2 - 36, height: bounds.height - 48),
            label: "INITIAL",
            narrowed: false
        )
        drawSample(
            in: CGRect(x: bounds.width / 2 + 12, y: 24, width: bounds.width / 2 - 36, height: bounds.height - 48),
            label: "AFTER PREFIX",
            narrowed: true
        )
    }

    private func drawSample(in frame: CGRect, label: String, narrowed: Bool) {
        (label as NSString).draw(at: CGPoint(x: frame.minX, y: frame.maxY - 16), withAttributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.62, alpha: 1)
        ])

        let target = CGRect(x: frame.minX + 20, y: frame.midY - 24, width: frame.width - 40, height: 52)
        NSColor(calibratedRed: 0.10, green: 0.15, blue: 0.21, alpha: 1).setFill()
        NSBezierPath(roundedRect: target, xRadius: 8, yRadius: 8).fill()
        ("Detected control" as NSString).draw(
            at: CGPoint(x: target.minX + 14, y: target.midY - 7),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.82, alpha: 1)
            ]
        )

        let badgeSize = CGSize(width: 34, height: 22)
        let badgeFrame = previewBadgeFrame(
            target: target,
            badgeSize: badgeSize,
            placement: placement
        )
        let resolvedAppearance = badgeAppearance.resolved(isNarrowed: narrowed)
        badgeColors(for: resolvedAppearance, palette: palette).background.setFill()
        badgeColors(for: resolvedAppearance, palette: palette).border.setStroke()
        let badgePath = NSBezierPath(
            roundedRect: badgeFrame,
            xRadius: resolvedAppearance == .liquidGlass ? 11 : 5,
            yRadius: resolvedAppearance == .liquidGlass ? 11 : 5
        )
        badgePath.lineWidth = 1
        badgePath.fill()
        badgePath.stroke()
        ("SA" as NSString).draw(at: CGPoint(x: badgeFrame.midX - 7, y: badgeFrame.midY - 6), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: badgeColors(for: resolvedAppearance, palette: palette).text
        ])
    }

    private func previewBadgeFrame(
        target: CGRect,
        badgeSize: CGSize,
        placement: HintOverlayPlacement
    ) -> CGRect {
        switch placement {
        case .dockedEdge:
            if target.width >= target.height * 2 {
                return CGRect(
                    x: target.maxX - 4,
                    y: target.midY - badgeSize.height / 2,
                    width: badgeSize.width,
                    height: badgeSize.height
                )
            }
            return CGRect(
                x: target.midX - badgeSize.width / 2,
                y: target.minY - badgeSize.height + 4,
                width: badgeSize.width,
                height: badgeSize.height
            )
        case .aboveCenter:
            return CGRect(
                x: target.midX - badgeSize.width / 2,
                y: target.maxY + 5,
                width: badgeSize.width,
                height: badgeSize.height
            )
        case .topLeft:
            return CGRect(
                x: target.minX + 4,
                y: target.maxY - badgeSize.height - 4,
                width: badgeSize.width,
                height: badgeSize.height
            )
        case .topRight:
            return CGRect(
                x: target.maxX - badgeSize.width - 4,
                y: target.maxY - badgeSize.height - 4,
                width: badgeSize.width,
                height: badgeSize.height
            )
        case .sideRight:
            return CGRect(
                x: target.maxX + 5,
                y: target.midY - badgeSize.height / 2,
                width: badgeSize.width,
                height: badgeSize.height
            )
        case .bottomRight:
            return CGRect(
                x: target.maxX - badgeSize.width - 4,
                y: target.minY + 4,
                width: badgeSize.width,
                height: badgeSize.height
            )
        }
    }

    private func badgeColors(
        for appearance: HintBadgeAppearance,
        palette: HintColorPalette
    ) -> (background: NSColor, border: NSColor, text: NSColor) {
        switch appearance {
        case .liquidGlass:
            return (
                palette.accentColor.withAlphaComponent(0.18),
                palette.accentColor.withAlphaComponent(0.72),
                .white
            )
        case .keycap:
            return (
                palette.keycapBackgroundColor,
                palette.accentColor,
                palette.textColor
            )
        }
    }
}
