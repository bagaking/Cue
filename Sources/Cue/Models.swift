import Foundation

enum WorkItemKind: String, Codable, CaseIterable, Sendable {
    case selection
    case prompt

    var label: String { self == .selection ? "Selection" : "Prompt" }
    var symbol: String { self == .selection ? "text.quote" : "arrow.up.message" }
}

enum WorkItemState: String, Codable, CaseIterable, Sendable {
    case queued
    case completed
    case archived
}

enum Sensitivity: String, Codable, CaseIterable, Sendable {
    case normal
    case transient
    case neverSave = "never_save"
}

struct SourceMetadata: Codable, Equatable, Sendable {
    var appName: String?
    var bundleIdentifier: String?
    var windowTitle: String?
    var url: String?

    static let none = SourceMetadata()

    init(
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

struct WorkItem: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var body: String
    var kind: WorkItemKind
    var state: WorkItemState
    var sectionID: UUID
    var source: SourceMetadata
    var sensitivity: Sensitivity
    var contentHash: String
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var archivedAt: Date?
    var pinned: Bool
    var order: Double
    var mergedFrom: [UUID]
    var mergedInto: UUID?

    init(
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

struct WorkSection: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var order: Double
    var isCollapsed: Bool

    init(id: UUID = UUID(), title: String, order: Double, isCollapsed: Bool = false) {
        self.id = id
        self.title = title
        self.order = order
        self.isCollapsed = isCollapsed
    }
}

/// Preserves non-Cue Markdown and the relative position of managed sections
/// and items. This is adapted from Pewter's verbatim-line round-trip rule,
/// extended for Cue's richer object model.
enum MarkdownLayoutEntry: Codable, Equatable, Sendable {
    case section(UUID)
    case item(UUID)
    case verbatim(String)
}

struct WorkspaceDocument: Codable, Equatable, Sendable {
    static let currentSchema = 2

    var schemaVersion: Int
    var id: UUID
    var title: String
    var sections: [WorkSection]
    var items: [WorkItem]
    var layout: [MarkdownLayoutEntry]

    init(
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

    var inbox: WorkSection {
        sections.sorted(by: { $0.order < $1.order }).first!
    }

    mutating func ensureInbox() {
        if sections.isEmpty {
            sections = [WorkSection(title: "Inbox", order: 0)]
        }
    }

    mutating func normalizeOrder() {
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

struct WorkspaceDescriptor: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var path: String
    var lastOpenedAt: Date
}

struct ContextMapping: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var appBundleIdentifier: String
    var titlePattern: String
    var workspaceID: UUID
    var enabled: Bool = true
}

struct AppSettings: Codable, Equatable, Sendable {
    var workspaces: [WorkspaceDescriptor] = []
    var activeWorkspaceID: UUID?
    var captureSourceApp = true
    var captureWindowTitle = false
    var completeOnCopy = false
    var duplicateWindowSeconds = 2.0
    var denylistedBundleIdentifiers: [String] = [
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.agilebits.onepassword7",
    ]
    var contextMappings: [ContextMapping] = []
    var panelPinned = false
    var keepPanelOnTop = true
    var showInDock = false
    var panelSide = "right"
    var reduceTranslucency = false
    var captureChord = "controlShiftC"
    var panelChord = "controlShiftSpace"
    var composerChord = "controlOptionSpace"
}

enum StorageHealth: Equatable, Sendable {
    case ready(lastWrite: Date?)
    case externallyModified
    case fileMissing
    case writeFailed(message: String)
    case recoveryBuffered

    var needsAttention: Bool {
        switch self {
        case .ready: false
        default: true
        }
    }
}

enum CaptureOutcome: Equatable, Sendable {
    case captured(WorkItem)
    case duplicate(existingID: UUID)
    case empty
    case secureField
    case denylisted(appName: String)
    case permissionMissing
    case unavailable
    case storageFailure(message: String)
}

struct Receipt: Identifiable, Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case none
        case undo
        case markDone([UUID])
        case openComposer
        case openSettings
        case revealItem(UUID)
        case copyRecovery
    }

    var id = UUID()
    var message: String
    var symbol: String
    var actionTitle: String?
    var action: Action
    var isError: Bool

    init(
        message: String,
        symbol: String = "checkmark.circle.fill",
        actionTitle: String? = nil,
        action: Action = .none,
        isError: Bool = false
    ) {
        self.message = message
        self.symbol = symbol
        self.actionTitle = actionTitle
        self.action = action
        self.isError = isError
    }
}

struct FileFingerprint: Equatable, Sendable {
    var size: UInt64
    var modifiedAt: Date
    var digest: String

    static func == (lhs: FileFingerprint, rhs: FileFingerprint) -> Bool {
        lhs.size == rhs.size && lhs.digest == rhs.digest
    }
}

enum WorkspaceStoreError: LocalizedError, Equatable {
    case externalModification
    case missingFile
    case invalidDocument(String)
    case writeFailure(String)

    var errorDescription: String? {
        switch self {
        case .externalModification:
            "The workspace changed outside Cue. Reload or save a copy before continuing."
        case .missingFile:
            "The workspace package moved or is unavailable."
        case let .invalidDocument(message):
            "The workspace could not be read: \(message)"
        case let .writeFailure(message):
            "The workspace could not be saved: \(message)"
        }
    }
}
