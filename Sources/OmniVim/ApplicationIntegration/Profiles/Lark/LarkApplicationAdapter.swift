struct LarkApplicationAdapter: ApplicationAdapter {
    private static let bundleIdentifiers: Set<String> = [
        "com.electron.lark", "com.larksuite.suite", "com.bytedance.Feishu"
    ]

    let identifier = "lark"
    private let editorResolver: any EditorResolving

    init(editorResolver: any EditorResolving = ElectronEditorResolver()) {
        self.editorResolver = editorResolver
    }

    func matches(_ context: RunningApplicationContext) -> Bool {
        matches(
            bundleIdentifier: context.bundleIdentifier,
            knownBundleIdentifiers: Self.bundleIdentifiers
        )
    }

    func capabilities(for environment: AdapterEnvironment) -> AdapterCapabilities {
        AdapterCapabilities(editorResolver: editorResolver)
    }
}
