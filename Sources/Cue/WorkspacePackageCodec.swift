import Foundation

/// Cue's package format keeps one readable Markdown file per work item.
/// The `.yaml` files use JSON syntax, which is valid YAML 1.2, so decoding
/// stays dependency-free while the source of truth remains inspectable.
enum WorkspacePackageCodec {
    static let schemaVersion = 2
    static let manifestPath = "manifest.yaml"

    struct Manifest: Codable, Equatable {
        var schemaVersion: Int
        var workspaceID: UUID
        var title: String
        var sectionPaths: [String]
        var itemPaths: [String]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "cue_schema"
            case workspaceID = "cue_workspace_id"
            case title
            case sectionPaths = "sections"
            case itemPaths = "items"
        }
    }

    struct SectionRecord: Codable, Equatable {
        var id: UUID
        var title: String
        var order: Double
        var isCollapsed: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case order
            case isCollapsed = "is_collapsed"
        }
    }

    struct Tombstone: Codable, Equatable {
        var workspaceID: UUID
        var itemID: UUID
        var deletedAt: Date

        enum CodingKeys: String, CodingKey {
            case workspaceID = "cue_workspace_id"
            case itemID = "item_id"
            case deletedAt = "deleted_at"
        }
    }

    private struct ItemMetadata: Codable {
        var schemaVersion: Int
        var workspaceID: UUID
        var id: UUID
        var kind: WorkItemKind
        var state: WorkItemState
        var sectionID: UUID
        var source: SourceMetadata
        var sensitivity: Sensitivity
        var createdAt: Date
        var updatedAt: Date
        var completedAt: Date?
        var archivedAt: Date?
        var pinned: Bool
        var order: Double
        var mergedFrom: [UUID]
        var mergedInto: UUID?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "cue_schema"
            case workspaceID = "cue_workspace_id"
            case id
            case kind
            case state
            case sectionID = "section_id"
            case source
            case sensitivity
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case completedAt = "completed_at"
            case archivedAt = "archived_at"
            case pinned
            case order
            case mergedFrom = "merged_from"
            case mergedInto = "merged_into"
        }
    }

    private static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let compactEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func manifest(for source: WorkspaceDocument) -> Manifest {
        var document = source
        document.ensureInbox()
        document.normalizeOrder()
        return Manifest(
            schemaVersion: schemaVersion,
            workspaceID: document.id,
            title: document.title,
            sectionPaths: document.sections.map(sectionPath).sorted(),
            itemPaths: document.items.map(itemPath).sorted()
        )
    }

    static func encodeManifest(_ manifest: Manifest) throws -> Data {
        try prettyEncoder.encode(manifest).withTrailingNewline()
    }

    static func decodeManifest(_ data: Data) throws -> Manifest {
        let manifest = try decoder.decode(Manifest.self, from: data)
        guard manifest.schemaVersion == schemaVersion else {
            throw WorkspaceStoreError.invalidDocument("workspace package schema \(manifest.schemaVersion) is unsupported")
        }
        guard Set(manifest.sectionPaths).count == manifest.sectionPaths.count,
              Set(manifest.itemPaths).count == manifest.itemPaths.count else {
            throw WorkspaceStoreError.invalidDocument("manifest contains duplicate paths")
        }
        guard (manifest.sectionPaths + manifest.itemPaths).allSatisfy(isSafeRelativePath) else {
            throw WorkspaceStoreError.invalidDocument("manifest contains an unsafe path")
        }
        guard manifest.sectionPaths.allSatisfy({ $0.hasPrefix("sections/") && $0.hasSuffix(".yaml") }),
              manifest.itemPaths.allSatisfy({ $0.hasPrefix("items/") && $0.hasSuffix(".md") }) else {
            throw WorkspaceStoreError.invalidDocument("manifest path type does not match its collection")
        }
        return manifest
    }

    static func encodeSection(_ section: WorkSection) throws -> Data {
        try prettyEncoder.encode(SectionRecord(
            id: section.id,
            title: section.title,
            order: section.order,
            isCollapsed: section.isCollapsed
        )).withTrailingNewline()
    }

    static func decodeSection(_ data: Data) throws -> WorkSection {
        let record = try decoder.decode(SectionRecord.self, from: data)
        return WorkSection(id: record.id, title: record.title, order: record.order, isCollapsed: record.isCollapsed)
    }

    static func encodeItem(_ item: WorkItem, workspaceID: UUID) throws -> Data {
        let body = Data(item.body.utf8)
        let metadata = ItemMetadata(
            schemaVersion: schemaVersion,
            workspaceID: workspaceID,
            id: item.id,
            kind: item.kind,
            state: item.state,
            sectionID: item.sectionID,
            source: item.source,
            sensitivity: item.sensitivity,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            completedAt: item.completedAt,
            archivedAt: item.archivedAt,
            pinned: item.pinned,
            order: item.order,
            mergedFrom: item.mergedFrom,
            mergedInto: item.mergedInto
        )
        let metadataData = try compactEncoder.encode(metadata)
        guard let metadataJSON = String(data: metadataData, encoding: .utf8) else {
            throw WorkspaceStoreError.invalidDocument("item metadata is not UTF-8")
        }

        var data = Data("<!-- cue:item \(metadataJSON) -->\n".utf8)
        data.append(body)
        data.append(Data("\n<!-- /cue:item -->\n".utf8))
        return data
    }

    static func decodeItem(_ data: Data, workspaceID: UUID) throws -> WorkItem {
        guard let contents = String(data: data, encoding: .utf8) else {
            throw WorkspaceStoreError.invalidDocument("item file is not UTF-8")
        }
        let marker = "<!-- cue:item "
        let markerEnd = " -->\n"
        let closing = "\n<!-- /cue:item -->\n"
        guard contents.hasPrefix(marker),
              let metadataEnd = contents.range(of: markerEnd),
              let closingRange = contents.range(of: closing, options: .backwards),
              metadataEnd.upperBound <= closingRange.lowerBound else {
            throw WorkspaceStoreError.invalidDocument("item file is missing Cue metadata")
        }

        let metadataJSON = String(contents[contents.index(contents.startIndex, offsetBy: marker.count)..<metadataEnd.lowerBound])
        let metadataData = Data(metadataJSON.utf8)
        let metadata = try decoder.decode(ItemMetadata.self, from: metadataData)
        guard metadata.schemaVersion == schemaVersion else {
            throw WorkspaceStoreError.invalidDocument("item schema \(metadata.schemaVersion) is unsupported")
        }
        guard metadata.workspaceID == workspaceID else {
            throw WorkspaceStoreError.invalidDocument("item belongs to a different workspace")
        }

        let body = String(contents[metadataEnd.upperBound..<closingRange.lowerBound])

        return WorkItem(
            id: metadata.id,
            body: body,
            kind: metadata.kind,
            state: metadata.state,
            sectionID: metadata.sectionID,
            source: metadata.source,
            sensitivity: metadata.sensitivity,
            contentHash: ContentHasher.hash(body),
            createdAt: metadata.createdAt,
            updatedAt: metadata.updatedAt,
            completedAt: metadata.completedAt,
            archivedAt: metadata.archivedAt,
            pinned: metadata.pinned,
            order: metadata.order,
            mergedFrom: metadata.mergedFrom,
            mergedInto: metadata.mergedInto
        )
    }

    static func encodeTombstone(_ value: Tombstone) throws -> Data {
        try prettyEncoder.encode(value).withTrailingNewline()
    }

    static func decodeTombstone(_ data: Data) throws -> Tombstone {
        try decoder.decode(Tombstone.self, from: data)
    }

    static func sectionPath(_ section: WorkSection) -> String {
        "sections/\(section.id.uuidString.lowercased()).yaml"
    }

    static func itemPath(_ item: WorkItem) -> String {
        let components = utcDateComponents(for: item.createdAt)
        return String(format: "items/%04d/%02d/%@.md", components.year ?? 1970, components.month ?? 1, item.id.uuidString.lowercased())
    }

    static func tombstonePath(for itemID: UUID) -> String {
        "tombstones/\(itemID.uuidString.lowercased()).json"
    }

    static func allTombstones(at root: URL, fileManager: FileManager) throws -> [UUID: Tombstone] {
        let directory = root.appendingPathComponent("tombstones", isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return [:] }
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }
        var values: [UUID: Tombstone] = [:]
        for file in files {
            let tombstone = try decodeTombstone(Data(contentsOf: file))
            guard UUID(uuidString: file.deletingPathExtension().lastPathComponent) == tombstone.itemID else {
                throw WorkspaceStoreError.invalidDocument("tombstone path does not match its item identifier")
            }
            values[tombstone.itemID] = tombstone
        }
        return values
    }

    private static func utcDateComponents(for date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.dateComponents([.year, .month], from: date)
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }
}

private extension Data {
    func withTrailingNewline() -> Data {
        guard last != 0x0A else { return self }
        var value = self
        value.append(0x0A)
        return value
    }
}
