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
    private let indicatorSize = CGSize(width: 104, height: 26)
    private let panel: NSPanel
    private let effectView: NSVisualEffectView
    private let accentView: NSView
    private let glyphLabel: NSTextField
    private let modeLabel: NSTextField
    private var anchorAXFrame: CGRect?
    private var hideWorkItem: DispatchWorkItem?
    private var presentationGeneration = 0

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
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.alphaValue = 0

        effectView = NSVisualEffectView(frame: CGRect(origin: .zero, size: indicatorSize))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = indicatorSize.height / 2
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.borderWidth = 0.5
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        effectView.autoresizingMask = [.width, .height]

        accentView = NSView(frame: CGRect(x: 6, y: 5, width: 16, height: 16))
        accentView.wantsLayer = true
        accentView.layer?.cornerRadius = 8

        glyphLabel = NSTextField(labelWithString: "N")
        glyphLabel.frame = accentView.bounds
        glyphLabel.alignment = .center
        glyphLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        glyphLabel.textColor = .white
        glyphLabel.autoresizingMask = [.width, .height]
        accentView.addSubview(glyphLabel)

        modeLabel = NSTextField(labelWithString: "NORMAL")
        modeLabel.frame = CGRect(x: 29, y: 5, width: 68, height: 16)
        modeLabel.alignment = .left
        modeLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        modeLabel.textColor = .labelColor

        effectView.addSubview(accentView)
        effectView.addSubview(modeLabel)
        panel.contentView = effectView
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

        applyAppearance(for: state, pendingOperator: pendingOperator)
        reposition(anchorAXFrame: anchorAXFrame)
        guard transition else { return }
        show()

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

    private func applyAppearance(for state: InteractionState, pendingOperator: VimOperator?) {
        if state == .normal, let pendingOperator {
            glyphLabel.stringValue = pendingOperator.indicatorGlyph
            modeLabel.stringValue = pendingOperator.indicatorLabel
            accentView.layer?.backgroundColor = switch pendingOperator {
            case .delete: NSColor.systemRed.cgColor
            case .change: NSColor.systemOrange.cgColor
            }
            return
        }

        switch state {
        case .inactive:
            break
        case .normal:
            glyphLabel.stringValue = "N"
            modeLabel.stringValue = "NORMAL"
            accentView.layer?.backgroundColor = NSColor.systemIndigo.cgColor
        case .insert:
            glyphLabel.stringValue = "I"
            modeLabel.stringValue = "INSERT"
            accentView.layer?.backgroundColor = NSColor.systemGreen.cgColor
        case .hint:
            glyphLabel.stringValue = "H"
            modeLabel.stringValue = "HINT"
            accentView.layer?.backgroundColor = NSColor.systemOrange.cgColor
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
