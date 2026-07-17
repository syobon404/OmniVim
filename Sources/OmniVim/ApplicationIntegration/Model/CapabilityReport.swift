import Foundation

enum CapabilityID: String, Codable, CaseIterable {
    case accessibilityTrusted
    case actionNames
    case editableRole
    case electronManualAccessibility
    case focusedElement
    case hitTesting
    case notificationObserver
    case parameterizedAttributes
    case selectedTextRange
    case textMarkers
}

enum CapabilitySupportStatus: String, Codable {
    case confirmed
    case unsupported
    case inconclusive
    case notTested
}

enum ProbeSafetyLevel: String, Codable {
    case passive
    case interactive
    case destructive
}

struct ProbeEvidence: Codable, Equatable {
    let capability: CapabilityID
    let status: CapabilitySupportStatus
    let safetyLevel: ProbeSafetyLevel
    let method: String
    let errorCode: Int?
    let detail: String?
    let capturedAt: Date
}

struct ApplicationCapabilityReport: Codable, Equatable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let fingerprint: ApplicationFingerprint
    let generatedAt: Date
    let evidence: [ProbeEvidence]

    init(
        fingerprint: ApplicationFingerprint,
        generatedAt: Date = Date(),
        evidence: [ProbeEvidence]
    ) {
        schemaVersion = Self.schemaVersion
        self.fingerprint = fingerprint
        self.generatedAt = generatedAt
        self.evidence = evidence
    }

    func status(for capability: CapabilityID) -> CapabilitySupportStatus {
        evidence.last(where: { $0.capability == capability })?.status ?? .notTested
    }
}
