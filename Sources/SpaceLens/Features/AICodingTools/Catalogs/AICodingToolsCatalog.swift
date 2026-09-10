enum AICodingToolsCatalog {
    static func definitions(for request: AICodingToolsRequest) -> [AICodingToolDefinition] {
        [
            CursorCatalog.definition(for: request),
            ClaudeCodeCatalog.definition(for: request),
            CodexCatalog.definition(for: request),
            AntigravityCatalog.definition(for: request),
            OpenCodeCatalog.definition(for: request)
        ]
    }

    static func rootDescriptors(for request: AICodingToolsRequest) -> [AICodingRootDescriptor] {
        definitions(for: request).flatMap(\.roots)
    }

    static var supportedTools: [AICodingToolMetadata] {
        [
            CursorCatalog.metadata,
            ClaudeCodeCatalog.metadata,
            CodexCatalog.metadata,
            AntigravityCatalog.metadata,
            OpenCodeCatalog.metadata
        ]
    }

    static func metadata(for id: AICodingToolID) -> AICodingToolMetadata {
        supportedTools.first { $0.id == id } ?? .fallback(for: id)
    }
}
