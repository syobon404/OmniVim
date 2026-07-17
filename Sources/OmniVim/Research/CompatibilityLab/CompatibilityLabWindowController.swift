import AppKit

#if DEBUG
@MainActor
final class CompatibilityLabWindowController: NSWindowController {
    private let recorder = AXSnapshotRecorder()
    private let exporter = CompatibilityArtifactExporter()
    private let textView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "No snapshot captured")
    private var snapshot: AXApplicationSnapshot?
    private var report: ApplicationCapabilityReport?
    private var targetProcessIdentifier: pid_t?

    convenience init() {
        let window = NSWindow(
            contentRect: CGRect(x: 120, y: 120, width: 960, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OmniVim Compatibility Lab"
        self.init(window: window)
        configureContent()
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }
        let captureButton = NSButton(title: "Capture AX", target: self, action: #selector(capture))
        let probeButton = NSButton(title: "Probe Capabilities", target: self, action: #selector(probeCapabilities))
        let saveButton = NSButton(title: "Export Sanitized Artifact", target: self, action: #selector(save))
        let revealButton = NSButton(title: "Reveal Artifacts", target: self, action: #selector(revealArtifacts))
        let toolbar = NSStackView(
            views: [captureButton, probeButton, saveButton, revealButton, statusLabel]
        )
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

    @objc private func probeCapabilities() {
        guard let processIdentifier = targetProcessIdentifier
            ?? NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let report = exporter.report(processIdentifier: processIdentifier) else {
            statusLabel.stringValue = "Probe failed: target unavailable"
            return
        }
        self.report = report
        statusLabel.stringValue = "\(report.fingerprint.bundleIdentifier) · \(report.evidence.count) probes"
        let artifact = CompatibilityArtifact(
            report: report,
            accessibilitySnapshot: snapshot
        )
        if let data = try? exporter.encode(artifact) {
            textView.string = String(decoding: data, as: UTF8.self)
        }
    }

    @objc private func save() {
        guard let processIdentifier = targetProcessIdentifier
            ?? NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let report = report ?? exporter.report(processIdentifier: processIdentifier) else {
            NSSound.beep()
            return
        }
        do {
            let artifact = CompatibilityArtifact(
                report: report,
                accessibilitySnapshot: snapshot
            )
            let url = try exporter.save(artifact)
            statusLabel.stringValue = "Saved: \(url.lastPathComponent)"
        } catch {
            statusLabel.stringValue = "Save failed: \(error.localizedDescription)"
        }
    }

    @objc private func revealArtifacts() {
        let directory = CompatibilityArtifactExporter.artifactDirectoryURL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}
#endif
