import AppKit

struct ModeIndicatorLayout {
    static func frame(
        anchorFrame: CGRect?,
        indicatorSize: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        guard let anchorFrame else {
            return CGRect(
                x: visibleFrame.midX - indicatorSize.width / 2,
                y: visibleFrame.minY + 18,
                width: indicatorSize.width,
                height: indicatorSize.height
            )
        }

        let fitsInside = anchorFrame.width >= indicatorSize.width + 16
            && anchorFrame.height >= indicatorSize.height + 16
        let preferredOrigin: CGPoint
        if fitsInside {
            preferredOrigin = CGPoint(
                x: anchorFrame.maxX - indicatorSize.width - 8,
                y: anchorFrame.minY + 8
            )
        } else {
            let belowY = anchorFrame.minY - indicatorSize.height - 6
            let y = belowY >= visibleFrame.minY + 6
                ? belowY
                : anchorFrame.maxY + 6
            preferredOrigin = CGPoint(
                x: anchorFrame.maxX - indicatorSize.width,
                y: y
            )
        }

        let minimumX = visibleFrame.minX + 6
        let maximumX = visibleFrame.maxX - indicatorSize.width - 6
        let minimumY = visibleFrame.minY + 6
        let maximumY = visibleFrame.maxY - indicatorSize.height - 6
        return CGRect(
            x: min(max(preferredOrigin.x, minimumX), maximumX),
            y: min(max(preferredOrigin.y, minimumY), maximumY),
            width: indicatorSize.width,
            height: indicatorSize.height
        )
    }
}

struct ModeIndicatorPresentationPolicy {
    static func shouldAutoHideInsert(
        state: InteractionState,
        persistentInsert: Bool
    ) -> Bool {
        state == .insert && !persistentInsert
    }
}

@MainActor
final class ModeIndicatorController {
    private let indicatorSize = CGSize(width: 118, height: 34)
    private let panel: NSPanel
    private let surfaceView: NSView
    private let accentView: NSView
    private let glyphLabel: NSTextField
    private let modeLabel: NSTextField
    private var nativeNucleusView: NSView?
    private var nativeLabelView: NSView?
    private var anchorAXFrame: CGRect?
    private var hideWorkItem: DispatchWorkItem?
    private var compactWorkItem: DispatchWorkItem?
    private var presentationGeneration = 0
    private var modeAnimationGeneration = 0
    private var lastPresentationKey: String?
    private var nativePillIsCompact = false

    init() {
        panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: indicatorSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.alphaValue = 0

        accentView = NSView(frame: CGRect(x: 6, y: 9, width: 16, height: 16))
        accentView.wantsLayer = true
        accentView.layer?.cornerRadius = 8
        accentView.layer?.cornerCurve = .continuous

        glyphLabel = NSTextField(labelWithString: "N")
        glyphLabel.frame = accentView.bounds
        glyphLabel.alignment = .center
        glyphLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        glyphLabel.textColor = .white
        glyphLabel.autoresizingMask = [.width, .height]
        accentView.addSubview(glyphLabel)

        modeLabel = NSTextField(labelWithString: "NORMAL")
        modeLabel.frame = CGRect(x: 29, y: 9, width: 82, height: 16)
        modeLabel.alignment = .left
        modeLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        modeLabel.textColor = .labelColor

        if #available(macOS 26.0, *) {
            let container = NSGlassEffectContainerView(frame: CGRect(origin: .zero, size: indicatorSize))
            container.spacing = 12
            container.autoresizingMask = [.width, .height]

            let glassContent = NSView(frame: container.bounds)
            glassContent.autoresizingMask = [.width, .height]

            let nucleus = NSGlassEffectView(frame: CGRect(x: 0, y: 1, width: 34, height: 32))
            nucleus.cornerRadius = 12
            nucleus.style = .regular
            accentView.frame = CGRect(x: 7, y: 6, width: 20, height: 20)
            accentView.layer?.cornerRadius = 7
            glyphLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
            nucleus.contentView = accentView

            let label = NSGlassEffectView(frame: CGRect(x: 40, y: 1, width: 78, height: 32))
            label.cornerRadius = 12
            label.style = .regular
            let labelContent = NSView(frame: label.bounds)
            modeLabel.frame = CGRect(x: 9, y: 8, width: 60, height: 16)
            modeLabel.alignment = .center
            labelContent.addSubview(modeLabel)
            label.contentView = labelContent

            glassContent.addSubview(nucleus)
            glassContent.addSubview(label)
            container.contentView = glassContent
            surfaceView = container
            nativeNucleusView = nucleus
            nativeLabelView = label
        } else {
            let effectView = NSVisualEffectView(frame: CGRect(origin: .zero, size: indicatorSize))
            effectView.material = .hudWindow
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = indicatorSize.height / 2
            effectView.layer?.cornerCurve = .continuous
            effectView.layer?.borderWidth = 0.5
            effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
            effectView.autoresizingMask = [.width, .height]
            effectView.addSubview(accentView)
            effectView.addSubview(modeLabel)
            surfaceView = effectView
            panel.hasShadow = true
        }
        panel.contentView = surfaceView
    }

    func update(
        _ state: InteractionState,
        anchorAXFrame: CGRect?,
        persistentInsert: Bool = false,
        pendingOperator: VimOperator? = nil,
        transition: Bool = true
    ) {
        self.anchorAXFrame = anchorAXFrame
        guard state != .inactive else {
            hide(animated: transition)
            return
        }

        compactWorkItem?.cancel()
        let wasCompact = nativePillIsCompact
        let presentationKey = applyAppearance(for: state, pendingOperator: pendingOperator)
        reposition(anchorAXFrame: anchorAXFrame)
        guard transition else { return }
        if wasCompact {
            expandNativePill()
        } else if let lastPresentationKey, lastPresentationKey != presentationKey {
            animateNativeModeBoundary()
        }
        lastPresentationKey = presentationKey
        show()
        scheduleNativeCompaction()

        hideWorkItem?.cancel()
        if ModeIndicatorPresentationPolicy.shouldAutoHideInsert(
            state: state,
            persistentInsert: persistentInsert
        ) {
            let workItem = DispatchWorkItem { [weak self] in
                self?.hide(animated: true)
            }
            hideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
        }
    }

    func reposition(anchorAXFrame: CGRect?) {
        self.anchorAXFrame = anchorAXFrame
        guard let placement = placement(anchorAXFrame: anchorAXFrame) else { return }
        panel.setFrame(placement, display: panel.isVisible)
    }

    @discardableResult
    private func applyAppearance(for state: InteractionState, pendingOperator: VimOperator?) -> String {
        let accentColor: NSColor
        if state == .normal, let pendingOperator {
            glyphLabel.stringValue = pendingOperator.indicatorGlyph
            modeLabel.stringValue = pendingOperator.indicatorLabel
            accentColor = switch pendingOperator {
            case .delete: .systemRed
            case .change: .systemOrange
            }
            glyphLabel.textColor = nativeGlyphColor(accentColor)
            applyNativeGlassTint(accentColor)
            accentView.layer?.backgroundColor = accentColor.withAlphaComponent(0.24).cgColor
            return "normal-\(pendingOperator.indicatorLabel)"
        }

        switch state {
        case .inactive:
            return "inactive"
        case .normal:
            glyphLabel.stringValue = "N"
            modeLabel.stringValue = "NORMAL"
            accentColor = .systemIndigo
        case .insert:
            glyphLabel.stringValue = "I"
            modeLabel.stringValue = "INSERT"
            accentColor = .systemCyan
        case .hint:
            glyphLabel.stringValue = "H"
            modeLabel.stringValue = "HINT"
            accentColor = .systemYellow
        }
        glyphLabel.textColor = nativeGlyphColor(accentColor)
        accentView.layer?.backgroundColor = accentColor.withAlphaComponent(0.20).cgColor
        applyNativeGlassTint(accentColor)
        return state.label
    }

    private func nativeGlyphColor(_ accentColor: NSColor) -> NSColor {
        if #available(macOS 26.0, *) { return accentColor }
        return .white
    }

    private func applyNativeGlassTint(_ color: NSColor) {
        guard #available(macOS 26.0, *),
              let nucleus = nativeNucleusView as? NSGlassEffectView,
              let label = nativeLabelView as? NSGlassEffectView else { return }
        nucleus.tintColor = color.withAlphaComponent(0.22)
        label.tintColor = color.withAlphaComponent(0.09)
    }

    private func animateNativeModeBoundary() {
        guard #available(macOS 26.0, *),
              let nucleus = nativeNucleusView,
              let label = nativeLabelView else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard !reduceMotion else { return }

        modeAnimationGeneration += 1
        let generation = modeAnimationGeneration
        let settledNucleus = CGRect(x: 0, y: 1, width: 34, height: 32)
        let settledLabel = CGRect(x: 40, y: 1, width: 78, height: 32)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.09
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            nucleus.animator().frame = CGRect(x: 2, y: 2, width: 30, height: 30)
            label.animator().frame = CGRect(x: 34, y: 1, width: 84, height: 32)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.modeAnimationGeneration == generation else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    nucleus.animator().frame = settledNucleus
                    label.animator().frame = settledLabel
                }
            }
        }
    }

    private func scheduleNativeCompaction() {
        guard #available(macOS 26.0, *), nativeLabelView != nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.compactNativePill()
        }
        compactWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05, execute: workItem)
    }

    private func compactNativePill() {
        guard #available(macOS 26.0, *),
              let nucleus = nativeNucleusView,
              let label = nativeLabelView,
              !nativePillIsCompact else { return }
        nativePillIsCompact = true
        modeAnimationGeneration += 1
        let generation = modeAnimationGeneration
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.10 : 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            modeLabel.animator().alphaValue = 0
            label.animator().frame = CGRect(x: 17, y: 7, width: 18, height: 20)
            label.animator().alphaValue = 0
            if !reduceMotion {
                nucleus.animator().frame = CGRect(x: 1, y: 1, width: 33, height: 32)
            }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.modeAnimationGeneration == generation else { return }
                self.modeLabel.isHidden = true
            }
        }
    }

    private func expandNativePill() {
        guard #available(macOS 26.0, *),
              let nucleus = nativeNucleusView,
              let label = nativeLabelView,
              nativePillIsCompact else { return }
        nativePillIsCompact = false
        modeAnimationGeneration += 1
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        modeLabel.isHidden = false
        modeLabel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.10 : 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            nucleus.animator().frame = CGRect(x: 0, y: 1, width: 34, height: 32)
            label.animator().frame = CGRect(x: 40, y: 1, width: 78, height: 32)
            label.animator().alphaValue = 1
            modeLabel.animator().alphaValue = 1
        }
    }

    private func placement(anchorAXFrame: CGRect?) -> CGRect? {
        if let anchorAXFrame {
            let targetPoint = CGPoint(x: anchorAXFrame.midX, y: anchorAXFrame.midY)
            for screen in NSScreen.screens {
                guard let displayID = displayID(for: screen) else { continue }
                let displayBounds = CGDisplayBounds(displayID)
                guard displayBounds.contains(targetPoint) else { continue }
                let appKitAnchor = CGRect(
                    x: screen.frame.minX + anchorAXFrame.minX - displayBounds.minX,
                    y: screen.frame.maxY - (anchorAXFrame.maxY - displayBounds.minY),
                    width: anchorAXFrame.width,
                    height: anchorAXFrame.height
                )
                return ModeIndicatorLayout.frame(
                    anchorFrame: appKitAnchor,
                    indicatorSize: indicatorSize,
                    visibleFrame: screen.visibleFrame
                )
            }
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        return ModeIndicatorLayout.frame(
            anchorFrame: nil,
            indicatorSize: indicatorSize,
            visibleFrame: screen.visibleFrame
        )
    }

    private func show() {
        presentationGeneration += 1
        guard let finalFrame = placement(anchorAXFrame: anchorAXFrame) else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var initialFrame = finalFrame
        if !reduceMotion { initialFrame.origin.y -= 2 }
        panel.setFrame(initialFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.08 : 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if !reduceMotion { panel.animator().setFrame(finalFrame, display: true) }
        }
    }

    private func hide(animated: Bool) {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        compactWorkItem?.cancel()
        compactWorkItem = nil
        presentationGeneration += 1
        let generation = presentationGeneration
        guard panel.isVisible else { return }
        guard animated else {
            panel.orderOut(nil)
            panel.alphaValue = 0
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.presentationGeneration == generation else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.uint32Value
        }
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
