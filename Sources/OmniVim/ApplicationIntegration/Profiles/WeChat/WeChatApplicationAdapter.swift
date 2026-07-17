struct WeChatApplicationAdapter: ApplicationAdapter {
    private static let bundleIdentifiers: Set<String> = [
        "com.tencent.xinWeChat", "com.tencent.WeChat"
    ]

    let identifier = "wechat"

    func matches(_ context: RunningApplicationContext) -> Bool {
        matches(
            bundleIdentifier: context.bundleIdentifier,
            knownBundleIdentifiers: Self.bundleIdentifiers
        )
    }

    func capabilities(for environment: AdapterEnvironment) -> AdapterCapabilities {
        AdapterCapabilities(editorResolver: CapabilityPlanner().editorResolver(
            for: environment.capabilityReport,
            allowsInference: true
        ))
    }
}
