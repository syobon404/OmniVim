import AppKit

struct ApplicationIntegrationResolution {
    let environment: AdapterEnvironment
    let adapterIdentifier: String
    let capabilities: AdapterCapabilities
    let report: ApplicationCapabilityReport
}

final class ApplicationIntegrationRuntime {
    private struct Observation {
        let report: ApplicationCapabilityReport
        let probedAt: Date
    }

    private let registry: ApplicationAdapterRegistry
    private let probe: any ApplicationCapabilityProbing
    private let cache: CapabilityReportCache
    private var observations: [pid_t: Observation] = [:]
    private var fingerprints: [pid_t: ApplicationFingerprint] = [:]

    init(
        registry: ApplicationAdapterRegistry = ApplicationAdapterRegistry(),
        probe: any ApplicationCapabilityProbing = AXCapabilityProbe(),
        cache: CapabilityReportCache = CapabilityReportCache()
    ) {
        self.registry = registry
        self.probe = probe
        self.cache = cache
    }

    func resolve(context: RunningApplicationContext) -> ApplicationIntegrationResolution {
        let runningApplication = NSRunningApplication(
            processIdentifier: context.processIdentifier
        )
        let fingerprint = fingerprints[context.processIdentifier] ?? ApplicationFingerprint.make(
            runningApplication: runningApplication,
            fallbackBundleIdentifier: context.bundleIdentifier
        )
        fingerprints[context.processIdentifier] = fingerprint
        let report = report(for: context, fingerprint: fingerprint)
        let environment = AdapterEnvironment(
            application: context,
            capabilityReport: report
        )
        let adapter = registry.adapter(for: context)
        return ApplicationIntegrationResolution(
            environment: environment,
            adapterIdentifier: adapter.identifier,
            capabilities: adapter.capabilities(for: environment),
            report: report
        )
    }

    private func report(
        for context: RunningApplicationContext,
        fingerprint: ApplicationFingerprint
    ) -> ApplicationCapabilityReport {
        let now = Date()
        if let observation = observations[context.processIdentifier],
           observation.report.fingerprint == fingerprint,
           (observation.report.status(for: .focusedElement) == .confirmed
            || now.timeIntervalSince(observation.probedAt) < 0.5) {
            return observation.report
        }

        if observations[context.processIdentifier] == nil,
           let cached = cache.report(for: fingerprint),
           cached.status(for: .focusedElement) == .confirmed {
            observations[context.processIdentifier] = Observation(report: cached, probedAt: now)
            return cached
        }

        let previousReport = observations[context.processIdentifier]?.report
        let report = probe.probe(context: context, fingerprint: fingerprint)
        observations[context.processIdentifier] = Observation(report: report, probedAt: now)
        if previousReport == nil || capabilityStatusesChanged(from: previousReport, to: report) {
            cache.store(report)
        }
        diagnosticLog(
            "capability probe bundle=\(fingerprint.bundleIdentifier) "
                + "version=\(fingerprint.version ?? "unknown") "
                + "focused=\(report.status(for: .focusedElement).rawValue) "
                + "editable=\(report.status(for: .editableRole).rawValue)"
        )
        return report
    }

    private func capabilityStatusesChanged(
        from previous: ApplicationCapabilityReport?,
        to current: ApplicationCapabilityReport
    ) -> Bool {
        guard let previous else { return true }
        return CapabilityID.allCases.contains {
            previous.status(for: $0) != current.status(for: $0)
        }
    }
}
