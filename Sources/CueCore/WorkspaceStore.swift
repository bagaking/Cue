import CryptoKit
import Foundation

public final class WorkspaceStore {
    private let fileManager: FileManager
    private let backupLimit: Int

    public init(
        fileManager: FileManager = .default,
        backupLimit: Int = 10
    ) {
        self.fileManager = fileManager
        self.backupLimit = max(backupLimit, 10)
    }

    public func create(document: WorkspaceDocument, at url: URL) throws -> FileFingerprint {
        try validatePackageURL(url)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: url.path) else {
            throw WorkspaceStoreError.externalModification
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        do {
            let fingerprint = try write(document: document, to: url, expectedFingerprint: nil)
            return fingerprint
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
    }

    public func load(from url: URL) throws -> (WorkspaceDocument, FileFingerprint) {
        try validatePackageURL(url)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw WorkspaceStoreError.missingFile
        }
        guard isDirectory.boolValue else {
            throw WorkspaceStoreError.invalidDocument("Cue workspaces are `.cue` packages, not single files")
        }

        do {
            let manifestURL = url.appendingPathComponent(WorkspacePackageCodec.manifestPath)
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                throw WorkspaceStoreError.invalidDocument("workspace package has no manifest.yaml")
            }
            let manifest = try WorkspacePackageCodec.decodeManifest(Data(contentsOf: manifestURL))
            var sections: [WorkSection] = []
            for path in manifest.sectionPaths {
                let section = try WorkspacePackageCodec.decodeSection(Data(contentsOf: url.appendingPathComponent(path)))
                guard WorkspacePackageCodec.sectionPath(section) == path else {
                    throw WorkspaceStoreError.invalidDocument("section path does not match its identifier")
                }
                sections.append(section)
            }

            let tombstones = try WorkspacePackageCodec.allTombstones(at: url, fileManager: fileManager)
            guard tombstones.values.allSatisfy({ $0.workspaceID == manifest.workspaceID }) else {
                throw WorkspaceStoreError.invalidDocument("tombstone belongs to a different workspace")
            }
            var items: [WorkItem] = []
            for path in manifest.itemPaths {
                let item = try WorkspacePackageCodec.decodeItem(Data(contentsOf: url.appendingPathComponent(path)), workspaceID: manifest.workspaceID)
                guard WorkspacePackageCodec.itemPath(item) == path else {
                    throw WorkspaceStoreError.invalidDocument("item path does not match its identifier or creation date")
                }
                if let tombstone = tombstones[item.id], tombstone.deletedAt >= item.updatedAt { continue }
                items.append(item)
            }

            guard Set(sections.map(\.id)).count == sections.count else {
                throw WorkspaceStoreError.invalidDocument("duplicate section identifiers")
            }
            guard Set(items.map(\.id)).count == items.count else {
                throw WorkspaceStoreError.invalidDocument("duplicate item identifiers")
            }

            var document = WorkspaceDocument(
                schemaVersion: WorkspacePackageCodec.schemaVersion,
                id: manifest.workspaceID,
                title: manifest.title,
                sections: sections,
                items: items,
                layout: []
            )
            document.ensureInbox()
            let validSectionIDs = Set(document.sections.map(\.id))
            let inboxID = document.inbox.id
            for index in document.items.indices where !validSectionIDs.contains(document.items[index].sectionID) {
                document.items[index].sectionID = inboxID
            }
            document.normalizeOrder()
            let fingerprint = try fingerprint(for: url)
            return (document, fingerprint)
        } catch let error as WorkspaceStoreError {
            throw error
        } catch {
            throw WorkspaceStoreError.invalidDocument(error.localizedDescription)
        }
    }

    @discardableResult
    public func write(
        document source: WorkspaceDocument,
        to url: URL,
        expectedFingerprint: FileFingerprint?
    ) throws -> FileFingerprint {
        try validatePackageURL(url)
        let exists = fileManager.fileExists(atPath: url.path)
        let hasManifest = fileManager.fileExists(atPath: url.appendingPathComponent(WorkspacePackageCodec.manifestPath).path)
        if let expectedFingerprint {
            guard exists else { throw WorkspaceStoreError.missingFile }
            guard try fingerprint(for: url) == expectedFingerprint else {
                throw WorkspaceStoreError.externalModification
            }
        } else if exists, hasManifest {
            throw WorkspaceStoreError.externalModification
        }

        var document = source
        document.ensureInbox()
        document.normalizeOrder()
        document.schemaVersion = WorkspacePackageCodec.schemaVersion

        let previous = hasManifest ? try? load(from: url).0 : nil
        let previousIDs = Set(previous?.items.map(\.id) ?? [])
        let intendedIDs = Set(document.items.map(\.id))
        let deletedIDs = previousIDs.subtracting(intendedIDs)
        let manifest = WorkspacePackageCodec.manifest(for: document)
        let files = try encodedFiles(for: document, manifest: manifest, deletedIDs: deletedIDs)

        let backupURL = hasManifest ? try createBackup(of: url) : nil
        do {
            try apply(files: files, manifest: manifest, to: url)
            let (validated, fingerprint) = try load(from: url)
            let canonicalDocument = try canonicalized(document)
            guard sameWorkspaceContent(validated, canonicalDocument) else {
                throw WorkspaceStoreError.invalidDocument("post-write package did not match the intended workspace")
            }
            return fingerprint
        } catch {
            if let backupURL {
                try? restoreBackup(backupURL, to: url)
            }
            if let storeError = error as? WorkspaceStoreError { throw storeError }
            throw WorkspaceStoreError.writeFailure(error.localizedDescription)
        }
    }

    public func saveConflictCopy(document: WorkspaceDocument, nextTo url: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = url.deletingPathExtension().lastPathComponent
        let parent = url.deletingLastPathComponent()
        var copy = parent.appendingPathComponent("\(stem).cue-conflict-\(formatter.string(from: Date())).cue", isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: copy.path) {
            copy = parent.appendingPathComponent("\(stem).cue-conflict-\(formatter.string(from: Date()))-\(suffix).cue", isDirectory: true)
            suffix += 1
        }
        _ = try create(document: document, at: copy)
        return copy
    }

    public func fingerprint(for url: URL) throws -> FileFingerprint {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw WorkspaceStoreError.missingFile
        }
        guard isDirectory.boolValue else {
            throw WorkspaceStoreError.invalidDocument("workspace path is not a package")
        }

        let files = try sourceFiles(in: url)
        var hasher = SHA256()
        var totalSize: UInt64 = 0
        var modifiedAt = Date.distantPast
        for file in files {
            let relative = relativePath(of: file, to: url)
            let data = try Data(contentsOf: file)
            hasher.update(data: Data(relative.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: data)
            totalSize += UInt64(data.count)
            let values = try file.resourceValues(forKeys: [.contentModificationDateKey])
            modifiedAt = max(modifiedAt, values.contentModificationDate ?? .distantPast)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return FileFingerprint(size: totalSize, modifiedAt: modifiedAt, digest: digest)
    }

    private func encodedFiles(
        for document: WorkspaceDocument,
        manifest: WorkspacePackageCodec.Manifest,
        deletedIDs: Set<UUID>
    ) throws -> [String: Data] {
        var files: [String: Data] = [
            WorkspacePackageCodec.manifestPath: try WorkspacePackageCodec.encodeManifest(manifest),
        ]
        for section in document.sections {
            files[WorkspacePackageCodec.sectionPath(section)] = try WorkspacePackageCodec.encodeSection(section)
        }
        for item in document.items {
            files[WorkspacePackageCodec.itemPath(item)] = try WorkspacePackageCodec.encodeItem(item, workspaceID: document.id)
        }
        for id in deletedIDs {
            let tombstone = WorkspacePackageCodec.Tombstone(workspaceID: document.id, itemID: id, deletedAt: Date())
            files[WorkspacePackageCodec.tombstonePath(for: id)] = try WorkspacePackageCodec.encodeTombstone(tombstone)
        }
        return files
    }

    private func apply(
        files: [String: Data],
        manifest: WorkspacePackageCodec.Manifest,
        to root: URL
    ) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for path in ["sections", "items", "tombstones", "assets/sha256"] {
            try fileManager.createDirectory(at: root.appendingPathComponent(path, isDirectory: true), withIntermediateDirectories: true)
        }

        let previousManifestURL = root.appendingPathComponent(WorkspacePackageCodec.manifestPath)
        let previousManifest = try? WorkspacePackageCodec.decodeManifest(Data(contentsOf: previousManifestURL))
        let manifestData = files[WorkspacePackageCodec.manifestPath]!

        for path in files.keys.sorted() where path != WorkspacePackageCodec.manifestPath {
            let destination = root.appendingPathComponent(path)
            let data = files[path]!
            if (try? Data(contentsOf: destination)) != data {
                try atomicWrite(data, to: destination)
            }
        }

        if (try? Data(contentsOf: previousManifestURL)) != manifestData {
            try atomicWrite(manifestData, to: previousManifestURL)
        }

        let retainedPaths = Set(manifest.sectionPaths + manifest.itemPaths)
        let stalePaths = Set((previousManifest?.sectionPaths ?? []) + (previousManifest?.itemPaths ?? []))
            .subtracting(retainedPaths)
        for path in stalePaths {
            let staleURL = root.appendingPathComponent(path)
            if fileManager.fileExists(atPath: staleURL.path) { try fileManager.removeItem(at: staleURL) }
        }
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".\(url.lastPathComponent).cue-tmp-\(UUID().uuidString)")
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

    private func createBackup(of url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent().appendingPathComponent(".cue-backups", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let backup = directory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(formatter.string(from: Date())).cue", isDirectory: true)
        try fileManager.copyItem(at: url, to: backup)

        let backups = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "cue" }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
        for oldBackup in backups.dropFirst(backupLimit) { try? fileManager.removeItem(at: oldBackup) }
        return backup
    }

    private func restoreBackup(_ backup: URL, to url: URL) throws {
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        try fileManager.copyItem(at: backup, to: url)
    }

    private func sourceFiles(in root: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true
            }
            .sorted { relativePath(of: $0, to: root) < relativePath(of: $1, to: root) }
    }

    private func relativePath(of url: URL, to root: URL) -> String {
        String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func validatePackageURL(_ url: URL) throws {
        guard url.pathExtension.lowercased() == "cue" else {
            throw WorkspaceStoreError.invalidDocument("workspace packages must use the .cue extension")
        }
    }

    private func canonicalized(_ source: WorkspaceDocument) throws -> WorkspaceDocument {
        var document = source
        document.ensureInbox()
        document.normalizeOrder()
        document.schemaVersion = WorkspacePackageCodec.schemaVersion
        document.sections = try document.sections.map {
            try WorkspacePackageCodec.decodeSection(WorkspacePackageCodec.encodeSection($0))
        }
        document.items = try document.items.map {
            try WorkspacePackageCodec.decodeItem(
                WorkspacePackageCodec.encodeItem($0, workspaceID: document.id),
                workspaceID: document.id
            )
        }
        document.layout = []
        return document
    }

    private func sameWorkspaceContent(_ lhs: WorkspaceDocument, _ rhs: WorkspaceDocument) -> Bool {
        lhs.id == rhs.id &&
            lhs.title == rhs.title &&
            Dictionary(uniqueKeysWithValues: lhs.sections.map { ($0.id, $0) }) == Dictionary(uniqueKeysWithValues: rhs.sections.map { ($0.id, $0) }) &&
            Dictionary(uniqueKeysWithValues: lhs.items.map { ($0.id, $0) }) == Dictionary(uniqueKeysWithValues: rhs.items.map { ($0.id, $0) })
    }
}
