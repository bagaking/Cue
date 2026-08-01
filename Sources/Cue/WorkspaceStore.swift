import CryptoKit
import Foundation

final class WorkspaceStore {
    private let fileManager: FileManager
    private let backupLimit: Int

    init(fileManager: FileManager = .default, backupLimit: Int = 10) {
        self.fileManager = fileManager
        self.backupLimit = max(backupLimit, 10)
    }

    func create(document: WorkspaceDocument, at url: URL) throws -> FileFingerprint {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            throw WorkspaceStoreError.externalModification
        }
        return try write(document: document, to: url, expectedFingerprint: nil)
    }

    func load(from url: URL) throws -> (WorkspaceDocument, FileFingerprint) {
        guard fileManager.fileExists(atPath: url.path) else {
            throw WorkspaceStoreError.missingFile
        }
        do {
            let data = try Data(contentsOf: url)
            guard let markdown = String(data: data, encoding: .utf8) else {
                throw WorkspaceStoreError.invalidDocument("file is not UTF-8")
            }
            return (try MarkdownWorkspaceCodec.decode(markdown), try fingerprint(for: url, data: data))
        } catch let error as WorkspaceStoreError {
            throw error
        } catch {
            throw WorkspaceStoreError.invalidDocument(error.localizedDescription)
        }
    }

    @discardableResult
    func write(
        document: WorkspaceDocument,
        to url: URL,
        expectedFingerprint: FileFingerprint?
    ) throws -> FileFingerprint {
        let exists = fileManager.fileExists(atPath: url.path)
        if let expectedFingerprint {
            guard exists else { throw WorkspaceStoreError.missingFile }
            let current = try fingerprint(for: url)
            guard current == expectedFingerprint else { throw WorkspaceStoreError.externalModification }
        } else if exists {
            throw WorkspaceStoreError.externalModification
        }

        let markdown: String
        let preflightDocument: WorkspaceDocument
        do {
            markdown = try MarkdownWorkspaceCodec.encode(document)
            preflightDocument = try MarkdownWorkspaceCodec.decode(markdown)
            let canonicalDocument = try MarkdownWorkspaceCodec.decode(
                MarkdownWorkspaceCodec.encode(preflightDocument)
            )
            guard sameWorkspaceContent(preflightDocument, canonicalDocument) else {
                throw WorkspaceStoreError.invalidDocument("Markdown round trip changed the intended workspace")
            }
        } catch let error as WorkspaceStoreError {
            throw error
        } catch {
            throw WorkspaceStoreError.invalidDocument(error.localizedDescription)
        }

        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".\(url.lastPathComponent).cue-tmp-\(UUID().uuidString)")

        do {
            try Data(markdown.utf8).write(to: temporary, options: [])
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize()
            try handle.close()

            if exists {
                try createBackup(of: url)
                _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: url)
            }

            let (validated, fingerprint) = try load(from: url)
            let persistedMarkdown = try String(contentsOf: url, encoding: .utf8)
            guard persistedMarkdown == markdown,
                  sameWorkspaceContent(validated, preflightDocument) else {
                throw WorkspaceStoreError.invalidDocument("post-write validation did not match the intended workspace")
            }
            return fingerprint
        } catch let error as WorkspaceStoreError {
            try? fileManager.removeItem(at: temporary)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw WorkspaceStoreError.writeFailure(error.localizedDescription)
        }
    }

    func saveConflictCopy(document: WorkspaceDocument, nextTo url: URL) throws -> URL {
        try saveConflictCopy(markdown: MarkdownWorkspaceCodec.encode(document), nextTo: url)
    }

    func saveConflictCopy(markdown: String, nextTo url: URL) throws -> URL {
        _ = try MarkdownWorkspaceCodec.decode(markdown)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = url.deletingPathExtension()
            .appendingPathExtension("cue-conflict-\(formatter.string(from: Date()))")
        var copy = base.appendingPathExtension("md")
        var suffix = 2
        while fileManager.fileExists(atPath: copy.path) {
            copy = URL(fileURLWithPath: base.path + "-\(suffix)").appendingPathExtension("md")
            suffix += 1
        }
        try Data(markdown.utf8).write(to: copy, options: .atomic)
        guard try String(contentsOf: copy, encoding: .utf8) == markdown else {
            throw WorkspaceStoreError.writeFailure("conflict copy verification failed")
        }
        return copy
    }

    func fingerprint(for url: URL) throws -> FileFingerprint {
        try fingerprint(for: url, data: Data(contentsOf: url))
    }

    private func fingerprint(for url: URL, data: Data) throws -> FileFingerprint {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let modifiedAt = attributes[.modificationDate] as? Date ?? .distantPast
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? UInt64(data.count)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return FileFingerprint(size: size, modifiedAt: modifiedAt, digest: digest)
    }

    private func createBackup(of url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let directory = url.deletingLastPathComponent().appendingPathComponent(".cue-backups", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let backup = directory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(formatter.string(from: Date())).md")
        try fileManager.copyItem(at: url, to: backup)

        let backups = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "md" }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }

        for oldBackup in backups.dropFirst(backupLimit) {
            try? fileManager.removeItem(at: oldBackup)
        }
    }

    private func sameWorkspaceContent(_ lhs: WorkspaceDocument, _ rhs: WorkspaceDocument) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion &&
            lhs.id == rhs.id &&
            lhs.title == rhs.title &&
            lhs.sections == rhs.sections &&
            lhs.items == rhs.items
    }
}
