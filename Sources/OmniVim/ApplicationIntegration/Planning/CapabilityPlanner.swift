struct CapabilityPlanner {
    func editorResolver(
        for report: ApplicationCapabilityReport?,
        allowsInference: Bool
    ) -> any EditorResolving {
        guard allowsInference else { return AXEditorResolver() }
        guard report?.status(for: .focusedElement) == .confirmed else {
            return CompositeEditorResolver(resolvers: [
                AXEditorResolver(),
                AXEditorResolver(allowsInference: true)
            ])
        }
        if report?.status(for: .editableRole) == .confirmed {
            return AXEditorResolver(allowsInference: true)
        }
        return CompositeEditorResolver(resolvers: [
            AXEditorResolver(),
            AXEditorResolver(allowsInference: true)
        ])
    }
}
