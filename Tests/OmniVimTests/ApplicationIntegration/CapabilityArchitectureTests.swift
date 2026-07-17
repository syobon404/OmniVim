import AppKit
import XCTest
@testable import OmniVim

final class CapabilityArchitectureTests: XCTestCase {
    func testReportDefaultsUnknownCapabilityToNotTested() {
        let report = ApplicationCapabilityReport(
            fingerprint: fingerprint(),
            evidence: []
        )

        XCTAssertEqual(report.status(for: .focusedElement), .notTested)
    }

    func testReportUsesLatestEvidenceForCapability() {
        let report = ApplicationCapabilityReport(
            fingerprint: fingerprint(),
            evidence: [
                evidence(.focusedElement, .unsupported),
                evidence(.focusedElement, .confirmed)
            ]
        )

        XCTAssertEqual(report.status(for: .focusedElement), .confirmed)
    }

    func testPlannerKeepsGenericApplicationsOnStrictAXResolver() {
        let resolver = CapabilityPlanner().editorResolver(
            for: ApplicationCapabilityReport(fingerprint: fingerprint(), evidence: []),
            allowsInference: false
        )

        XCTAssertTrue(resolver is AXEditorResolver)
        XCTAssertFalse((resolver as? AXEditorResolver)?.allowsInference ?? true)
    }

    func testPlannerBuildsCompositeFallbackWhenInferenceIsAllowed() {
        let resolver = CapabilityPlanner().editorResolver(
            for: ApplicationCapabilityReport(fingerprint: fingerprint(), evidence: []),
            allowsInference: true
        )

        XCTAssertTrue(resolver is CompositeEditorResolver)
    }

    func testCapabilityCacheIsVersionScopedAndRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CapabilityReportCache(directoryURL: directory)
        let report = ApplicationCapabilityReport(
            fingerprint: fingerprint(version: "1.0"),
            generatedAt: Date(timeIntervalSince1970: 10),
            evidence: [evidence(.focusedElement, .confirmed)]
        )

        cache.store(report)

        XCTAssertEqual(
            CapabilityReportCache(directoryURL: directory).report(for: report.fingerprint),
            report
        )
        XCTAssertNil(cache.report(for: fingerprint(version: "2.0")))
    }

#if DEBUG
    func testCompatibilityArtifactRedactsUserFacingAXText() {
        let snapshot = AXApplicationSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1),
            processIdentifier: 42,
            bundleIdentifier: "test.app",
            applicationName: "Test",
            nodes: [AXNodeSnapshot(
                id: 0,
                parentID: nil,
                depth: 0,
                role: "AXTextArea",
                subrole: "",
                title: "Private title",
                description: "Private description",
                value: "Private message",
                identifier: "private-id",
                attributes: ["AXRole", "AXValue"],
                actions: ["AXPress"],
                frame: AXRectSnapshot(CGRect(x: 1, y: 2, width: 3, height: 4)),
                enabled: true,
                focused: true
            )]
        )
        let artifact = CompatibilityArtifact(
            report: ApplicationCapabilityReport(fingerprint: fingerprint(), evidence: []),
            accessibilitySnapshot: snapshot
        )

        XCTAssertEqual(artifact.accessibilitySnapshot?.nodes[0].value, "<redacted>")
        XCTAssertEqual(artifact.accessibilitySnapshot?.nodes[0].role, "AXTextArea")
        XCTAssertEqual(artifact.accessibilitySnapshot?.nodes[0].attributes, ["AXRole", "AXValue"])
        XCTAssertEqual(artifact.accessibilitySnapshot?.nodes[0].actions, ["AXPress"])
    }
#endif

    private func fingerprint(version: String = "1.0") -> ApplicationFingerprint {
        ApplicationFingerprint(
            bundleIdentifier: "test.app",
            version: version,
            buildVersion: "1",
            executableName: "Test",
            runtimeMarkers: [.unknown]
        )
    }

    private func evidence(
        _ capability: CapabilityID,
        _ status: CapabilitySupportStatus
    ) -> ProbeEvidence {
        ProbeEvidence(
            capability: capability,
            status: status,
            safetyLevel: .passive,
            method: "test",
            errorCode: nil,
            detail: nil,
            capturedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
