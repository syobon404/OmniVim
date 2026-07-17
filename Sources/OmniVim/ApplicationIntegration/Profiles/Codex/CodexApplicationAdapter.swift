struct CodexApplicationAdapter: ApplicationAdapter {
    private static let bundleIdentifiers: Set<String> = ["com.openai.codex"]

    let identifier = "codex"

    func matches(_ context: RunningApplicationContext) -> Bool {
        matches(
            bundleIdentifier: context.bundleIdentifier,
            knownBundleIdentifiers: Self.bundleIdentifiers
        )
    }

    func capabilities(for environment: AdapterEnvironment) -> AdapterCapabilities {
        AdapterCapabilities(
            editorResolver: CapabilityPlanner().editorResolver(
                for: environment.capabilityReport,
                allowsInference: true
            ),
            activator: TargetedMouseElementActivator()
        )
    }
}
