import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var document: WorkspaceDocument?
    @Published private(set) var storageHealth: StorageHealth = .ready(lastWrite: nil)
    @Published var query = ""
    @Published var showingArchive = false
    @Published var selectedItemIDs: Set<UUID> = []
    @Published var focusedItemID: UUID?
    @Published var activeSectionID: UUID?
    @Published var composerText = ""
    @Published var receipt: Receipt?
    @Published var mergeRequest: MergeRequest?
    @Published var conflictMergeRequest: ConflictMergeRequest?
    @Published var composerFocused = false
    @Published private(set) var recoveryMarkdown: String?
    @Published private(set) var isAccessibilityTrusted = false
    @Published private(set) var dwellingCompletedIDs: Set<UUID> = []

    struct MergeRequest: Identifiable, Equatable {
        var id = UUID()
        var itemIDs: [UUID]
        var preview: String
        var asBullets: Bool
    }

    struct ConflictMergeRequest: Identifiable, Equatable {
        var id = UUID()
        var mergedDocument: WorkspaceDocument
        var externalDocument: WorkspaceDocument
        var externalFingerprint: FileFingerprint
        var preview: String
        var summary: String
    }

    private let settingsStore: SettingsStore
    private let workspaceStore: WorkspaceStore
    private var expectedFingerprint: FileFingerprint?
    private var undoStack: [WorkspaceDocument] = []
    private var orderedSelection = ItemSelectionModel()
    private var receiptDismissTask: Task<Void, Never>?
    private var completionDwellTasks: [UUID: Task<Void, Never>] = [:]
    private var filePollTimer: Timer?

    var onReceipt: ((Receipt) -> Void)?
    var onRequestSettings: (() -> Void)?
    var onRequestComposer: (() -> Void)?
    var onRequestHide: (() -> Void)?

    init(
        settingsStore: SettingsStore = SettingsStore(),
        workspaceStore: WorkspaceStore = WorkspaceStore()
    ) {
        self.settingsStore = settingsStore
        self.workspaceStore = workspaceStore
        settings = settingsStore.load()
        isAccessibilityTrusted = SelectionCaptureService.isTrusted(prompt: false)

        if ProcessInfo.processInfo.arguments.contains("--demo") || ProcessInfo.processInfo.environment["CUE_DEMO"] == "1" {
            installDemoWorkspaceIfNeeded()
        }
        loadActiveWorkspace()
        startFilePolling()
    }

    deinit {
        filePollTimer?.invalidate()
        receiptDismissTask?.cancel()
        for task in completionDwellTasks.values { task.cancel() }
    }

    var activeWorkspace: WorkspaceDescriptor? {
        guard let active = settings.activeWorkspaceID else { return nil }
        return settings.workspaces.first { $0.id == active }
    }

    var activeWorkspaceURL: URL? {
        activeWorkspace.map { URL(fileURLWithPath: $0.path) }
    }

    var activeWorkspaceTitle: String {
        activeWorkspace?.title ?? "No workspace"
    }

    var activeSectionTitle: String {
        guard let document else { return "Inbox" }
        let id = activeSectionID ?? document.inbox.id
        return document.sections.first(where: { $0.id == id })?.title ?? "Inbox"
    }

    var hasWorkspace: Bool { document != nil && activeWorkspace != nil }

    var queuedCount: Int {
        document?.items.filter { $0.state == .queued }.count ?? 0
    }

    var completedCount: Int {
        document?.items.filter { $0.state == .completed }.count ?? 0
    }

    var archiveCount: Int {
        document?.items.filter { $0.state == .archived }.count ?? 0
    }

    func visibleItems(in sectionID: UUID? = nil) -> [WorkItem] {
        guard let document else { return [] }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sectionOrder = Dictionary(uniqueKeysWithValues: document.sections.map { ($0.id, $0.order) })
        let sectionTitles = Dictionary(uniqueKeysWithValues: document.sections.map { ($0.id, $0.title.lowercased()) })
        return document.items
            .filter { item in
                let stateMatches = showingArchive ? item.state == .archived : item.state != .archived
                let sectionMatches = sectionID == nil || item.sectionID == sectionID
                let queryMatches = normalizedQuery.isEmpty ||
                    item.body.lowercased().contains(normalizedQuery) ||
                    (item.source.appName?.lowercased().contains(normalizedQuery) ?? false) ||
                    (item.source.windowTitle?.lowercased().contains(normalizedQuery) ?? false) ||
                    (sectionTitles[item.sectionID]?.contains(normalizedQuery) ?? false)
                return stateMatches && sectionMatches && queryMatches
            }
            .sorted { lhs, rhs in
                if lhs.state != rhs.state {
                    if lhs.state == .queued { return true }
                    if rhs.state == .queued { return false }
                }
                if sectionID == nil, sectionOrder[lhs.sectionID] != sectionOrder[rhs.sectionID] {
                    return (sectionOrder[lhs.sectionID] ?? .greatestFiniteMagnitude) <
                        (sectionOrder[rhs.sectionID] ?? .greatestFiniteMagnitude)
                }
                if lhs.pinned != rhs.pinned { return lhs.pinned }
                if lhs.order == rhs.order { return lhs.createdAt < rhs.createdAt }
                return lhs.order < rhs.order
            }
    }

    func createDefaultWorkspace() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = documents.appendingPathComponent("Cue", isDirectory: true)
        var url = directory.appendingPathComponent("Cue Workspace.md")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("Cue Workspace \(suffix).md")
            suffix += 1
        }
        createWorkspace(title: "Cue Workspace", at: url)
    }

    func createWorkspace(title: String, at url: URL) {
        var document = WorkspaceDocument(title: title)
        document.ensureInbox()
        do {
            let fingerprint = try workspaceStore.create(document: document, at: url)
            let descriptor = WorkspaceDescriptor(
                id: document.id,
                title: title,
                path: url.path,
                lastOpenedAt: Date()
            )
            settings.workspaces.removeAll { $0.path == url.path || $0.id == descriptor.id }
            settings.workspaces.append(descriptor)
            settings.activeWorkspaceID = descriptor.id
            try settingsStore.save(settings)
            self.document = document
            expectedFingerprint = fingerprint
            activeSectionID = document.inbox.id
            undoStack.removeAll()
            storageHealth = .ready(lastWrite: Date())
            publishReceipt(Receipt(message: "Workspace created · \(title)", symbol: "folder.badge.plus"))
        } catch {
            storageHealth = .writeFailed(message: error.localizedDescription)
            publishReceipt(Receipt(message: "Workspace not created", symbol: "exclamationmark.triangle.fill", isError: true))
        }
    }

    func addExistingWorkspace(url: URL) {
        do {
            let (loaded, fingerprint) = try workspaceStore.load(from: url)
            let descriptor = WorkspaceDescriptor(
                id: loaded.id,
                title: loaded.title,
                path: url.path,
                lastOpenedAt: Date()
            )
            settings.workspaces.removeAll { $0.path == url.path || $0.id == descriptor.id }
            settings.workspaces.append(descriptor)
            settings.activeWorkspaceID = descriptor.id
            try settingsStore.save(settings)
            document = loaded
            expectedFingerprint = fingerprint
            activeSectionID = loaded.inbox.id
            undoStack.removeAll()
            storageHealth = .ready(lastWrite: nil)
            publishReceipt(Receipt(message: "Opened · \(loaded.title)", symbol: "folder"))
        } catch {
            storageHealth = .writeFailed(message: error.localizedDescription)
            publishReceipt(Receipt(message: "That file is not a readable Cue workspace", symbol: "doc.badge.ellipsis", isError: true))
        }
    }

    @discardableResult
    func switchWorkspace(to id: UUID) -> Bool {
        guard let workspaceIndex = settings.workspaces.firstIndex(where: { $0.id == id }) else { return false }
        let descriptor = settings.workspaces[workspaceIndex]
        do {
            let (loaded, fingerprint) = try workspaceStore.load(from: URL(fileURLWithPath: descriptor.path))
            guard loaded.id == descriptor.id else {
                throw WorkspaceStoreError.invalidDocument("workspace identifier no longer matches this reference")
            }

            var updatedSettings = settings
            updatedSettings.activeWorkspaceID = id
            updatedSettings.workspaces[workspaceIndex].title = loaded.title
            updatedSettings.workspaces[workspaceIndex].lastOpenedAt = Date()
            try settingsStore.save(updatedSettings)
            settings = updatedSettings
            document = loaded
            expectedFingerprint = fingerprint
            activeSectionID = loaded.inbox.id
            selectedItemIDs.removeAll()
            focusedItemID = nil
            orderedSelection.clear()
            undoStack.removeAll()
            storageHealth = .ready(lastWrite: nil)
            return true
        } catch {
            publishReceipt(Receipt(
                message: "Workspace unavailable · \(descriptor.title)",
                symbol: "externaldrive.badge.exclamationmark",
                isError: true
            ))
            return false
        }
    }

    func removeWorkspaceReference(_ id: UUID) {
        settings.workspaces.removeAll { $0.id == id }
        settings.contextMappings.removeAll { $0.workspaceID == id }
        if settings.activeWorkspaceID == id {
            settings.activeWorkspaceID = settings.workspaces.first?.id
        }
        try? settingsStore.save(settings)
        clearSelection()
        undoStack.removeAll()
        loadActiveWorkspace()
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        do {
            try settingsStore.save(settings)
        } catch {
            publishReceipt(Receipt(message: "Settings were not saved", symbol: "exclamationmark.triangle.fill", isError: true))
        }
    }

    @discardableResult
    func addCapturedSelection(_ selection: SelectionCaptureService.Selection) -> CaptureOutcome {
        if let bundleIdentifier = selection.sourceBundleIdentifierForMapping,
           let mapping = settings.contextMappings.filter({
               $0.enabled &&
                   $0.appBundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame &&
                   ($0.titlePattern.isEmpty ||
                       (selection.sourceWindowTitleForMapping?.localizedCaseInsensitiveContains($0.titlePattern) ?? false))
           }).max(by: { $0.titlePattern.count < $1.titlePattern.count }),
           mapping.workspaceID != settings.activeWorkspaceID,
           !switchWorkspace(to: mapping.workspaceID) {
            return .storageFailure(message: "The mapped workspace is unavailable")
        }
        return addItem(body: selection.text, kind: .selection, source: selection.source)
    }

    @discardableResult
    func addItem(
        body: String,
        kind: WorkItemKind,
        source: SourceMetadata = .none,
        sensitivity: Sensitivity = .normal
    ) -> CaptureOutcome {
        let normalizedBody = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !normalizedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        guard sensitivity != .neverSave else { return .secureField }
        guard var document else { return .storageFailure(message: "No workspace") }

        let now = Date()
        if let duplicate = CapturePolicy.duplicate(
            body: normalizedBody,
            now: now,
            items: document.items,
            windowSeconds: settings.duplicateWindowSeconds
        ) {
            publishReceipt(Receipt(
                message: "Already captured",
                symbol: "equal.circle.fill",
                actionTitle: "View",
                action: .revealItem(duplicate.id)
            ))
            return .duplicate(existingID: duplicate.id)
        }

        let sectionID = activeSectionID ?? document.inbox.id
        let nextOrder = (document.items.filter { $0.sectionID == sectionID }.map(\.order).max() ?? -1) + 1
        let item = WorkItem(
            body: normalizedBody,
            kind: kind,
            sectionID: sectionID,
            source: source,
            sensitivity: sensitivity,
            contentHash: ContentHasher.hash(normalizedBody),
            createdAt: now,
            updatedAt: now,
            order: nextOrder
        )
        document.items.append(item)

        guard persistMutation(previous: self.document, intended: document) else {
            return .storageFailure(message: "Workspace write failed")
        }

        focusedItemID = item.id
        selectedItemIDs = [item.id]
        orderedSelection.select(item.id)
        publishReceipt(Receipt(
            message: "Captured · \(activeSectionTitle)",
            symbol: "checkmark.circle.fill",
            actionTitle: "Undo",
            action: .undo
        ))
        return .captured(item)
    }

    func queueComposer() {
        let text = composerText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let outcome = addItem(body: text, kind: .prompt)
        if case .captured = outcome { composerText = "" }
    }

    func editItem(_ id: UUID, body: String) {
        guard var document, let index = document.items.firstIndex(where: { $0.id == id }) else { return }
        let normalizedBody = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !normalizedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let previous = document
        document.items[index].body = normalizedBody
        document.items[index].contentHash = ContentHasher.hash(normalizedBody)
        document.items[index].updatedAt = Date()
        if persistMutation(previous: previous, intended: document) {
            publishReceipt(Receipt(message: "Updated", symbol: "pencil.circle.fill", actionTitle: "Undo", action: .undo))
        }
    }

    func toggleCompletion(_ ids: Set<UUID>) {
        guard !ids.isEmpty, var document else { return }
        let previous = document
        let now = Date()
        var completedIDs = Set<UUID>()
        var requeuedIDs = Set<UUID>()
        for index in document.items.indices where ids.contains(document.items[index].id) && document.items[index].state != .archived {
            if document.items[index].state == .completed {
                document.items[index].state = .queued
                document.items[index].completedAt = nil
                requeuedIDs.insert(document.items[index].id)
            } else {
                document.items[index].state = .completed
                document.items[index].completedAt = now
                completedIDs.insert(document.items[index].id)
            }
            document.items[index].updatedAt = now
        }
        if persistMutation(previous: previous, intended: document) {
            for id in requeuedIDs {
                dwellingCompletedIDs.remove(id)
                completionDwellTasks[id]?.cancel()
                completionDwellTasks[id] = nil
            }
            for id in completedIDs { scheduleCompletionDwell(for: id) }
            let message: String
            if ids.count > 1 {
                message = "Updated \(ids.count) items"
            } else {
                message = completedIDs.isEmpty ? "Moved back to queue" : "Completed"
            }
            publishReceipt(Receipt(message: message, actionTitle: "Undo", action: .undo))
        }
    }

    func markCompleted(_ ids: Set<UUID>) {
        guard let document else { return }
        let queuedIDs = Set(document.items.filter {
            ids.contains($0.id) && $0.state == .queued
        }.map(\.id))
        guard !queuedIDs.isEmpty else { return }
        toggleCompletion(queuedIDs)
    }

    func archive(_ ids: Set<UUID>) {
        guard !ids.isEmpty, var document else { return }
        let previous = document
        let now = Date()
        for index in document.items.indices where ids.contains(document.items[index].id) {
            document.items[index].state = .archived
            document.items[index].archivedAt = now
            document.items[index].updatedAt = now
        }
        if persistMutation(previous: previous, intended: document) {
            for id in ids {
                dwellingCompletedIDs.remove(id)
                completionDwellTasks[id]?.cancel()
                completionDwellTasks[id] = nil
            }
            selectedItemIDs.subtract(ids)
            orderedSelection.replace(with: selectedItemIDs, order: visibleItems().map(\.id))
            focusedItemID = orderedSelection.lead
            publishReceipt(Receipt(message: ids.count == 1 ? "Archived" : "Archived \(ids.count)", symbol: "archivebox.fill", actionTitle: "Undo", action: .undo))
        }
    }

    func archiveCompleted() {
        guard let document else { return }
        archive(Set(document.items.filter { $0.state == .completed }.map(\.id)))
    }

    func restore(_ ids: Set<UUID>) {
        guard !ids.isEmpty, var document else { return }
        let previous = document
        for index in document.items.indices where ids.contains(document.items[index].id) {
            document.items[index].state = .queued
            document.items[index].archivedAt = nil
            document.items[index].completedAt = nil
            document.items[index].updatedAt = Date()
        }
        if persistMutation(previous: previous, intended: document) {
            publishReceipt(Receipt(message: ids.count == 1 ? "Restored" : "Restored \(ids.count)", symbol: "arrow.uturn.backward.circle.fill", actionTitle: "Undo", action: .undo))
        }
    }

    func togglePin(_ id: UUID) {
        guard var document, let index = document.items.firstIndex(where: { $0.id == id }) else { return }
        let previous = document
        document.items[index].pinned.toggle()
        document.items[index].updatedAt = Date()
        _ = persistMutation(previous: previous, intended: document)
    }

    func moveItem(_ id: UUID, before targetID: UUID) {
        guard id != targetID, var document,
              let sourceIndex = document.items.firstIndex(where: { $0.id == id }),
              let targetIndex = document.items.firstIndex(where: { $0.id == targetID }) else { return }
        let previous = document
        let sectionID = document.items[targetIndex].sectionID
        document.items[sourceIndex].sectionID = sectionID
        let targetOrder = document.items[targetIndex].order
        let earlier = document.items
            .filter { $0.sectionID == sectionID && $0.id != id && $0.order < targetOrder }
            .map(\.order).max() ?? (targetOrder - 2)
        document.items[sourceIndex].order = (earlier + targetOrder) / 2
        document.items[sourceIndex].updatedAt = Date()
        document.normalizeOrder()
        _ = persistMutation(previous: previous, intended: document)
    }

    func moveItem(_ id: UUID, to sectionID: UUID) {
        guard var document, let index = document.items.firstIndex(where: { $0.id == id }) else { return }
        let previous = document
        document.items[index].sectionID = sectionID
        document.items[index].order = (document.items.filter { $0.sectionID == sectionID }.map(\.order).max() ?? -1) + 1
        document.items[index].updatedAt = Date()
        document.normalizeOrder()
        _ = persistMutation(previous: previous, intended: document)
    }

    func createSection(title: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, var document else { return }
        let previous = document
        let section = WorkSection(title: cleaned, order: (document.sections.map(\.order).max() ?? -1) + 1)
        document.sections.append(section)
        if persistMutation(previous: previous, intended: document) {
            activeSectionID = section.id
            publishReceipt(Receipt(message: "Section created · \(cleaned)", symbol: "square.stack.3d.up.fill"))
        }
    }

    func activateSection(_ id: UUID) {
        guard let document, let section = document.sections.first(where: { $0.id == id }) else { return }
        activeSectionID = id
        if section.isCollapsed { toggleSection(id) }
    }

    func toggleSection(_ id: UUID) {
        guard var document, let index = document.sections.firstIndex(where: { $0.id == id }) else { return }
        let previous = document
        document.sections[index].isCollapsed.toggle()
        _ = persistMutation(previous: previous, intended: document)
    }

    func prepareMerge(_ ids: Set<UUID>) {
        guard let document else { return }
        let ordered = itemsInWorkspaceOrder(document.items.filter { ids.contains($0.id) }, document: document)
        guard ordered.count >= 2 else {
            publishReceipt(Receipt(message: "Select at least two items to merge", symbol: "rectangle.on.rectangle.slash", isError: true))
            return
        }
        mergeRequest = MergeRequest(
            itemIDs: ordered.map(\.id),
            preview: ordered.map(\.body).joined(separator: "\n\n"),
            asBullets: false
        )
    }

    func setMergeStyle(asBullets: Bool) {
        guard var request = mergeRequest, let document else { return }
        request.asBullets = asBullets
        let items = request.itemIDs.compactMap { id in document.items.first { $0.id == id } }
        request.preview = asBullets
            ? items.map { "- " + $0.body.replacingOccurrences(of: "\n", with: "\n  ") }.joined(separator: "\n")
            : items.map(\.body).joined(separator: "\n\n")
        mergeRequest = request
    }

    func confirmMerge() {
        guard let request = mergeRequest, var document else { return }
        let originals = request.itemIDs.compactMap { id in document.items.first { $0.id == id } }.sorted { $0.order < $1.order }
        guard let first = originals.first, originals.count >= 2 else { return }
        let previous = document
        let now = Date()
        let mergedID = UUID()
        let merged = WorkItem(
            id: mergedID,
            body: request.preview,
            kind: .prompt,
            sectionID: first.sectionID,
            source: .none,
            contentHash: ContentHasher.hash(request.preview),
            createdAt: now,
            updatedAt: now,
            order: first.order,
            mergedFrom: originals.map(\.id)
        )
        for index in document.items.indices where request.itemIDs.contains(document.items[index].id) {
            document.items[index].state = .archived
            document.items[index].archivedAt = now
            document.items[index].mergedInto = mergedID
            document.items[index].updatedAt = now
        }
        document.items.append(merged)
        document.normalizeOrder()
        if persistMutation(previous: previous, intended: document) {
            selectedItemIDs = [mergedID]
            focusedItemID = mergedID
            orderedSelection.select(mergedID)
            mergeRequest = nil
            publishReceipt(Receipt(message: "Merged \(originals.count) items", symbol: "rectangle.on.rectangle.angled", actionTitle: "Undo", action: .undo))
        }
    }

    func cancelMerge() { mergeRequest = nil }

    func copyFocused() {
        let ids = selectedItemIDs.isEmpty ? Set(focusedItemID.map { [$0] } ?? []) : selectedItemIDs
        copy(ids: ids, asList: false)
    }

    func copySelectedAsList() {
        let ids = selectedItemIDs.isEmpty ? Set(focusedItemID.map { [$0] } ?? []) : selectedItemIDs
        copy(ids: ids, asList: true)
    }

    func copy(ids: Set<UUID>, asList: Bool) {
        guard let document else { return }
        let items = itemsInWorkspaceOrder(document.items.filter { ids.contains($0.id) }, document: document)
        guard !items.isEmpty else { return }
        let value = asList
            ? items.map { "- " + $0.body.replacingOccurrences(of: "\n", with: "\n  ") }.joined(separator: "\n")
            : items.map(\.body).joined(separator: "\n\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)

        if settings.completeOnCopy {
            let queuedIDs = Set(items.filter { $0.state == .queued }.map(\.id))
            if queuedIDs.isEmpty {
                publishReceipt(Receipt(
                    message: items.count == 1 ? "Copied" : "Copied \(items.count) items",
                    symbol: "doc.on.doc.fill"
                ))
            } else {
                markCompleted(queuedIDs)
            }
        } else {
            publishReceipt(Receipt(
                message: items.count == 1 ? "Copied" : "Copied \(items.count) items",
                symbol: "doc.on.doc.fill",
                actionTitle: "Mark done",
                action: .markDone(items.map(\.id))
            ))
        }
    }

    func undo() {
        guard recoveryMarkdown == nil else {
            publishReceipt(Receipt(
                message: "Resolve the buffered workspace change first",
                symbol: "externaldrive.badge.exclamationmark",
                isError: true
            ))
            return
        }
        guard let previous = undoStack.popLast(), let current = document else { return }
        if persist(document: previous, pushUndo: false) {
            document = previous
            selectedItemIDs = selectedItemIDs.filter { id in previous.items.contains { $0.id == id } }
            orderedSelection.replace(with: selectedItemIDs, order: visibleItems().map(\.id))
            focusedItemID = orderedSelection.lead
            if let focusedItemID, !previous.items.contains(where: { $0.id == focusedItemID }) {
                self.focusedItemID = nil
            }
            publishReceipt(Receipt(message: "Undone", symbol: "arrow.uturn.backward.circle.fill"))
        } else {
            document = current
            undoStack.append(previous)
        }
    }

    func select(_ id: UUID, extending: Bool = false, toggling: Bool = false, visibleOrder: [UUID]? = nil) {
        let order = visibleOrder ?? visibleItems().map(\.id)
        if toggling {
            orderedSelection.toggle(id)
        } else if extending {
            orderedSelection.extend(to: id, order: order)
        } else {
            orderedSelection.select(id)
        }
        selectedItemIDs = orderedSelection.selected
        focusedItemID = orderedSelection.lead
    }

    func moveFocus(offset: Int, extending: Bool, visibleOrder: [UUID]? = nil) {
        let order = visibleOrder ?? visibleItems().map(\.id)
        guard !order.isEmpty else { return }
        _ = orderedSelection.step(offset, order: order, extending: extending)
        selectedItemIDs = orderedSelection.selected
        focusedItemID = orderedSelection.lead
    }

    func selectAllVisible(visibleOrder: [UUID]? = nil) {
        orderedSelection.selectAll(order: visibleOrder ?? visibleItems().map(\.id))
        selectedItemIDs = orderedSelection.selected
        focusedItemID = orderedSelection.lead
    }

    func clearSelection() {
        orderedSelection.clear()
        selectedItemIDs.removeAll()
        focusedItemID = nil
    }

    func performReceiptAction(_ action: Receipt.Action) {
        switch action {
        case .none: break
        case .undo: undo()
        case let .markDone(ids): markCompleted(Set(ids))
        case .openComposer: onRequestComposer?()
        case .openSettings: onRequestSettings?()
        case let .revealItem(id):
            showingArchive = document?.items.first(where: { $0.id == id })?.state == .archived
            select(id)
            onRequestComposer?()
        case .copyRecovery:
            guard let recoveryMarkdown else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(recoveryMarkdown, forType: .string)
        }
    }

    func reloadAfterExternalEdit() {
        if loadActiveWorkspace() {
            undoStack.removeAll()
            clearSelection()
            for task in completionDwellTasks.values { task.cancel() }
            completionDwellTasks.removeAll()
            dwellingCompletedIDs.removeAll()
            recoveryMarkdown = nil
            conflictMergeRequest = nil
            publishReceipt(Receipt(message: "Reloaded external changes", symbol: "arrow.clockwise.circle.fill"))
        } else {
            publishReceipt(Receipt(message: "External file is not a readable Cue workspace", symbol: "doc.badge.ellipsis", isError: true))
        }
    }

    func saveConflictCopy() {
        guard let document, let url = activeWorkspaceURL else { return }
        do {
            let markdown = try recoveryMarkdown ?? MarkdownWorkspaceCodec.encode(document)
            let copy = try workspaceStore.saveConflictCopy(markdown: markdown, nextTo: url)
            recoveryMarkdown = nil
            conflictMergeRequest = nil
            if !FileManager.default.fileExists(atPath: url.path) {
                storageHealth = .fileMissing
            } else if let expectedFingerprint,
                      let current = try? workspaceStore.fingerprint(for: url),
                      current != expectedFingerprint {
                storageHealth = .externallyModified
            } else {
                storageHealth = .writeFailed(message: "The original workspace still needs attention.")
            }
            publishReceipt(Receipt(message: "Saved copy · \(copy.lastPathComponent)", symbol: "doc.badge.plus"))
        } catch {
            publishReceipt(Receipt(message: "Copy could not be saved", symbol: "exclamationmark.triangle.fill", isError: true))
        }
    }

    func prepareConflictMerge() {
        guard let baseline = document,
              let recoveryMarkdown,
              let url = activeWorkspaceURL else { return }
        do {
            let normalizedBaseline = try MarkdownWorkspaceCodec.decode(
                MarkdownWorkspaceCodec.encode(baseline)
            )
            let local = try MarkdownWorkspaceCodec.decode(recoveryMarkdown)
            let (external, externalFingerprint) = try workspaceStore.load(from: url)
            let merged = try mergeDocuments(
                baseline: normalizedBaseline,
                local: local,
                external: external
            )
            let preview = try MarkdownWorkspaceCodec.encode(merged)
            let localChanges = changeCount(from: normalizedBaseline, to: local)
            let externalChanges = changeCount(from: normalizedBaseline, to: external)
            conflictMergeRequest = ConflictMergeRequest(
                mergedDocument: merged,
                externalDocument: external,
                externalFingerprint: externalFingerprint,
                preview: preview,
                summary: "Keeps \(localChanges) local and \(externalChanges) external object changes. External prose remains authoritative."
            )
        } catch {
            conflictMergeRequest = nil
            publishReceipt(Receipt(
                message: "Automatic merge stopped · \(error.localizedDescription)",
                symbol: "arrow.triangle.merge",
                actionTitle: "Copy text",
                action: .copyRecovery,
                isError: true
            ))
        }
    }

    func confirmConflictMerge() {
        guard let request = conflictMergeRequest, let url = activeWorkspaceURL else { return }
        do {
            let fingerprint = try workspaceStore.write(
                document: request.mergedDocument,
                to: url,
                expectedFingerprint: request.externalFingerprint
            )
            expectedFingerprint = fingerprint
            document = request.mergedDocument
            undoStack.append(request.externalDocument)
            if undoStack.count > 30 { undoStack.removeFirst(undoStack.count - 30) }
            recoveryMarkdown = nil
            conflictMergeRequest = nil
            storageHealth = .ready(lastWrite: Date())
            clearSelection()
            publishReceipt(Receipt(
                message: "Merged local and external changes",
                symbol: "arrow.triangle.merge",
                actionTitle: "Undo",
                action: .undo
            ))
        } catch {
            conflictMergeRequest = nil
            storageHealth = .recoveryBuffered
            publishReceipt(Receipt(
                message: "Workspace changed again · review the merge again",
                symbol: "arrow.triangle.2.circlepath",
                isError: true
            ))
        }
    }

    func cancelConflictMerge() { conflictMergeRequest = nil }

    func revealWorkspace() {
        guard let url = activeWorkspaceURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func refreshAccessibilityStatus() {
        isAccessibilityTrusted = SelectionCaptureService.isTrusted(prompt: false)
    }

    func requestAccessibilityPermission() {
        isAccessibilityTrusted = SelectionCaptureService.isTrusted(prompt: true)
        if !isAccessibilityTrusted {
            publishReceipt(Receipt(
                message: "Selection access is off",
                symbol: "hand.raised.fill",
                actionTitle: "Open Settings",
                action: .openSettings,
                isError: true
            ))
        }
    }

    func publishReceipt(_ value: Receipt) {
        receiptDismissTask?.cancel()
        receipt = value
        onReceipt?(value)
        receiptDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.receipt?.id == value.id { self?.receipt = nil }
            }
        }
    }

    @discardableResult
    private func loadActiveWorkspace() -> Bool {
        guard let descriptor = activeWorkspace else {
            document = nil
            expectedFingerprint = nil
            storageHealth = .ready(lastWrite: nil)
            return true
        }
        do {
            let (loaded, fingerprint) = try workspaceStore.load(from: URL(fileURLWithPath: descriptor.path))
            guard loaded.id == descriptor.id else {
                throw WorkspaceStoreError.invalidDocument("workspace identifier no longer matches this reference")
            }
            document = loaded
            expectedFingerprint = fingerprint
            activeSectionID = loaded.sections.contains(where: { $0.id == activeSectionID }) ? activeSectionID : loaded.inbox.id
            storageHealth = .ready(lastWrite: nil)
            if let index = settings.workspaces.firstIndex(where: { $0.id == descriptor.id }),
               settings.workspaces[index].title != loaded.title {
                settings.workspaces[index].title = loaded.title
                settings.workspaces[index].lastOpenedAt = Date()
                try? settingsStore.save(settings)
            }
            return true
        } catch WorkspaceStoreError.missingFile {
            storageHealth = .fileMissing
            return false
        } catch {
            storageHealth = .writeFailed(message: error.localizedDescription)
            return false
        }
    }

    private func persistMutation(previous: WorkspaceDocument?, intended: WorkspaceDocument) -> Bool {
        guard recoveryMarkdown == nil else {
            publishReceipt(Receipt(
                message: "Resolve the buffered workspace change first",
                symbol: "externaldrive.badge.exclamationmark",
                actionTitle: "Copy text",
                action: .copyRecovery,
                isError: true
            ))
            return false
        }
        if persist(document: intended, pushUndo: false) {
            if let previous { undoStack.append(previous) }
            if undoStack.count > 30 { undoStack.removeFirst(undoStack.count - 30) }
            document = intended
            return true
        }
        return false
    }

    private func persist(document: WorkspaceDocument, pushUndo: Bool) -> Bool {
        guard let url = activeWorkspaceURL else { return false }
        do {
            let fingerprint = try workspaceStore.write(
                document: document,
                to: url,
                expectedFingerprint: expectedFingerprint
            )
            expectedFingerprint = fingerprint
            self.document = document
            storageHealth = .ready(lastWrite: Date())
            recoveryMarkdown = nil
            return true
        } catch WorkspaceStoreError.externalModification {
            storageHealth = .externallyModified
        } catch WorkspaceStoreError.missingFile {
            storageHealth = .fileMissing
        } catch {
            storageHealth = .writeFailed(message: error.localizedDescription)
        }
        recoveryMarkdown = try? MarkdownWorkspaceCodec.encode(document)
        storageHealth = .recoveryBuffered
        publishReceipt(Receipt(
            message: "Workspace changed · unsaved text is safe here",
            symbol: "exclamationmark.arrow.triangle.2.circlepath",
            actionTitle: "Copy text",
            action: .copyRecovery,
            isError: true
        ))
        return false
    }

    private func checkExternalFileState() {
        refreshAccessibilityStatus()
        guard let url = activeWorkspaceURL, let expectedFingerprint else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            storageHealth = .fileMissing
            return
        }
        guard let current = try? workspaceStore.fingerprint(for: url) else { return }
        if current != expectedFingerprint, !storageHealth.needsAttention {
            storageHealth = .externallyModified
        }
    }

    private func startFilePolling() {
        filePollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkExternalFileState() }
        }
    }

    private func scheduleCompletionDwell(for id: UUID) {
        dwellingCompletedIDs.insert(id)
        completionDwellTasks[id]?.cancel()
        completionDwellTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.dwellingCompletedIDs.remove(id)
                self?.completionDwellTasks[id] = nil
            }
        }
    }

    private func itemsInWorkspaceOrder(_ items: [WorkItem], document: WorkspaceDocument) -> [WorkItem] {
        let sectionOrder = Dictionary(uniqueKeysWithValues: document.sections.map { ($0.id, $0.order) })
        return items.sorted { lhs, rhs in
            let lhsSection = sectionOrder[lhs.sectionID] ?? .greatestFiniteMagnitude
            let rhsSection = sectionOrder[rhs.sectionID] ?? .greatestFiniteMagnitude
            if lhsSection != rhsSection { return lhsSection < rhsSection }
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            if lhs.order == rhs.order { return lhs.createdAt < rhs.createdAt }
            return lhs.order < rhs.order
        }
    }

    private func mergeDocuments(
        baseline: WorkspaceDocument,
        local: WorkspaceDocument,
        external: WorkspaceDocument
    ) throws -> WorkspaceDocument {
        guard baseline.id == local.id, baseline.id == external.id else {
            throw WorkspaceStoreError.invalidDocument("workspace identifiers do not match")
        }

        let schema = try resolvedValue(
            baseline: baseline.schemaVersion,
            local: local.schemaVersion,
            external: external.schemaVersion,
            label: "schema"
        )
        let title = try resolvedValue(
            baseline: baseline.title,
            local: local.title,
            external: external.title,
            label: "workspace title"
        )

        let baselineSections = Dictionary(uniqueKeysWithValues: baseline.sections.map { ($0.id, $0) })
        let localSections = Dictionary(uniqueKeysWithValues: local.sections.map { ($0.id, $0) })
        let externalSections = Dictionary(uniqueKeysWithValues: external.sections.map { ($0.id, $0) })
        let sectionIDs = Set(baselineSections.keys).union(localSections.keys).union(externalSections.keys)
        var sections: [WorkSection] = []
        for id in sectionIDs {
            if let resolved: WorkSection = try resolvedOptionalValue(
                baseline: baselineSections[id],
                local: localSections[id],
                external: externalSections[id],
                label: "section \(id.uuidString.prefix(8))"
            ) {
                sections.append(resolved)
            }
        }
        guard !sections.isEmpty else {
            throw WorkspaceStoreError.invalidDocument("all sections were removed")
        }

        let baselineItems = Dictionary(uniqueKeysWithValues: baseline.items.map { ($0.id, $0) })
        let localItems = Dictionary(uniqueKeysWithValues: local.items.map { ($0.id, $0) })
        let externalItems = Dictionary(uniqueKeysWithValues: external.items.map { ($0.id, $0) })
        let itemIDs = Set(baselineItems.keys).union(localItems.keys).union(externalItems.keys)
        var items: [WorkItem] = []
        for id in itemIDs {
            if let resolved: WorkItem = try resolvedOptionalValue(
                baseline: baselineItems[id],
                local: localItems[id],
                external: externalItems[id],
                label: "item \(id.uuidString.prefix(8))"
            ) {
                items.append(resolved)
            }
        }

        let sectionIDSet = Set(sections.map(\.id))
        guard items.allSatisfy({ sectionIDSet.contains($0.sectionID) }) else {
            throw WorkspaceStoreError.invalidDocument("an item and its section changed incompatibly")
        }

        var merged = WorkspaceDocument(
            schemaVersion: schema,
            id: baseline.id,
            title: title,
            sections: sections,
            items: items,
            layout: external.layout
        )
        merged.normalizeOrder()
        return merged
    }

    private func resolvedValue<Value: Equatable>(
        baseline: Value,
        local: Value,
        external: Value,
        label: String
    ) throws -> Value {
        guard let value: Value = try resolvedOptionalValue(
            baseline: Optional(baseline),
            local: Optional(local),
            external: Optional(external),
            label: label
        ) else {
            throw WorkspaceStoreError.invalidDocument("\(label) was removed")
        }
        return value
    }

    private func resolvedOptionalValue<Value: Equatable>(
        baseline: Value?,
        local: Value?,
        external: Value?,
        label: String
    ) throws -> Value? {
        if local == baseline { return external }
        if external == baseline { return local }
        if local == external { return local }
        throw WorkspaceStoreError.invalidDocument("both sides changed \(label)")
    }

    private func changeCount(from baseline: WorkspaceDocument, to changed: WorkspaceDocument) -> Int {
        var count = baseline.title == changed.title && baseline.schemaVersion == changed.schemaVersion ? 0 : 1
        let baselineSections = Dictionary(uniqueKeysWithValues: baseline.sections.map { ($0.id, $0) })
        let changedSections = Dictionary(uniqueKeysWithValues: changed.sections.map { ($0.id, $0) })
        count += Set(baselineSections.keys).union(changedSections.keys).filter {
            baselineSections[$0] != changedSections[$0]
        }.count
        let baselineItems = Dictionary(uniqueKeysWithValues: baseline.items.map { ($0.id, $0) })
        let changedItems = Dictionary(uniqueKeysWithValues: changed.items.map { ($0.id, $0) })
        count += Set(baselineItems.keys).union(changedItems.keys).filter {
            baselineItems[$0] != changedItems[$0]
        }.count
        return count
    }

    private func installDemoWorkspaceIfNeeded() {
        guard settings.workspaces.isEmpty else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Cue Demo", isDirectory: true)
        let url = directory.appendingPathComponent("Product Launch.md")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)

        var demo = WorkspaceDocument(title: "Product Launch")
        let inbox = demo.inbox.id
        let research = WorkSection(title: "Research", order: 1)
        demo.sections.append(research)
        let now = Date()
        demo.items = [
            WorkItem(body: "Compare the onboarding friction in the three strongest local-first tools.", kind: .prompt, sectionID: inbox, contentHash: ContentHasher.hash("Compare the onboarding friction in the three strongest local-first tools."), createdAt: now.addingTimeInterval(-340), updatedAt: now, order: 0),
            WorkItem(body: "The useful unit is the next unresolved thought, not a clipboard entry or a permanent note.", kind: .selection, sectionID: research.id, source: SourceMetadata(appName: "Safari", bundleIdentifier: "com.apple.Safari"), contentHash: ContentHasher.hash("The useful unit is the next unresolved thought, not a clipboard entry or a permanent note."), createdAt: now.addingTimeInterval(-220), updatedAt: now, pinned: true, order: 0),
            WorkItem(body: "Draft the launch prompt with privacy boundaries stated before features.", kind: .prompt, state: .completed, sectionID: research.id, contentHash: ContentHasher.hash("Draft the launch prompt with privacy boundaries stated before features."), createdAt: now.addingTimeInterval(-110), updatedAt: now, completedAt: now.addingTimeInterval(-20), order: 1),
        ]
        if let fingerprint = try? workspaceStore.create(document: demo, at: url) {
            settings.workspaces = [WorkspaceDescriptor(id: demo.id, title: demo.title, path: url.path, lastOpenedAt: now)]
            settings.activeWorkspaceID = demo.id
            try? settingsStore.save(settings)
            document = demo
            expectedFingerprint = fingerprint
        }
    }
}
