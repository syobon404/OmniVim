struct TerminalApplicationAdapter: ApplicationAdapter {
    private static let bundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.github.wez.wezterm",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty"
    ]

    let identifier = "terminal"

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
                allowsInference: false
            ),
            commandExecutor: TerminalAdapterCommandExecutor()
        )
    }
}
