import CueCore
import Foundation

extension WorkItemKind {
    var label: String { self == .selection ? "Selection" : "Prompt" }
    var symbol: String { self == .selection ? "text.quote" : "arrow.up.message" }
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
