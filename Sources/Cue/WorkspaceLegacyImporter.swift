import CueCore
import Foundation

/// Adapts Cue's legacy aggregate Markdown recovery format into the sole
/// package writer. The aggregate codec remains app-side and never becomes a
/// second live workspace implementation.
struct WorkspaceLegacyImporter {
    let workspaceStore: WorkspaceStore

    init(workspaceStore: WorkspaceStore) {
        self.workspaceStore = workspaceStore
    }

    func importWorkspace(from sourceURL: URL, to packageURL: URL) throws -> FileFingerprint {
        let data = try Data(contentsOf: sourceURL)
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw WorkspaceStoreError.invalidDocument("legacy workspace is not UTF-8")
        }
        let document = try MarkdownWorkspaceCodec.decode(markdown)
        return try workspaceStore.create(document: document, at: packageURL)
    }
}
