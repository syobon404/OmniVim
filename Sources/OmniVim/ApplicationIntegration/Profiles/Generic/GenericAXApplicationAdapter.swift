struct GenericAXApplicationAdapter: ApplicationAdapter {
    let identifier = "generic-ax"

    func matches(_ context: RunningApplicationContext) -> Bool { true }

    func capabilities(for environment: AdapterEnvironment) -> AdapterCapabilities {
        AdapterCapabilities(editorResolver: CapabilityPlanner().editorResolver(
            for: environment.capabilityReport,
            allowsInference: false
        ))
    }
}
