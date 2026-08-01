import Foundation

struct WorkspaceSearchIndex: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var id: UUID
        var sectionID: UUID
        var state: WorkItemState
        var body: String
        var sourceApp: String?
        var sourceWindow: String?
        var updatedAt: Date
    }

    var schemaVersion = 1
    var workspaceID: UUID
    var generatedAt: Date
    var entries: [Entry]

    static func rebuild(from document: WorkspaceDocument, generatedAt: Date = Date()) -> WorkspaceSearchIndex {
        WorkspaceSearchIndex(
            workspaceID: document.id,
            generatedAt: generatedAt,
            entries: document.items.map {
                Entry(
                    id: $0.id,
                    sectionID: $0.sectionID,
                    state: $0.state,
                    body: $0.body,
                    sourceApp: $0.source.appName,
                    sourceWindow: $0.source.windowTitle,
                    updatedAt: $0.updatedAt
                )
            }
        )
    }
}
