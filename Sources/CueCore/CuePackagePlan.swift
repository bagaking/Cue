import CryptoKit
import Foundation

public struct CueRecordRevision: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard CuePackagePlanner.isLowercaseASCIIRevision(rawValue) else { return nil }
        self.rawValue = rawValue
    }
}

public struct CuePackageRevision: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard CuePackagePlanner.isLowercaseASCIIRevision(rawValue) else { return nil }
        self.rawValue = rawValue
    }
}

public enum CuePackageReadOnlyReason: Equatable, Sendable {
    case newerSchema(Int)
    case unsupportedRequiredFeatures([String])
    case unknownLegacyManifestMetadata([String])
    case unlistedLegacyManagedRecords([String])
    case unpreservableLegacyItemMetadata([String])
    case nonemptyAssets([String])
}

public enum CuePackageWriteCapability: Equatable, Sendable {
    case writableSchema3
    case requiresVerifiedSchema2Migration
    case readOnly(CuePackageReadOnlyReason)
}

public enum CuePackageTombstoneBinding: Equatable, Sendable {
    case observed(recordRevision: CueRecordRevision)
    case legacyUnbound(deletedAt: Date)
}

public struct CuePackageTombstone: Equatable, Sendable {
    public let itemID: UUID
    public let workspaceID: UUID
    public let binding: CuePackageTombstoneBinding

    public init(itemID: UUID, workspaceID: UUID, binding: CuePackageTombstoneBinding) {
        self.itemID = itemID
        self.workspaceID = workspaceID
        self.binding = binding
    }
}

public enum CuePackageConflict: Equatable, Sendable {
    case editDelete(itemID: UUID, recordRevision: CueRecordRevision, observedRevision: CueRecordRevision)
    case legacyDeleteEdit(itemID: UUID, recordRevision: CueRecordRevision, deletedAt: Date)
}

public struct CuePackageItemRecord: Equatable, Sendable {
    public let path: String
    public let record: CueItemRecord
    public let revision: CueRecordRevision
    public let data: Data

    public init(path: String, record: CueItemRecord, revision: CueRecordRevision, data: Data) {
        self.path = path
        self.record = record
        self.revision = revision
        self.data = data
    }
}

public struct CuePackageInspection: Equatable, Sendable {
    public let schemaVersion: Int
    public let workspaceID: UUID
    public let title: String
    public let requiredFeatures: [String]
    public let writeCapability: CuePackageWriteCapability
    public let document: WorkspaceDocument?
    public let itemRecords: [CuePackageItemRecord]
    public let tombstones: [CuePackageTombstone]
    public let conflicts: [CuePackageConflict]
    public let unlistedManagedPaths: [String]
    public let packageRevision: CuePackageRevision
    let rawDirectories: [String]
    let rawFiles: [String: Data]

    init(
        schemaVersion: Int,
        workspaceID: UUID,
        title: String,
        requiredFeatures: [String],
        writeCapability: CuePackageWriteCapability,
        document: WorkspaceDocument?,
        itemRecords: [CuePackageItemRecord],
        tombstones: [CuePackageTombstone],
        conflicts: [CuePackageConflict],
        unlistedManagedPaths: [String],
        packageRevision: CuePackageRevision,
        rawDirectories: [String],
        rawFiles: [String: Data]
    ) {
        self.schemaVersion = schemaVersion
        self.workspaceID = workspaceID
        self.title = title
        self.requiredFeatures = requiredFeatures
        self.writeCapability = writeCapability
        self.document = document
        self.itemRecords = itemRecords
        self.tombstones = tombstones
        self.conflicts = conflicts
        self.unlistedManagedPaths = unlistedManagedPaths
        self.packageRevision = packageRevision
        self.rawDirectories = rawDirectories
        self.rawFiles = rawFiles
    }
}

public struct CuePlannedPackageFile: Equatable, Sendable {
    public let path: String
    public let data: Data

    public init(path: String, data: Data) {
        self.path = path
        self.data = data
    }
}

/// An in-memory, fully validated package image. This type deliberately has no
/// filesystem publication method; coordinated staging and replacement belong
/// to the later transaction slice.
public struct CueSchema3PackagePlan: Equatable, Sendable {
    public let sourcePackageRevision: CuePackageRevision?
    public let targetPackageRevision: CuePackageRevision
    public let directories: [String]
    public let files: [CuePlannedPackageFile]

    init(
        sourcePackageRevision: CuePackageRevision?,
        targetPackageRevision: CuePackageRevision,
        directories: [String],
        files: [CuePlannedPackageFile]
    ) {
        self.sourcePackageRevision = sourcePackageRevision
        self.targetPackageRevision = targetPackageRevision
        self.directories = directories
        self.files = files
    }
}

/// Foundation-only schema inspection and migration planning. It never writes
/// to the observed package and is not a second `WorkspaceStore`.
public enum CuePackagePlanner {
    public static let schemaVersion = 3

    private static let manifestPath = "manifest.yaml"
    private static let baseDirectories = ["assets", "assets/sha256", "items", "sections", "tombstones"]
    private static let schema3ManifestKeys: Set<String> = [
        "cue_schema", "cue_workspace_id", "title", "required_features",
    ]
    private static let schema2ManifestKeys: Set<String> = [
        "cue_schema", "cue_workspace_id", "title", "sections", "items",
    ]
    private static let schema2ItemKeys: Set<String> = [
        "cue_schema", "cue_workspace_id", "id", "kind", "state", "section_id", "source",
        "sensitivity", "created_at", "updated_at", "completed_at", "archived_at", "pinned",
        "order", "merged_from", "merged_into",
    ]
    private static let schema3ItemKeys: Set<String> = [
        "schema", "workspace_id", "id", "kind", "state", "section_id", "source",
        "sensitivity", "created_at", "updated_at", "completed_at", "archived_at", "pinned",
        "order", "merged_from", "merged_into",
    ]
    private static let sourceKeys: Set<String> = [
        "appName", "bundleIdentifier", "windowTitle", "url",
    ]
    private static let schema2TombstoneKeys: Set<String> = [
        "cue_workspace_id", "item_id", "deleted_at",
    ]

    private enum EntryKind: String {
        case directory = "D"
        case file = "F"
    }

    private struct TreeEntry {
        var path: String
        var kind: EntryKind
    }

    private struct TreeSnapshot {
        var entries: [TreeEntry]
        var files: [String: Data]
        var revision: CuePackageRevision
    }

    private struct ManifestHeader: Decodable {
        var schemaVersion: Int
        var workspaceID: UUID
        var title: String
        var requiredFeatures: [String]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "cue_schema"
            case workspaceID = "cue_workspace_id"
            case title
            case requiredFeatures = "required_features"
        }
    }

    private struct Schema3Manifest: Codable, Equatable {
        var schemaVersion: Int
        var workspaceID: UUID
        var title: String
        var requiredFeatures: [String]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "cue_schema"
            case workspaceID = "cue_workspace_id"
            case title
            case requiredFeatures = "required_features"
        }
    }

    private struct Schema3SectionRecord: Codable {
        var schemaVersion: Int
        var workspaceID: UUID
        var id: UUID
        var title: String
        var order: Double
        var isCollapsed: Bool

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema"
            case workspaceID = "workspace_id"
            case id
            case title
            case order
            case isCollapsed = "is_collapsed"
        }

        init(section: WorkSection, workspaceID: UUID) {
            schemaVersion = CuePackagePlanner.schemaVersion
            self.workspaceID = workspaceID
            id = section.id
            title = section.title
            order = section.order
            isCollapsed = section.isCollapsed
        }

        var section: WorkSection {
            WorkSection(id: id, title: title, order: order, isCollapsed: isCollapsed)
        }
    }

    private struct Schema3TombstoneRecord: Codable {
        var schemaVersion: Int
        var workspaceID: UUID
        var itemID: UUID
        var kind: String
        var observedRevision: String?
        var deletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "cue_schema"
            case workspaceID = "cue_workspace_id"
            case itemID = "item_id"
            case kind
            case observedRevision = "observed_revision"
            case deletedAt = "deleted_at"
        }
    }

    private struct LegacyConflictEvidence: Equatable {
        var itemID: UUID
        var deletedAt: Date
    }

    /// Reads exactly once from a URL supplied by the caller's coordinated
    /// accessor. Slice C owns creation of that accessor and all CAS behavior.
    public static func inspect(
        atCoordinatedAccessorURL url: URL,
        fileManager: FileManager = .default
    ) throws -> CuePackageInspection {
        let snapshot = try readSnapshot(at: url, fileManager: fileManager)
        do {
            return try inspect(snapshot)
        } catch let error as WorkspaceStoreError {
            throw error
        } catch {
            throw invalid(error.localizedDescription)
        }
    }

    public static func planSchema3Migration(
        from inspection: CuePackageInspection
    ) throws -> CueSchema3PackagePlan {
        do {
            return try makeSchema3MigrationPlan(from: inspection)
        } catch let error as WorkspaceStoreError {
            throw error
        } catch {
            throw invalid(error.localizedDescription)
        }
    }

    static func planSchema3Creation(for source: WorkspaceDocument) throws -> CueSchema3PackagePlan {
        try makeSchema3WritePlan(base: nil, sourceRevision: nil, source: source)
    }

    static func planSchema3Write(
        from inspection: CuePackageInspection,
        document source: WorkspaceDocument
    ) throws -> CueSchema3PackagePlan {
        let base: CuePackageInspection
        switch inspection.writeCapability {
        case .requiresVerifiedSchema2Migration:
            let migration = try makeSchema3MigrationPlan(from: inspection)
            base = try inspectSchema3(snapshotForPlan(directories: migration.directories, files: migration.files))
        case .writableSchema3:
            base = inspection
        case let .readOnly(reason):
            throw WorkspaceStoreError.readOnly(reason)
        }
        guard base.conflicts.isEmpty else {
            throw invalid("workspace has unresolved storage conflicts")
        }
        return try makeSchema3WritePlan(
            base: base,
            sourceRevision: inspection.packageRevision,
            source: source
        )
    }

    private static func makeSchema3WritePlan(
        base: CuePackageInspection?,
        sourceRevision: CuePackageRevision?,
        source: WorkspaceDocument
    ) throws -> CueSchema3PackagePlan {
        let document = try normalizedDraft(source)
        if let base {
            guard base.workspaceID == document.id else {
                throw invalid("draft belongs to a different workspace")
            }
            if case let .readOnly(reason) = base.writeCapability {
                throw WorkspaceStoreError.readOnly(reason)
            }
        }

        var plannedFiles = base?.rawFiles ?? [:]
        plannedFiles = plannedFiles.filter {
            !$0.key.hasPrefix("sections/") && !$0.key.hasPrefix("items/") && $0.key != manifestPath
        }
        plannedFiles[manifestPath] = try encodeSchema3Manifest(.init(
            schemaVersion: schemaVersion,
            workspaceID: document.id,
            title: document.title,
            requiredFeatures: []
        ))

        let baseSections = Dictionary(uniqueKeysWithValues: (base?.document?.sections ?? []).map { ($0.id, $0) })
        for section in document.sections {
            let path = schema3SectionPath(section)
            if baseSections[section.id] == section, let original = base?.rawFiles[path] {
                plannedFiles[path] = original
            } else {
                plannedFiles[path] = try encoder().encode(
                    Schema3SectionRecord(section: section, workspaceID: document.id)
                ).addingTrailingNewline()
            }
        }

        let baseItems = Dictionary(uniqueKeysWithValues: (base?.itemRecords ?? []).map {
            ($0.record.item.id, $0)
        })
        let tombstoneIDs = Set((base?.tombstones ?? []).map(\.itemID))
        let intendedIDs = Set(document.items.map(\.id))
        guard intendedIDs.isDisjoint(with: tombstoneIDs) else {
            throw invalid("draft cannot revive an item while its tombstone is retained")
        }
        for item in document.items {
            var record = baseItems[item.id]?.record ?? CueItemRecord(workspaceID: document.id, item: item)
            record.workspaceID = document.id
            record.item = item
            plannedFiles[schema3ItemPath(item)] = try CueItemRecordCodec.encode(record)
        }
        for removed in baseItems.values where !intendedIDs.contains(removed.record.item.id) &&
            !tombstoneIDs.contains(removed.record.item.id) {
            let tombstone = Schema3TombstoneRecord(
                schemaVersion: schemaVersion,
                workspaceID: document.id,
                itemID: removed.record.item.id,
                kind: "observed",
                observedRevision: removed.revision.rawValue,
                deletedAt: nil
            )
            plannedFiles[legacyTombstonePath(removed.record.item.id)] = try encoder().encode(tombstone).addingTrailingNewline()
        }

        let directories = plannedDirectories(for: plannedFiles.keys)
        let files = plannedFiles.keys.sorted().map { CuePlannedPackageFile(path: $0, data: plannedFiles[$0]!) }
        let targetSnapshot = try snapshotForPlan(directories: directories, files: files)
        let verified = try inspectSchema3(targetSnapshot)
        guard verified.writeCapability == .writableSchema3,
              verified.conflicts.isEmpty,
              let verifiedDocument = verified.document,
              sameWorkspaceContent(verifiedDocument, document) else {
            throw invalid("schema-3 write plan did not preserve the complete intended document")
        }
        return CueSchema3PackagePlan(
            sourcePackageRevision: sourceRevision,
            targetPackageRevision: targetSnapshot.revision,
            directories: directories,
            files: files
        )
    }

    private static func makeSchema3MigrationPlan(
        from inspection: CuePackageInspection
    ) throws -> CueSchema3PackagePlan {
        guard inspection.schemaVersion == WorkspacePackageCodec.schemaVersion,
              inspection.writeCapability == .requiresVerifiedSchema2Migration else {
            throw invalid("package inspection is not eligible for verified schema-2 migration")
        }
        let source = snapshot(from: inspection)
        guard source.revision == inspection.packageRevision else {
            throw invalid("package inspection raw closure does not match its revision")
        }
        let manifestData = try requiredFile(manifestPath, in: source)
        guard let document = inspection.document else {
            throw invalid("schema-2 package did not produce a migration document")
        }
        let legacyManifest = try WorkspacePackageCodec.decodeManifest(manifestData)
        var plannedFiles: [String: Data] = [
            manifestPath: try encodeSchema3Manifest(.init(
                schemaVersion: schemaVersion,
                workspaceID: document.id,
                title: document.title,
                requiredFeatures: []
            )),
        ]

        for path in legacyManifest.sectionPaths {
            let legacySectionData = try requiredFile(path, in: source)
            _ = try CueItemRecordCodec.parseJSONObjectEnvelope(legacySectionData)
            let legacySection = try WorkspacePackageCodec.decodeSection(legacySectionData)
            plannedFiles[path] = try encoder().encode(
                Schema3SectionRecord(section: legacySection, workspaceID: document.id)
            ).addingTrailingNewline()
        }
        for path in legacyManifest.itemPaths {
            let data = try requiredFile(path, in: source)
            let item = try decodeLegacyItem(data, workspaceID: document.id).item
            plannedFiles[schema3ItemPath(item)] = try migrateLegacyItem(data, item: item, workspaceID: document.id)
        }

        for entry in source.entries where entry.kind == .file && entry.path.hasPrefix("tombstones/") {
            let data = try requiredFile(entry.path, in: source)
            plannedFiles[entry.path] = try migrateLegacyTombstone(data, workspaceID: document.id)
        }
        let directories = plannedDirectories(for: plannedFiles.keys)
        let files = plannedFiles.keys.sorted().map { CuePlannedPackageFile(path: $0, data: plannedFiles[$0]!) }
        let planSnapshot = try snapshotForPlan(directories: directories, files: files)
        let verified = try inspectSchema3(planSnapshot)
        guard migrationClosureMatches(source: inspection, target: verified) else {
            throw invalid("schema-3 package plan did not preserve the complete source closure")
        }
        return CueSchema3PackagePlan(
            sourcePackageRevision: inspection.packageRevision,
            targetPackageRevision: planSnapshot.revision,
            directories: directories,
            files: files
        )
    }

    private static func normalizedDraft(_ source: WorkspaceDocument) throws -> WorkspaceDocument {
        var document = source
        document.ensureInbox()
        document.normalizeOrder()
        document.schemaVersion = schemaVersion
        document.layout = []
        for index in document.items.indices {
            document.items[index].contentHash = ContentHasher.hash(document.items[index].body)
            document.items[index] = try CueItemRecordCodec.decode(
                CueItemRecordCodec.encode(CueItemRecord(
                    workspaceID: document.id,
                    item: document.items[index]
                ))
            ).item
        }
        try requireUnique(document.sections.map(\.id), label: "section")
        try requireUnique(document.items.map(\.id), label: "item")
        let sectionIDs = Set(document.sections.map(\.id))
        guard document.items.allSatisfy({ sectionIDs.contains($0.sectionID) }) else {
            throw invalid("draft item references a nonexistent section")
        }
        return document
    }

    private static func sameWorkspaceContent(_ lhs: WorkspaceDocument, _ rhs: WorkspaceDocument) -> Bool {
        lhs.id == rhs.id &&
            lhs.title == rhs.title &&
            Dictionary(uniqueKeysWithValues: lhs.sections.map { ($0.id, $0) }) ==
                Dictionary(uniqueKeysWithValues: rhs.sections.map { ($0.id, $0) }) &&
            Dictionary(uniqueKeysWithValues: lhs.items.map { ($0.id, $0) }) ==
                Dictionary(uniqueKeysWithValues: rhs.items.map { ($0.id, $0) })
    }

    private static func inspect(_ snapshot: TreeSnapshot) throws -> CuePackageInspection {
        let manifestData = try requiredFile(manifestPath, in: snapshot)
        let envelope = try CueItemRecordCodec.parseJSONObjectEnvelope(manifestData)
        let header = try decoder().decode(ManifestHeader.self, from: manifestData)
        guard header.schemaVersion >= WorkspacePackageCodec.schemaVersion else {
            throw invalid("workspace package schema \(header.schemaVersion) is unsupported")
        }

        if header.schemaVersion > schemaVersion {
            return capabilityOnlyInspection(
                header: header,
                capability: .readOnly(.newerSchema(header.schemaVersion)),
                snapshot: snapshot,
                revision: snapshot.revision
            )
        }
        if header.schemaVersion == WorkspacePackageCodec.schemaVersion {
            return try inspectSchema2(snapshot)
        }

        guard Set(envelope.members.map(\.key)) == schema3ManifestKeys else {
            throw invalid("schema-3 manifest must contain exactly cue_schema, cue_workspace_id, title, and required_features")
        }
        let manifest = try decoder().decode(Schema3Manifest.self, from: manifestData)
        guard Set(manifest.requiredFeatures).count == manifest.requiredFeatures.count,
              manifest.requiredFeatures.allSatisfy(isFeatureName) else {
            throw invalid("schema-3 manifest required_features are invalid")
        }
        let unsupported = manifest.requiredFeatures.sorted()
        if !unsupported.isEmpty {
            return capabilityOnlyInspection(
                header: header,
                capability: .readOnly(.unsupportedRequiredFeatures(unsupported)),
                snapshot: snapshot,
                revision: snapshot.revision
            )
        }
        return try inspectSchema3(snapshot)
    }

    private static func inspectSchema2(_ snapshot: TreeSnapshot) throws -> CuePackageInspection {
        try validateTopology(snapshot, itemSuffix: ".md")
        let manifestData = try requiredFile(manifestPath, in: snapshot)
        let manifestEnvelope = try CueItemRecordCodec.parseJSONObjectEnvelope(manifestData)
        let manifest = try WorkspacePackageCodec.decodeManifest(manifestData)
        for path in manifest.sectionPaths + manifest.itemPaths where !isStrictRelativePath(path) {
            throw invalid("schema-2 manifest contains an unsafe path")
        }

        var sections: [WorkSection] = []
        for path in manifest.sectionPaths {
            let sectionData = try requiredFile(path, in: snapshot)
            _ = try CueItemRecordCodec.parseJSONObjectEnvelope(sectionData)
            let section = try WorkspacePackageCodec.decodeSection(sectionData)
            guard WorkspacePackageCodec.sectionPath(section) == path else {
                throw invalid("section path does not match its identifier")
            }
            sections.append(section)
        }
        try requireUnique(sections.map(\.id), label: "section")
        guard !sections.isEmpty else { throw invalid("workspace has no section records") }

        var itemRecords: [CuePackageItemRecord] = []
        var itemMetadataCollisions: [String] = []
        for path in manifest.itemPaths {
            let data = try requiredFile(path, in: snapshot)
            let legacy = try decodeLegacyItem(data, workspaceID: manifest.workspaceID)
            let item = legacy.item
            guard WorkspacePackageCodec.itemPath(item) == path else {
                throw invalid("item path does not match its identifier or creation date")
            }
            let collisions = Set(legacy.envelope.members.map(\.key))
                .subtracting(schema2ItemKeys)
                .intersection(schema3ItemKeys)
                .sorted()
            itemMetadataCollisions.append(contentsOf: collisions.map { "\(path)#\($0)" })
            itemRecords.append(.init(
                path: path,
                record: CueItemRecord(workspaceID: manifest.workspaceID, item: item),
                revision: exactRevision(data),
                data: data
            ))
        }
        try requireUnique(itemRecords.map { $0.record.item.id }, label: "item")
        try validateSectionReferences(itemRecords, sections: sections)

        let tombstones = try legacyTombstones(in: snapshot, workspaceID: manifest.workspaceID)
        let recordsByID = Dictionary(uniqueKeysWithValues: itemRecords.map { ($0.record.item.id, $0) })
        let conflicts = tombstones.compactMap { tombstone -> CuePackageConflict? in
            guard let record = recordsByID[tombstone.itemID],
                  case let .legacyUnbound(deletedAt) = tombstone.binding else { return nil }
            return .legacyDeleteEdit(itemID: tombstone.itemID, recordRevision: record.revision, deletedAt: deletedAt)
        }

        let actualSections = Set(snapshot.entries.filter {
            $0.kind == .file && $0.path.hasPrefix("sections/")
        }.map(\.path))
        let actualItems = Set(snapshot.entries.filter {
            $0.kind == .file && $0.path.hasPrefix("items/")
        }.map(\.path))
        let listedSections = Set(manifest.sectionPaths)
        let listedItems = Set(manifest.itemPaths)
        let unlisted = actualSections.subtracting(listedSections)
            .union(actualItems.subtracting(listedItems))
            .sorted()
        let unknownManifestKeys = Set(manifestEnvelope.members.map(\.key))
            .subtracting(schema2ManifestKeys)
            .sorted()
        let assetPaths = assetFilePaths(in: snapshot)
        let capability: CuePackageWriteCapability
        if !unknownManifestKeys.isEmpty {
            capability = .readOnly(.unknownLegacyManifestMetadata(unknownManifestKeys))
        } else if !unlisted.isEmpty {
            capability = .readOnly(.unlistedLegacyManagedRecords(unlisted))
        } else if !itemMetadataCollisions.isEmpty {
            capability = .readOnly(.unpreservableLegacyItemMetadata(itemMetadataCollisions.sorted()))
        } else if !assetPaths.isEmpty {
            capability = .readOnly(.nonemptyAssets(assetPaths))
        } else {
            capability = .requiresVerifiedSchema2Migration
        }

        let document = WorkspaceDocument(
            schemaVersion: WorkspacePackageCodec.schemaVersion,
            id: manifest.workspaceID,
            title: manifest.title,
            sections: sections,
            items: itemRecords.map { $0.record.item },
            layout: []
        )
        return CuePackageInspection(
            schemaVersion: WorkspacePackageCodec.schemaVersion,
            workspaceID: manifest.workspaceID,
            title: manifest.title,
            requiredFeatures: [],
            writeCapability: capability,
            document: document,
            itemRecords: itemRecords.sorted { $0.path < $1.path },
            tombstones: tombstones.sorted { $0.itemID.uuidString < $1.itemID.uuidString },
            conflicts: conflicts.sorted(by: conflictOrder),
            unlistedManagedPaths: unlisted,
            packageRevision: snapshot.revision,
            rawDirectories: directoryPaths(in: snapshot),
            rawFiles: snapshot.files
        )
    }

    private static func inspectSchema3(_ snapshot: TreeSnapshot) throws -> CuePackageInspection {
        try validateTopology(snapshot, itemSuffix: ".cue.md")
        let manifestData = try requiredFile(manifestPath, in: snapshot)
        let envelope = try CueItemRecordCodec.parseJSONObjectEnvelope(manifestData)
        guard Set(envelope.members.map(\.key)) == schema3ManifestKeys else {
            throw invalid("schema-3 manifest must contain exactly cue_schema, cue_workspace_id, title, and required_features")
        }
        let manifest = try decoder().decode(Schema3Manifest.self, from: manifestData)
        guard manifest.schemaVersion == schemaVersion else {
            throw invalid("workspace package schema \(manifest.schemaVersion) is unsupported")
        }

        var sections: [WorkSection] = []
        for entry in snapshot.entries where entry.kind == .file && entry.path.hasPrefix("sections/") {
            let sectionData = try requiredFile(entry.path, in: snapshot)
            _ = try CueItemRecordCodec.parseJSONObjectEnvelope(sectionData)
            let record = try decoder().decode(
                Schema3SectionRecord.self,
                from: sectionData
            )
            guard record.schemaVersion == schemaVersion else {
                throw invalid("section schema is unsupported")
            }
            guard record.workspaceID == manifest.workspaceID else {
                throw invalid("section belongs to a different workspace")
            }
            let section = record.section
            guard schema3SectionPath(section) == entry.path else {
                throw invalid("section path does not match its identifier")
            }
            sections.append(section)
        }
        try requireUnique(sections.map(\.id), label: "section")
        guard !sections.isEmpty else { throw invalid("workspace has no section records") }

        var itemRecords: [CuePackageItemRecord] = []
        for entry in snapshot.entries where entry.kind == .file && entry.path.hasPrefix("items/") {
            let data = try requiredFile(entry.path, in: snapshot)
            let record = try CueItemRecordCodec.decode(data)
            guard record.workspaceID == manifest.workspaceID else {
                throw invalid("item belongs to a different workspace")
            }
            guard schema3ItemPath(record.item) == entry.path else {
                throw invalid("item path does not match its identifier or UTC creation date")
            }
            itemRecords.append(.init(path: entry.path, record: record, revision: exactRevision(data), data: data))
        }
        try requireUnique(itemRecords.map { $0.record.item.id }, label: "item")
        try validateSectionReferences(itemRecords, sections: sections)

        let tombstones = try schema3Tombstones(in: snapshot, workspaceID: manifest.workspaceID)
        let recordsByID = Dictionary(uniqueKeysWithValues: itemRecords.map { ($0.record.item.id, $0) })
        var suppressed = Set<UUID>()
        var conflicts: [CuePackageConflict] = []
        for tombstone in tombstones {
            guard let record = recordsByID[tombstone.itemID] else { continue }
            switch tombstone.binding {
            case let .observed(observedRevision):
                if observedRevision == record.revision {
                    suppressed.insert(tombstone.itemID)
                } else {
                    conflicts.append(.editDelete(
                        itemID: tombstone.itemID,
                        recordRevision: record.revision,
                        observedRevision: observedRevision
                    ))
                }
            case let .legacyUnbound(deletedAt):
                conflicts.append(.legacyDeleteEdit(
                    itemID: tombstone.itemID,
                    recordRevision: record.revision,
                    deletedAt: deletedAt
                ))
            }
        }

        let retainedItems = itemRecords
            .filter { !suppressed.contains($0.record.item.id) }
            .map { $0.record.item }
        let document = WorkspaceDocument(
            schemaVersion: schemaVersion,
            id: manifest.workspaceID,
            title: manifest.title,
            sections: sections,
            items: retainedItems,
            layout: []
        )
        let assetPaths = assetFilePaths(in: snapshot)
        let capability: CuePackageWriteCapability = assetPaths.isEmpty
            ? .writableSchema3
            : .readOnly(.nonemptyAssets(assetPaths))
        return CuePackageInspection(
            schemaVersion: schemaVersion,
            workspaceID: manifest.workspaceID,
            title: manifest.title,
            requiredFeatures: manifest.requiredFeatures,
            writeCapability: capability,
            document: document,
            itemRecords: itemRecords.sorted { $0.path < $1.path },
            tombstones: tombstones.sorted { $0.itemID.uuidString < $1.itemID.uuidString },
            conflicts: conflicts.sorted(by: conflictOrder),
            unlistedManagedPaths: [],
            packageRevision: snapshot.revision,
            rawDirectories: directoryPaths(in: snapshot),
            rawFiles: snapshot.files
        )
    }

    private static func capabilityOnlyInspection(
        header: ManifestHeader,
        capability: CuePackageWriteCapability,
        snapshot: TreeSnapshot,
        revision: CuePackageRevision
    ) -> CuePackageInspection {
        CuePackageInspection(
            schemaVersion: header.schemaVersion,
            workspaceID: header.workspaceID,
            title: header.title,
            requiredFeatures: header.requiredFeatures ?? [],
            writeCapability: capability,
            document: nil,
            itemRecords: [],
            tombstones: [],
            conflicts: [],
            unlistedManagedPaths: [],
            packageRevision: revision,
            rawDirectories: directoryPaths(in: snapshot),
            rawFiles: snapshot.files
        )
    }

    private static func validateTopology(_ snapshot: TreeSnapshot, itemSuffix: String) throws {
        let entries = Dictionary(uniqueKeysWithValues: snapshot.entries.map { ($0.path, $0.kind) })
        guard entries[manifestPath] == .file else { throw invalid("workspace package has no regular manifest.yaml") }
        for directory in baseDirectories where entries[directory] != .directory {
            throw invalid("workspace package is missing controlled directory \(directory)")
        }

        let allowedRoot = Set([manifestPath, "assets", "items", "sections", "tombstones"])
        for entry in snapshot.entries {
            let components = entry.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard let root = components.first, allowedRoot.contains(root) else {
                throw invalid("workspace package contains an unexpected root entry")
            }
            switch root {
            case manifestPath:
                guard components.count == 1, entry.kind == .file else { throw invalid("manifest.yaml has an invalid type") }
            case "sections":
                if components.count == 1 { continue }
                guard components.count == 2,
                      entry.kind == .file,
                      canonicalUUIDStem(components[1], suffix: ".yaml") != nil else {
                    throw invalid("sections contains an unexpected depth, type, extension, or identifier")
                }
            case "tombstones":
                if components.count == 1 { continue }
                guard components.count == 2,
                      entry.kind == .file,
                      canonicalUUIDStem(components[1], suffix: ".json") != nil else {
                    throw invalid("tombstones contains an unexpected depth, type, extension, or identifier")
                }
            case "items":
                if components.count == 1 { continue }
                if components.count == 2 {
                    guard entry.kind == .directory, isYear(components[1]) else {
                        throw invalid("items contains an invalid UTC year directory")
                    }
                } else if components.count == 3 {
                    guard entry.kind == .directory,
                          isYear(components[1]),
                          isMonth(components[2]) else {
                        throw invalid("items contains an invalid UTC month directory")
                    }
                } else if components.count == 4 {
                    guard entry.kind == .file,
                          isYear(components[1]),
                          isMonth(components[2]),
                          canonicalUUIDStem(components[3], suffix: itemSuffix) != nil else {
                        throw invalid("items contains an unexpected type, extension, or identifier")
                    }
                } else {
                    throw invalid("items contains an unexpected depth")
                }
            case "assets":
                if components.count == 1 { continue }
                if components.count == 2 {
                    guard components[1] == "sha256", entry.kind == .directory else {
                        throw invalid("assets contains an unexpected directory")
                    }
                } else if components.count == 3 {
                    guard components[1] == "sha256",
                          entry.kind == .file,
                          isSHA256(components[2]) else {
                        throw invalid("assets/sha256 contains an invalid blob path")
                    }
                } else {
                    throw invalid("assets contains an unexpected depth")
                }
            default:
                throw invalid("workspace package contains an unexpected entry")
            }
        }
    }

    private static func legacyTombstones(
        in snapshot: TreeSnapshot,
        workspaceID: UUID
    ) throws -> [CuePackageTombstone] {
        var tombstones: [CuePackageTombstone] = []
        for entry in snapshot.entries where entry.kind == .file && entry.path.hasPrefix("tombstones/") {
            let data = try requiredFile(entry.path, in: snapshot)
            _ = try CueItemRecordCodec.parseJSONObjectEnvelope(data)
            let record = try WorkspacePackageCodec.decodeTombstone(data)
            guard record.workspaceID == workspaceID else { throw invalid("tombstone belongs to a different workspace") }
            guard legacyTombstonePath(record.itemID) == entry.path else {
                throw invalid("tombstone path does not match its item identifier")
            }
            tombstones.append(.init(
                itemID: record.itemID,
                workspaceID: record.workspaceID,
                binding: .legacyUnbound(deletedAt: record.deletedAt)
            ))
        }
        try requireUnique(tombstones.map(\.itemID), label: "tombstone")
        return tombstones
    }

    private static func schema3Tombstones(
        in snapshot: TreeSnapshot,
        workspaceID: UUID
    ) throws -> [CuePackageTombstone] {
        var tombstones: [CuePackageTombstone] = []
        for entry in snapshot.entries where entry.kind == .file && entry.path.hasPrefix("tombstones/") {
            let data = try requiredFile(entry.path, in: snapshot)
            _ = try CueItemRecordCodec.parseJSONObjectEnvelope(data)
            let record = try decoder().decode(Schema3TombstoneRecord.self, from: data)
            guard record.schemaVersion == schemaVersion else { throw invalid("tombstone schema is unsupported") }
            guard record.workspaceID == workspaceID else { throw invalid("tombstone belongs to a different workspace") }
            guard legacyTombstonePath(record.itemID) == entry.path else {
                throw invalid("tombstone path does not match its item identifier")
            }
            let binding: CuePackageTombstoneBinding
            switch record.kind {
            case "observed":
                guard let rawRevision = record.observedRevision,
                      let revision = CueRecordRevision(rawValue: rawRevision),
                      record.deletedAt == nil else {
                    throw invalid("observed tombstone must bind one exact record revision")
                }
                binding = .observed(recordRevision: revision)
            case "legacy_unbound":
                guard record.observedRevision == nil, let deletedAt = record.deletedAt else {
                    throw invalid("legacyUnbound tombstone must retain only timestamp provenance")
                }
                binding = .legacyUnbound(deletedAt: deletedAt)
            default:
                throw invalid("tombstone kind is unsupported")
            }
            tombstones.append(.init(itemID: record.itemID, workspaceID: record.workspaceID, binding: binding))
        }
        try requireUnique(tombstones.map(\.itemID), label: "tombstone")
        return tombstones
    }

    private static func migrateLegacyItem(_ data: Data, item: WorkItem, workspaceID: UUID) throws -> Data {
        let legacy = try decodeLegacyItem(data, workspaceID: workspaceID)
        let unknown = legacy.envelope.members.filter { !schema2ItemKeys.contains($0.key) }
        let unknownKeys = Set(unknown.map(\.key))
        guard unknownKeys.isDisjoint(with: schema3ItemKeys) else {
            throw invalid("schema-2 item metadata collides with schema-3 reserved keys")
        }

        let canonical = try CueItemRecordCodec.encode(CueItemRecord(workspaceID: workspaceID, item: item))
        guard canonical.starts(with: Data("---\ncue: ".utf8)),
              let objectEnd = canonical.range(of: Data("\n---\n".utf8))?.lowerBound else {
            throw invalid("schema-3 item codec produced an invalid record")
        }
        let objectStart = Data("---\ncue: ".utf8).count
        var object = Data(canonical[objectStart..<objectEnd])
        if let legacySource = legacy.envelope.members.first(where: { $0.key == "source" }) {
            let legacySourceData = Data(legacy.metadata[legacySource.valueRange])
            let legacySourceEnvelope = try CueItemRecordCodec.parseJSONObjectEnvelope(legacySourceData)
            let unknownSource = legacySourceEnvelope.members.filter { !sourceKeys.contains($0.key) }
            if !unknownSource.isEmpty {
                let canonicalEnvelope = try CueItemRecordCodec.parseJSONObjectEnvelope(object)
                guard let canonicalSource = canonicalEnvelope.members.first(where: { $0.key == "source" }) else {
                    throw invalid("schema-3 item metadata has no source object")
                }
                let canonicalSourceData = Data(object[canonicalSource.valueRange])
                let mergedSource = try appendUnknownMembers(
                    unknownSource.map { Data(legacySourceData[$0.memberRange]) },
                    to: canonicalSourceData
                )
                object.replaceSubrange(canonicalSource.valueRange, with: mergedSource)
            }
        }
        let unknownMembers = unknown.map { Data(legacy.metadata[$0.memberRange]) }
        let mergedObject = try appendUnknownMembers(unknownMembers, to: object)

        var migrated = Data(canonical[..<objectStart])
        migrated.append(mergedObject)
        migrated.append(Data(canonical[objectEnd...]))
        let decoded = try CueItemRecordCodec.decode(migrated)
        guard decoded.workspaceID == workspaceID,
              decoded.item == item,
              migrated.suffix(legacy.body.count) == legacy.body else {
            throw invalid("schema-2 item did not migrate losslessly")
        }
        return migrated
    }

    private static func migrateLegacyTombstone(_ data: Data, workspaceID: UUID) throws -> Data {
        let envelope = try CueItemRecordCodec.parseJSONObjectEnvelope(data)
        let legacy = try WorkspacePackageCodec.decodeTombstone(data)
        guard legacy.workspaceID == workspaceID else { throw invalid("tombstone belongs to a different workspace") }
        let unknown = envelope.members.filter { !schema2TombstoneKeys.contains($0.key) }
        let record = Schema3TombstoneRecord(
            schemaVersion: schemaVersion,
            workspaceID: legacy.workspaceID,
            itemID: legacy.itemID,
            kind: "legacy_unbound",
            observedRevision: nil,
            deletedAt: legacy.deletedAt
        )
        let canonical = try encoder().encode(record).addingTrailingNewline()
        let object = Data(canonical.dropLast())
        let merged = try appendUnknownMembers(unknown.map { Data(data[$0.memberRange]) }, to: object)
        return merged.addingTrailingNewline()
    }

    private static func decodeLegacyItem(
        _ data: Data,
        workspaceID: UUID
    ) throws -> (item: WorkItem, metadata: Data, envelope: CueJSONObjectEnvelope, body: Data) {
        let opening = Data("<!-- cue:item ".utf8)
        let metadataClosing = Data(" -->\n".utf8)
        let closing = Data("\n<!-- /cue:item -->\n".utf8)
        guard data.starts(with: opening),
              data.count >= opening.count + metadataClosing.count + closing.count,
              let metadataEndRange = data.range(of: metadataClosing, in: opening.count..<data.count),
              data.suffix(closing.count) == closing else {
            throw invalid("schema-2 item file is not in the lossless migration form")
        }
        let bodyEnd = data.count - closing.count
        guard metadataEndRange.upperBound <= bodyEnd else { throw invalid("schema-2 item metadata overlaps its body") }
        let metadata = Data(data[opening.count..<metadataEndRange.lowerBound])
        let envelope = try CueItemRecordCodec.parseJSONObjectEnvelope(metadata)
        let item = try WorkspacePackageCodec.decodeItem(data, workspaceID: workspaceID)
        let body = Data(data[metadataEndRange.upperBound..<bodyEnd])
        guard Data(item.body.utf8) == body else { throw invalid("schema-2 item body bytes are not round-trippable UTF-8") }
        return (item, metadata, envelope, body)
    }

    private static func appendUnknownMembers(_ members: [Data], to object: Data) throws -> Data {
        guard !members.isEmpty else { return object }
        var cursor = object.endIndex
        while cursor > object.startIndex {
            let previous = object.index(before: cursor)
            if object[previous] == 0x7D {
                var result = Data(object[..<previous])
                result.append(0x2C)
                for (index, member) in members.enumerated() {
                    if index > 0 { result.append(0x2C) }
                    result.append(member)
                }
                result.append(Data(object[previous...]))
                _ = try CueItemRecordCodec.parseJSONObjectEnvelope(result)
                return result
            }
            guard object[previous] == 0x20 || object[previous] == 0x09 || object[previous] == 0x0A || object[previous] == 0x0D else {
                break
            }
            cursor = previous
        }
        throw invalid("metadata object is not closed")
    }

    private static func readSnapshot(at url: URL, fileManager: FileManager) throws -> TreeSnapshot {
        guard url.pathExtension.lowercased() == "cue" else {
            throw invalid("workspace packages must use the .cue extension")
        }
        let rootType: FileAttributeType
        do {
            rootType = try itemType(at: url, fileManager: fileManager)
        } catch CocoaError.fileReadNoSuchFile {
            throw WorkspaceStoreError.missingFile
        }
        guard rootType != .typeSymbolicLink else { throw invalid("workspace package root must not be a symbolic link") }
        guard rootType == .typeDirectory else { throw invalid("workspace path is not a package directory") }

        let rootPath = url.standardizedFileURL.path
        var entries: [TreeEntry] = []
        var files: [String: Data] = [:]

        func walk(_ directory: URL, prefix: String) throws {
            let children = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            for child in children {
                let childPath = child.standardizedFileURL.path
                guard childPath.hasPrefix(rootPath + "/") else {
                    throw invalid("workspace entry escapes the package root")
                }
                let name = child.lastPathComponent
                guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
                    throw invalid("workspace entry has an unsafe path component")
                }
                let relative = prefix.isEmpty ? name : "\(prefix)/\(name)"
                guard isStrictRelativePath(relative) else { throw invalid("workspace entry has an unsafe relative path") }
                let type = try itemType(at: child, fileManager: fileManager)
                if type == .typeSymbolicLink { throw invalid("workspace package contains a symbolic link at \(relative)") }
                if type == .typeDirectory {
                    entries.append(.init(path: relative, kind: .directory))
                    try walk(child, prefix: relative)
                } else if type == .typeRegular {
                    entries.append(.init(path: relative, kind: .file))
                    files[relative] = try Data(contentsOf: child)
                } else {
                    throw invalid("workspace package contains an unsupported entry type at \(relative)")
                }
            }
        }
        try walk(url, prefix: "")
        entries.sort { $0.path < $1.path }
        return TreeSnapshot(entries: entries, files: files, revision: treeRevision(entries: entries, files: files))
    }

    private static func snapshotForPlan(
        directories: [String],
        files: [CuePlannedPackageFile]
    ) throws -> TreeSnapshot {
        guard Set(directories).count == directories.count,
              Set(files.map(\.path)).count == files.count else {
            throw invalid("schema-3 plan contains duplicate paths")
        }
        var entries = directories.map { TreeEntry(path: $0, kind: .directory) }
        entries.append(contentsOf: files.map { TreeEntry(path: $0.path, kind: .file) })
        entries.sort { $0.path < $1.path }
        let data = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.data) })
        return TreeSnapshot(entries: entries, files: data, revision: treeRevision(entries: entries, files: data))
    }

    private static func snapshot(from inspection: CuePackageInspection) -> TreeSnapshot {
        var entries = inspection.rawDirectories.map { TreeEntry(path: $0, kind: .directory) }
        entries.append(contentsOf: inspection.rawFiles.keys.map { TreeEntry(path: $0, kind: .file) })
        entries.sort { $0.path < $1.path }
        return TreeSnapshot(
            entries: entries,
            files: inspection.rawFiles,
            revision: treeRevision(entries: entries, files: inspection.rawFiles)
        )
    }

    private static func directoryPaths(in snapshot: TreeSnapshot) -> [String] {
        snapshot.entries.filter { $0.kind == .directory }.map(\.path).sorted()
    }

    private static func assetFilePaths(in snapshot: TreeSnapshot) -> [String] {
        snapshot.entries.filter {
            $0.kind == .file && $0.path.hasPrefix("assets/sha256/")
        }.map(\.path).sorted()
    }

    private static func plannedDirectories<S: Sequence>(for paths: S) -> [String] where S.Element == String {
        var directories = Set(baseDirectories)
        for path in paths {
            var components = path.split(separator: "/").map(String.init)
            if !components.isEmpty { components.removeLast() }
            var prefix: [String] = []
            for component in components {
                prefix.append(component)
                directories.insert(prefix.joined(separator: "/"))
            }
        }
        return directories.sorted()
    }

    private static func treeRevision(entries: [TreeEntry], files: [String: Data]) -> CuePackageRevision {
        var hasher = SHA256()
        for entry in entries.sorted(by: { $0.path < $1.path }) {
            let data = files[entry.path] ?? Data()
            hasher.update(data: Data("\(entry.kind.rawValue)\0\(entry.path.utf8.count)\0\(entry.path)\0\(data.count)\0".utf8))
            hasher.update(data: data)
        }
        return CuePackageRevision(rawValue: hex(hasher.finalize()))!
    }

    private static func exactRevision(_ data: Data) -> CueRecordRevision {
        CueRecordRevision(rawValue: hex(SHA256.hash(data: data)))!
    }

    private static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func requiredFile(_ path: String, in snapshot: TreeSnapshot) throws -> Data {
        guard isStrictRelativePath(path), let data = snapshot.files[path] else {
            throw invalid("workspace package is missing required file \(path)")
        }
        return data
    }

    private static func itemType(at url: URL, fileManager: FileManager) throws -> FileAttributeType {
        guard let type = try fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType else {
            throw invalid("workspace entry type is unavailable")
        }
        return type
    }

    private static func validateSectionReferences(
        _ records: [CuePackageItemRecord],
        sections: [WorkSection]
    ) throws {
        let valid = Set(sections.map(\.id))
        guard records.allSatisfy({ valid.contains($0.record.item.sectionID) }) else {
            throw invalid("item references a nonexistent section")
        }
    }

    private static func requireUnique<T: Hashable>(_ values: [T], label: String) throws {
        guard Set(values).count == values.count else { throw invalid("duplicate \(label) identifiers") }
    }

    private static func schema3SectionPath(_ section: WorkSection) -> String {
        "sections/\(section.id.uuidString.lowercased()).yaml"
    }

    private static func schema3ItemPath(_ item: WorkItem) -> String {
        let components = utcDateComponents(item.createdAt)
        return String(
            format: "items/%04d/%02d/%@.cue.md",
            components.year ?? 1970,
            components.month ?? 1,
            item.id.uuidString.lowercased()
        )
    }

    private static func legacyTombstonePath(_ itemID: UUID) -> String {
        "tombstones/\(itemID.uuidString.lowercased()).json"
    }

    private static func utcDateComponents(_ date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.dateComponents([.year, .month], from: date)
    }

    private static func canonicalUUIDStem(_ name: String, suffix: String) -> UUID? {
        guard name.hasSuffix(suffix) else { return nil }
        let stem = String(name.dropLast(suffix.count))
        guard let id = UUID(uuidString: stem), stem == id.uuidString.lowercased() else { return nil }
        return id
    }

    private static func isStrictRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasSuffix("/"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: { $0.value == 0 }) else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func isYear(_ value: String) -> Bool {
        value.utf8.count == 4 && value.utf8.allSatisfy(isASCIIDigit)
    }

    private static func isMonth(_ value: String) -> Bool {
        guard value.utf8.count == 2,
              value.utf8.allSatisfy(isASCIIDigit),
              let month = Int(value) else { return false }
        return (1...12).contains(month)
    }

    private static func isSHA256(_ value: String) -> Bool {
        isLowercaseASCIIRevision(value)
    }

    private static func isFeatureName(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy {
            isASCIIDigit($0) || (0x61...0x7A).contains($0) || $0 == 0x5F || $0 == 0x2D
        }
    }

    private static func migrationClosureMatches(
        source: CuePackageInspection,
        target: CuePackageInspection
    ) -> Bool {
        guard target.schemaVersion == schemaVersion,
              target.writeCapability == .writableSchema3,
              target.requiredFeatures.isEmpty,
              source.workspaceID == target.workspaceID,
              source.title == target.title,
              let sourceDocument = source.document,
              let targetDocument = target.document,
              source.itemRecords.count == target.itemRecords.count,
              Set(source.itemRecords.map { $0.record.item.id }) == Set(target.itemRecords.map { $0.record.item.id }),
              Dictionary(uniqueKeysWithValues: sourceDocument.sections.map { ($0.id, $0) }) ==
                Dictionary(uniqueKeysWithValues: targetDocument.sections.map { ($0.id, $0) }),
              Dictionary(uniqueKeysWithValues: sourceDocument.items.map { ($0.id, $0) }) ==
                Dictionary(uniqueKeysWithValues: targetDocument.items.map { ($0.id, $0) }),
              source.tombstones.sorted(by: tombstoneOrder) == target.tombstones.sorted(by: tombstoneOrder),
              let sourceConflicts = legacyConflictEvidence(source.conflicts),
              let targetConflicts = legacyConflictEvidence(target.conflicts) else {
            return false
        }
        return sourceConflicts == targetConflicts
    }

    private static func legacyConflictEvidence(
        _ conflicts: [CuePackageConflict]
    ) -> [LegacyConflictEvidence]? {
        var evidence: [LegacyConflictEvidence] = []
        for conflict in conflicts {
            switch conflict {
            case .editDelete:
                return nil
            case let .legacyDeleteEdit(itemID, _, deletedAt):
                evidence.append(.init(itemID: itemID, deletedAt: deletedAt))
            }
        }
        return evidence.sorted {
            if $0.itemID == $1.itemID { return $0.deletedAt < $1.deletedAt }
            return $0.itemID.uuidString < $1.itemID.uuidString
        }
    }

    private static func tombstoneOrder(_ lhs: CuePackageTombstone, _ rhs: CuePackageTombstone) -> Bool {
        lhs.itemID.uuidString < rhs.itemID.uuidString
    }

    static func isLowercaseASCIIRevision(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            isASCIIDigit($0) || (0x61...0x66).contains($0)
        }
    }

    private static func isASCIIDigit(_ value: UInt8) -> Bool {
        (0x30...0x39).contains(value)
    }

    private static func conflictOrder(_ lhs: CuePackageConflict, _ rhs: CuePackageConflict) -> Bool {
        conflictItemID(lhs).uuidString < conflictItemID(rhs).uuidString
    }

    private static func conflictItemID(_ conflict: CuePackageConflict) -> UUID {
        switch conflict {
        case let .editDelete(itemID, _, _), let .legacyDeleteEdit(itemID, _, _): itemID
        }
    }

    private static func encodeSchema3Manifest(_ manifest: Schema3Manifest) throws -> Data {
        try encoder().encode(manifest).addingTrailingNewline()
    }

    private static func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        value.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return value
    }

    private static func decoder() -> JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }

    private static func invalid(_ message: String) -> WorkspaceStoreError {
        .invalidDocument(message)
    }
}

private extension Data {
    func addingTrailingNewline() -> Data {
        guard last != 0x0A else { return self }
        var value = self
        value.append(0x0A)
        return value
    }
}
