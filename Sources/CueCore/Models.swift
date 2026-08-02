import Foundation

public enum WorkItemKind: String, Codable, CaseIterable, Sendable {
    case selection
    case prompt
}

public enum WorkItemState: String, Codable, CaseIterable, Sendable {
    case queued
    case completed
    case archived
}

public enum Sensitivity: String, Codable, CaseIterable, Sendable {
    case normal
    case transient
    case neverSave = "never_save"
}

public struct SourceMetadata: Codable, Equatable, Sendable {
    public var appName: String?
    public var bundleIdentifier: String?
    public var windowTitle: String?
    public var url: String?

    public static let none = SourceMetadata()

    public init(
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.url = url
    }
}

public struct WorkItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var body: String
    public var kind: WorkItemKind
    public var state: WorkItemState
    public var sectionID: UUID
    public var source: SourceMetadata
    public var sensitivity: Sensitivity
    public var contentHash: String
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var archivedAt: Date?
    public var pinned: Bool
    public var order: Double
    public var mergedFrom: [UUID]
    public var mergedInto: UUID?

    public init(
        id: UUID = UUID(),
        body: String,
        kind: WorkItemKind,
        state: WorkItemState = .queued,
        sectionID: UUID,
        source: SourceMetadata = .none,
        sensitivity: Sensitivity = .normal,
        contentHash: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        archivedAt: Date? = nil,
        pinned: Bool = false,
        order: Double,
        mergedFrom: [UUID] = [],
        mergedInto: UUID? = nil
    ) {
        self.id = id
        self.body = body
        self.kind = kind
        self.state = state
        self.sectionID = sectionID
        self.source = source
        self.sensitivity = sensitivity
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.archivedAt = archivedAt
        self.pinned = pinned
        self.order = order
        self.mergedFrom = mergedFrom
        self.mergedInto = mergedInto
    }
}

public struct WorkSection: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var order: Double
    public var isCollapsed: Bool

    public init(id: UUID = UUID(), title: String, order: Double, isCollapsed: Bool = false) {
        self.id = id
        self.title = title
        self.order = order
        self.isCollapsed = isCollapsed
    }
}

/// Preserves non-Cue Markdown and the relative position of managed sections
/// and items. This is adapted from Pewter's verbatim-line round-trip rule,
/// extended for Cue's richer object model.
public enum MarkdownLayoutEntry: Codable, Equatable, Sendable {
    case section(UUID)
    case item(UUID)
    case verbatim(String)
}

public struct WorkspaceDocument: Codable, Equatable, Sendable {
    public static let currentSchema = 3

    public var schemaVersion: Int
    public var id: UUID
    public var title: String
    public var sections: [WorkSection]
    public var items: [WorkItem]
    public var layout: [MarkdownLayoutEntry]

    public init(
        schemaVersion: Int = currentSchema,
        id: UUID = UUID(),
        title: String,
        sections: [WorkSection] = [],
        items: [WorkItem] = [],
        layout: [MarkdownLayoutEntry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.sections = sections
        self.items = items
        self.layout = layout
        ensureInbox()
    }

    public var inbox: WorkSection {
        sections.sorted(by: { $0.order < $1.order }).first!
    }

    public mutating func ensureInbox() {
        if sections.isEmpty {
            sections = [WorkSection(title: "Inbox", order: 0)]
        }
    }

    public mutating func normalizeOrder() {
        sections.sort { $0.order < $1.order }
        for index in sections.indices { sections[index].order = Double(index) }

        let grouped = Dictionary(grouping: items.indices, by: { items[$0].sectionID })
        for indices in grouped.values {
            let sorted = indices.sorted { items[$0].order < items[$1].order }
            for (position, index) in sorted.enumerated() {
                items[index].order = Double(position)
            }
        }
    }
}

public struct FileFingerprint: Equatable, Sendable {
    public var size: UInt64
    public var modifiedAt: Date
    public var digest: String

    public init(size: UInt64, modifiedAt: Date, digest: String) {
        self.size = size
        self.modifiedAt = modifiedAt
        self.digest = digest
    }

    public static func == (lhs: FileFingerprint, rhs: FileFingerprint) -> Bool {
        lhs.size == rhs.size && lhs.digest == rhs.digest
    }
}

public struct WorkspaceSnapshot: Sendable {
    public let packageURL: URL
    public let document: WorkspaceDocument?
    public let revision: CuePackageRevision
    public let itemRecords: [CuePackageItemRecord]
    public let tombstones: [CuePackageTombstone]
    public let conflicts: [CuePackageConflict]
    public let writeCapability: CuePackageWriteCapability

    let inspection: CuePackageInspection

    init(packageURL: URL, document: WorkspaceDocument?, inspection: CuePackageInspection) {
        self.packageURL = packageURL
        self.document = document
        revision = inspection.packageRevision
        itemRecords = inspection.itemRecords
        tombstones = inspection.tombstones
        conflicts = inspection.conflicts
        writeCapability = inspection.writeCapability
        self.inspection = inspection
    }
}

public struct WorkspaceCommitReceipt: Sendable {
    public let snapshot: WorkspaceSnapshot
    public let publishedURL: URL
    public let retainedBackupURL: URL?

    public init(snapshot: WorkspaceSnapshot, publishedURL: URL, retainedBackupURL: URL?) {
        self.snapshot = snapshot
        self.publishedURL = publishedURL
        self.retainedBackupURL = retainedBackupURL
    }
}

public enum WorkspaceRecoveryCandidateState: Equatable, Sendable {
    case missing
    case source
    case target
    case other(CuePackageRevision)
    case unreadable
}

public struct WorkspaceRecoveryCandidate: Equatable, Sendable {
    public let url: URL
    public let state: WorkspaceRecoveryCandidateState

    public init(url: URL, state: WorkspaceRecoveryCandidateState) {
        self.url = url
        self.state = state
    }
}

public struct WorkspacePublicationRecovery: Equatable, Sendable {
    public let sourceRevision: CuePackageRevision?
    public let targetRevision: CuePackageRevision
    public let candidates: [WorkspaceRecoveryCandidate]

    public init(
        sourceRevision: CuePackageRevision?,
        targetRevision: CuePackageRevision,
        candidates: [WorkspaceRecoveryCandidate]
    ) {
        self.sourceRevision = sourceRevision
        self.targetRevision = targetRevision
        self.candidates = candidates
    }
}

@_spi(Testing) public enum WorkspaceTransactionFailpoint: String, CaseIterable, Sendable {
    case afterStageSynchronized
    case afterStageValidated
    case afterRevisionConfirmed
    case afterReplacement
    case afterPublishedValidation
}

@_spi(Testing) public struct WorkspaceTransactionContext: Sendable {
    public let requestedURL: URL
    public let stageURL: URL
    public let adjacentBackupURL: URL?
    public let publishedURL: URL?

    public init(
        requestedURL: URL,
        stageURL: URL,
        adjacentBackupURL: URL?,
        publishedURL: URL?
    ) {
        self.requestedURL = requestedURL
        self.stageURL = stageURL
        self.adjacentBackupURL = adjacentBackupURL
        self.publishedURL = publishedURL
    }
}

public enum WorkspaceStoreError: LocalizedError, Equatable {
    case externalModification
    case missingFile
    case invalidDocument(String)
    case readOnly(CuePackageReadOnlyReason)
    case publicationRecoveryRequired(WorkspacePublicationRecovery)
    case writeFailure(String)

    public var errorDescription: String? {
        switch self {
        case .externalModification:
            "The workspace changed outside Cue. Reload or save a copy before continuing."
        case .missingFile:
            "The workspace package moved or is unavailable."
        case let .invalidDocument(message):
            "The workspace could not be read: \(message)"
        case .readOnly:
            "The workspace uses content Cue cannot safely write."
        case .publicationRecoveryRequired:
            "The workspace publication needs recovery review; Cue preserved every available package."
        case let .writeFailure(message):
            "The workspace could not be saved: \(message)"
        }
    }
}
