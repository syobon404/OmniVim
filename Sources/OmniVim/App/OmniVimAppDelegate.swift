import AppKit

@MainActor
final class OmniVimAppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = OmniVimCoordinator()
    private var statusItem: NSStatusItem!
#if DEBUG
    private lazy var inspector = AXInspectorWindowController()
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        diagnosticLog("applicationDidFinishLaunching")
        NSLog("[OmniVim] applicationDidFinishLaunching")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        makeStatusItem()
        coordinator.start()
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
        let inspectorItem = menu.addItem(withTitle: "Open AX Inspector", action: #selector(openInspector), keyEquivalent: "d")
        inspectorItem.keyEquivalentModifierMask = [.command, .option]
        inspectorItem.target = self
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
    @objc private func openInspector() {
        inspector.target(processIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        inspector.showWindow(nil)
        inspector.window?.orderFrontRegardless()
    }
#endif

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
