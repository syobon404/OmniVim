import AppKit

#if DEBUG
struct CompatibilityArtifact: Codable, Equatable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let report: ApplicationCapabilityReport
    let accessibilitySnapshot: AXApplicationSnapshot?
    let sanitized: Bool

    init(
        report: ApplicationCapabilityReport,
        accessibilitySnapshot: AXApplicationSnapshot?,
        sanitized: Bool = true
    ) {
        schemaVersion = Self.schemaVersion
        exportedAt = Date()
        self.report = report
        self.accessibilitySnapshot = sanitized
            ? accessibilitySnapshot?.sanitized()
            : accessibilitySnapshot
        self.sanitized = sanitized
    }
}

@MainActor
final class CompatibilityArtifactExporter {
    private let probe: any ApplicationCapabilityProbing

    init(probe: any ApplicationCapabilityProbing = AXCapabilityProbe()) {
        self.probe = probe
    }

    func report(processIdentifier: pid_t) -> ApplicationCapabilityReport? {
        guard let app = NSRunningApplication(processIdentifier: processIdentifier) else { return nil }
        let context = RunningApplicationContext(
            processIdentifier: processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            activationPolicy: app.activationPolicy,
            accessibilityElement: AXUIElementCreateApplication(processIdentifier)
        )
        let fingerprint = ApplicationFingerprint.make(
            runningApplication: app,
            fallbackBundleIdentifier: app.bundleIdentifier
        )
        return probe.probe(context: context, fingerprint: fingerprint)
    }

    func encode(_ artifact: CompatibilityArtifact) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(artifact)
    }

    func save(_ artifact: CompatibilityArtifact) throws -> URL {
        let directory = Self.artifactDirectoryURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = directory.appendingPathComponent(
            "\(artifact.report.fingerprint.bundleIdentifier)-"
                + "\(formatter.string(from: artifact.exportedAt)).json"
        )
        try encode(artifact).write(to: url, options: .atomic)
        diagnosticLog("compatibility artifact saved path=\(url.path)")
        return url
    }

    static var artifactDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/OmniVim/Compatibility/Artifacts",
            isDirectory: true
        )
    }
}
#endif
