struct ApplicationAdapterRegistry {
    private let adapters: [any ApplicationAdapter]

    init(adapters: [any ApplicationAdapter] = Self.standardAdapters) {
        self.adapters = adapters
    }

    func adapter(for context: RunningApplicationContext) -> any ApplicationAdapter {
        adapters.first { $0.matches(context) } ?? GenericAXApplicationAdapter()
    }

    static var standardAdapters: [any ApplicationAdapter] {
        [
            CodexApplicationAdapter(),
            WeChatApplicationAdapter(),
            LarkApplicationAdapter(),
            TelegramApplicationAdapter(),
            TerminalApplicationAdapter(),
            GenericAXApplicationAdapter()
        ]
    }
}
