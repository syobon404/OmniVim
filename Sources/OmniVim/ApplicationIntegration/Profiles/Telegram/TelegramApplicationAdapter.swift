struct TelegramApplicationAdapter: ApplicationAdapter {
    private static let bundleIdentifiers: Set<String> = [
        "ru.keepcoder.Telegram", "org.telegram.desktop", "ph.telegra.Telegraph"
    ]

    let identifier = "telegram"

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
            hintProvider: TelegramHintProvider(),
            activator: CoordinateElementActivator()
        )
    }
}
