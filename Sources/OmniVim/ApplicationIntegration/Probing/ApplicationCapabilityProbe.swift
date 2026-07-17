protocol ApplicationCapabilityProbing {
    var safetyLevel: ProbeSafetyLevel { get }

    func probe(
        context: RunningApplicationContext,
        fingerprint: ApplicationFingerprint
    ) -> ApplicationCapabilityReport
}
