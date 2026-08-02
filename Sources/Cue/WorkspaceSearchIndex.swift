import CueCore
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

/// Owns only rebuildable derived search data. Package content remains owned by
/// CueCore.WorkspaceStore, and cache failures never invalidate a content load
/// or commit.
final class WorkspaceSearchIndexStore {
    private let fileManager: FileManager
    private let directoryURL: URL

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cue/WorkspaceIndex", isDirectory: true)
    }

    func url(for workspaceID: UUID) -> URL {
        directoryURL.appendingPathComponent("\(workspaceID.uuidString.lowercased()).json")
    }

    func rebuild(for document: WorkspaceDocument) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(WorkspaceSearchIndex.rebuild(from: document))
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try atomicWrite(data, to: url(for: document.id))
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).cue-tmp-\(UUID().uuidString)")
        do {
            try data.write(to: temporary, options: [])
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize()
            try handle.close()
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }
}
