import AppKit

#if DEBUG
@MainActor
final class AXInspectorWindowController: NSWindowController {
    private let recorder = AXSnapshotRecorder()
    private let textView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "No snapshot captured")
    private var snapshot: AXApplicationSnapshot?
    private var targetProcessIdentifier: pid_t?

    convenience init() {
        let window = NSWindow(
            contentRect: CGRect(x: 120, y: 120, width: 960, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OmniVim AX Inspector"
        self.init(window: window)
        configureContent()
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }
        let captureButton = NSButton(title: "Capture Frontmost App", target: self, action: #selector(capture))
        let saveButton = NSButton(title: "Save JSON", target: self, action: #selector(save))
        let revealButton = NSButton(title: "Reveal Snapshots", target: self, action: #selector(revealSnapshots))
        let toolbar = NSStackView(views: [captureButton, saveButton, revealButton, statusLabel])
        toolbar.orientation = .horizontal
        toolbar.spacing = 10
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(toolbar)
        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    func target(processIdentifier: pid_t?) {
        targetProcessIdentifier = processIdentifier
        if let processIdentifier, let app = NSRunningApplication(processIdentifier: processIdentifier) {
            statusLabel.stringValue = "Target: \(app.localizedName ?? String(processIdentifier))"
        }
    }

    @objc private func capture() {
        let captured = targetProcessIdentifier.flatMap { recorder.capture(processIdentifier: $0) }
            ?? recorder.captureFrontmost()
        guard let captured else {
            statusLabel.stringValue = "Capture failed: Accessibility permission or frontmost app unavailable"
            return
        }
        snapshot = captured
        statusLabel.stringValue = "\(captured.applicationName) · \(captured.nodes.count) nodes"
        if let data = try? recorder.encode(captured) {
            textView.string = String(decoding: data, as: UTF8.self)
        }
    }

    @objc private func save() {
        guard let snapshot else {
            NSSound.beep()
            return
        }
        do {
            let url = try recorder.save(snapshot)
            statusLabel.stringValue = "Saved: \(url.lastPathComponent)"
        } catch {
            statusLabel.stringValue = "Save failed: \(error.localizedDescription)"
        }
    }

    @objc private func revealSnapshots() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/OmniVim/Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}
#endif
