protocol ApplicationAdapter {
    var identifier: String { get }

    func matches(_ context: RunningApplicationContext) -> Bool
    func capabilities(for environment: AdapterEnvironment) -> AdapterCapabilities
}

extension ApplicationAdapter {
    func matches(
        bundleIdentifier: String?,
        knownBundleIdentifiers: Set<String>
    ) -> Bool {
        guard let bundleIdentifier else { return false }
        return knownBundleIdentifiers.contains(bundleIdentifier)
    }
}
