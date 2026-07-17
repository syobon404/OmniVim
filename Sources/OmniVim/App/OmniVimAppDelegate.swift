import AppKit

@MainActor
final class OmniVimAppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = OmniVimCoordinator()
    private var statusItem: NSStatusItem!
#if DEBUG
    private lazy var compatibilityLab = CompatibilityLabWindowController()
    private lazy var motionLab = ModeMotionLabWindowController()
    private var debugElementActivator: ElementActivator?
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        diagnosticLog("applicationDidFinishLaunching")
        NSLog("[OmniVim] applicationDidFinishLaunching")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
#if DEBUG
        if requestScreenCaptureAccessIfRequested() {
            app.terminate(nil)
            return
        }
        if captureCompatibilityArtifactIfRequested() {
            app.terminate(nil)
            return
        }
        if probeHintDiscoveryIfRequested() {
            app.terminate(nil)
            return
        }
        if activateHintIfRequested() {
            return
        }
#endif
        makeStatusItem()
        coordinator.start()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-hints") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                self?.coordinator.showHints(searchOnly: false)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--motion-lab") {
            motionLab.present()
        }
#endif
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⌘V"

        let menu = NSMenu()
        menu.addItem(withTitle: "OmniVim  ·  Text + UI navigation", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let hint = menu.addItem(withTitle: "Show UI hints", action: #selector(showHints), keyEquivalent: "f")
        hint.keyEquivalentModifierMask = .control
        hint.target = self
        let search = menu.addItem(withTitle: "Search UI elements", action: #selector(showSearchHints), keyEquivalent: "")
        search.target = self
        menu.addItem(.separator())
#if DEBUG
        let inspectorItem = menu.addItem(withTitle: "Open Compatibility Lab", action: #selector(openCompatibilityLab), keyEquivalent: "d")
        inspectorItem.keyEquivalentModifierMask = [.command, .option]
        inspectorItem.target = self
        let motionLabItem = menu.addItem(withTitle: "Open Motion Lab", action: #selector(openMotionLab), keyEquivalent: "m")
        motionLabItem.keyEquivalentModifierMask = [.command, .option]
        motionLabItem.target = self
        menu.addItem(.separator())
#endif
        let accessibility = menu.addItem(withTitle: "Open Accessibility Settings", action: #selector(openAccessibility), keyEquivalent: "")
        accessibility.target = self
        let quit = menu.addItem(withTitle: "Quit OmniVim", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        statusItem.menu = menu
    }

    @objc private func showHints() { coordinator.showHints(searchOnly: false) }
    @objc private func showSearchHints() { coordinator.showHints(searchOnly: true) }

#if DEBUG
    private func requestScreenCaptureAccessIfRequested() -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("--request-screen-capture") else {
            return false
        }
        let granted = CGRequestScreenCaptureAccess()
        diagnosticLog("screen capture permission requested granted=\(granted)")
        return true
    }

    private func probeHintDiscoveryIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let optionIndex = arguments.firstIndex(of: "--probe-hints"),
              arguments.indices.contains(optionIndex + 1) else { return false }

        let bundleIdentifier = arguments[optionIndex + 1]
        guard let target = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated }) else {
            diagnosticLog("hint probe failed bundle=\(bundleIdentifier) reason=not-running")
            return true
        }

        let hints: [UIElementHint]
        if bundleIdentifier == "ru.keepcoder.Telegram" {
            hints = TelegramHintProvider().hints(
                processIdentifier: target.processIdentifier,
                searchOnly: false
            )
        } else {
            hints = AXHitTestHintScanner().elements(
                processIdentifier: target.processIdentifier
            )
        }
        let roleCounts = Dictionary(grouping: hints, by: \.role)
            .map { "\($0.key)=\($0.value.count)" }
            .sorted()
            .joined(separator: ",")
        diagnosticLog(
            "hint probe completed bundle=\(bundleIdentifier) "
                + "count=\(hints.count) roles=\(roleCounts)"
        )
        for (index, hint) in hints.prefix(250).enumerated() {
            diagnosticLog(
                "hint probe item=\(index) role=\(hint.role) subrole=\(hint.subrole) "
                    + "frame=x=\(Int(hint.frame.minX)) y=\(Int(hint.frame.minY)) "
                    + "w=\(Int(hint.frame.width)) h=\(Int(hint.frame.height))"
            )
        }
        return true
    }

    private func activateHintIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let optionIndex = arguments.firstIndex(of: "--activate-hint"),
              arguments.indices.contains(optionIndex + 2),
              let hintIndex = Int(arguments[optionIndex + 2]) else { return false }

        let bundleIdentifier = arguments[optionIndex + 1]
        guard bundleIdentifier == "ru.keepcoder.Telegram",
              let target = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first(where: { !$0.isTerminated }) else {
            diagnosticLog("hint debug activation failed bundle=\(bundleIdentifier) reason=not-running")
            return true
        }

        let hints = TelegramHintProvider().hints(
            processIdentifier: target.processIdentifier,
            searchOnly: false
        )
        guard hints.indices.contains(hintIndex) else {
            diagnosticLog(
                "hint debug activation failed bundle=\(bundleIdentifier) "
                    + "index=\(hintIndex) count=\(hints.count)"
            )
            return true
        }

        let activator = ElementActivator()
        debugElementActivator = activator
        CoordinateElementActivator().activate(hints[hintIndex], using: activator)
        diagnosticLog(
            "hint debug activation dispatched bundle=\(bundleIdentifier) "
                + "index=\(hintIndex) count=\(hints.count)"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.debugElementActivator = nil
            NSApplication.shared.terminate(nil)
        }
        return true
    }

    private func captureCompatibilityArtifactIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let optionIndex = arguments.firstIndex(of: "--capture-compatibility"),
              arguments.indices.contains(optionIndex + 1) else { return false }

        let bundleIdentifier = arguments[optionIndex + 1]
        guard let target = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated }) else {
            diagnosticLog("compatibility capture failed bundle=\(bundleIdentifier) reason=not-running")
            return true
        }

        let recorder = AXSnapshotRecorder()
        let exporter = CompatibilityArtifactExporter()
        guard let report = exporter.report(processIdentifier: target.processIdentifier) else {
            diagnosticLog("compatibility capture failed bundle=\(bundleIdentifier) reason=probe")
            return true
        }

        do {
            let snapshot = recorder.capture(processIdentifier: target.processIdentifier)
            let artifact = CompatibilityArtifact(
                report: report,
                accessibilitySnapshot: snapshot
            )
            let url = try exporter.save(artifact)
            diagnosticLog(
                "compatibility capture completed bundle=\(bundleIdentifier) "
                    + "nodes=\(snapshot?.nodes.count ?? 0) path=\(url.path)"
            )
        } catch {
            diagnosticLog(
                "compatibility capture failed bundle=\(bundleIdentifier) "
                    + "reason=\(error.localizedDescription)"
            )
        }
        return true
    }

    @objc private func openCompatibilityLab() {
        compatibilityLab.target(
            processIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier
        )
        compatibilityLab.showWindow(nil)
        compatibilityLab.window?.orderFrontRegardless()
    }

    @objc private func openMotionLab() {
        motionLab.present()
    }
#endif

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
