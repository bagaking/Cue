import AppKit
import CueCore
import SwiftUI
import UniformTypeIdentifiers

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

struct SidecarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var editingItem: WorkItem?
    @State private var showingNewSection = false
    @State private var newSectionTitle = ""
    @State private var completedExpanded = false
    @State private var searchExpanded = false
    @FocusState private var focus: FocusTarget?

    private enum FocusTarget: Hashable { case search, list }

    private struct WorkItemRenderID: Hashable {
        var itemID: UUID
        var state: String
    }

    var body: some View {
        GeometryReader { geometry in
            let compactHeight = geometry.size.height < 560
            let compactWidth = geometry.size.width < 370
            ZStack {
                VisualEffectBackground(material: .popover)
                Color(nsColor: .windowBackgroundColor)
                    .opacity((reduceTransparency || model.settings.reduceTranslucency) ? 0.98 : 0.72)

                if model.hasWorkspace {
                    content(compactHeight: compactHeight, compactWidth: compactWidth)
                } else {
                    OnboardingView(model: model, compact: compactHeight)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
            }
        }
        .frame(minWidth: 352, idealWidth: 372, maxWidth: 560, minHeight: 500, idealHeight: 600, maxHeight: 900)
        .sheet(item: $editingItem) { item in
            EditItemSheet(item: item) { model.editItem(item.id, body: $0) }
        }
        .sheet(item: $model.mergeRequest) { request in
            MergePreviewSheet(model: model, request: request)
        }
        .sheet(item: $model.conflictMergeRequest) { request in
            ConflictMergeSheet(model: model, request: request)
        }
        .sheet(isPresented: $showingNewSection) {
            VStack(alignment: .leading, spacing: 12) {
                Text("New section").font(.headline)
                TextField("Section name", text: $newSectionTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { createSection() }
                HStack {
                    Spacer()
                    Button("Cancel") { showingNewSection = false }
                    Button("Create") { createSection() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(newSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 320)
        }
        .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
            guard focus == .list || focus == nil else { return .ignored }
            model.moveFocus(
                offset: press.key == .upArrow ? -1 : 1,
                extending: press.modifiers.contains(.shift),
                visibleOrder: displayedItemIDs
            )
            focus = .list
            return .handled
        }
        .onKeyPress(keys: ["x", "X"], phases: .down) { press in
            guard press.modifiers.isEmpty, focus == .list, !model.selectedItemIDs.isEmpty else { return .ignored }
            model.toggleCompletion(model.selectedItemIDs)
            return .handled
        }
        .onKeyPress(.return) {
            guard focus == .list,
                  model.selectedItemIDs.count == 1,
                  let id = model.selectedItemIDs.first,
                  let item = model.document?.items.first(where: { $0.id == id }) else { return .ignored }
            editingItem = item
            return .handled
        }
        .onKeyPress(keys: ["c", "C"], phases: .down) { press in
            guard press.modifiers.contains(.command), focus == .list || focus == nil else { return .ignored }
            if press.modifiers.contains(.shift) { model.copySelectedAsList() } else { model.copyFocused() }
            return .handled
        }
        .onKeyPress(keys: ["a", "A"], phases: .down) { press in
            guard press.modifiers == .command, focus == .list || focus == nil else { return .ignored }
            model.selectAllVisible(visibleOrder: displayedItemIDs)
            return .handled
        }
        .onKeyPress(keys: ["z", "Z"], phases: .down) { press in
            guard press.modifiers == .command, focus == .list || focus == nil else { return .ignored }
            model.undo()
            return .handled
        }
        .onKeyPress(keys: ["f", "F"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            searchExpanded = true
            focus = .search
            return .handled
        }
        .onKeyPress(.escape) {
            if model.selectedItemIDs.count > 1 {
                model.clearSelection()
                return .handled
            }
            if !model.query.isEmpty {
                model.query = ""
                return .handled
            }
            return .ignored
        }
        .onChange(of: model.query) { _, _ in model.clearSelection() }
    }

    private func content(compactHeight: Bool, compactWidth: Bool) -> some View {
        VStack(spacing: 0) {
            header(compactHeight: compactHeight, compactWidth: compactWidth)
            if model.storageHealth.needsAttention { storageBanner }
            Divider().opacity(0.55)
            list
            if model.selectedItemIDs.count > 1 { batchBar }
            Divider().opacity(0.55)
            composer(compact: compactHeight)
        }
        .overlay(alignment: .bottom) {
            if let receipt = model.receipt {
                ReceiptView(receipt: receipt) { model.performReceiptAction(receipt.action) }
                    .padding(.bottom, model.selectedItemIDs.count > 1 ? (compactHeight ? 84 : 100) : (compactHeight ? 54 : 66))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: model.receipt?.id)
    }

    private func header(compactHeight: Bool, compactWidth: Bool) -> some View {
        VStack(spacing: compactHeight ? 4 : 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(model.settings.workspaces) { workspace in
                        Button {
                            model.switchWorkspace(to: workspace.id)
                        } label: {
                            if workspace.id == model.settings.activeWorkspaceID {
                                Label(workspace.title, systemImage: "checkmark")
                            } else {
                                Text(workspace.title)
                            }
                        }
                    }
                    Divider()
                    Button("Create workspace…") { showCreatePanel() }
                    Button("Open workspace…") { showOpenPanel() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.2.fill")
                            .foregroundStyle(.tint)
                        Text(model.activeWorkspaceTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                Spacer()

                if compactHeight {
                    Button {
                        searchExpanded.toggle()
                        if searchExpanded { focus = .search }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 8).fill((searchExpanded || !model.query.isEmpty) ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .help(searchExpanded ? "Hide Search" : "Search")
                    .accessibilityLabel(searchExpanded ? "Hide Search" : "Show Search")
                }

                PanelPinToggle(model: model)

                if compactWidth {
                    Menu {
                        Button(model.showingArchive ? "Show active queue" : "Open Archive") {
                            model.showingArchive.toggle()
                            model.clearSelection()
                        }
                        Button("Settings") { model.onRequestSettings?() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help("More")
                    .accessibilityLabel("More Cue actions")
                } else {
                    Button {
                        model.showingArchive.toggle()
                        model.clearSelection()
                    } label: {
                        Image(systemName: model.showingArchive ? "tray.full.fill" : "archivebox")
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 8).fill(model.showingArchive ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .help(model.showingArchive ? "Back to active queue" : "Open Archive")
                    .accessibilityLabel(model.showingArchive ? "Show active queue" : "Show Archive")

                    Button {
                        model.onRequestSettings?()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    .accessibilityLabel("Open Settings")
                }
            }

            if !compactHeight || searchExpanded || !model.query.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField(model.showingArchive ? "Search Archive" : "Search next thoughts", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($focus, equals: .search)
                    if !model.query.isEmpty {
                        Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, compactHeight ? 5 : 7)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.05)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, compactHeight ? 7 : 10)
        .padding(.bottom, compactHeight ? 7 : 10)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if model.showingArchive {
                        archiveContent
                    } else {
                        activeContent
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .list)
            .onChange(of: model.focusedItemID) { _, id in
                guard let id,
                      let state = model.document?.items.first(where: { $0.id == id })?.state else { return }
                let renderID = WorkItemRenderID(itemID: id, state: state.rawValue)
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                    proxy.scrollTo(renderID, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var activeContent: some View {
        if model.visibleItems().isEmpty {
            EmptyQueueView(hasQuery: !model.query.isEmpty, hasPermission: model.isAccessibilityTrusted)
        } else if let document = model.document {
            ForEach(document.sections.sorted(by: { $0.order < $1.order })) { section in
                let items = model.visibleItems(in: section.id).filter {
                    $0.state == .queued || model.dwellingCompletedIDs.contains($0.id)
                }
                if !items.isEmpty || model.query.isEmpty {
                    SectionHeader(
                        title: section.title,
                        count: items.count,
                        collapsed: section.isCollapsed,
                        active: model.activeSectionID == section.id,
                        onActivate: { model.activateSection(section.id) },
                        onToggle: {
                            model.toggleSection(section.id)
                            model.clearSelection()
                        }
                    )
                    if !section.isCollapsed {
                        ForEach(items) { item in itemCard(item, sections: document.sections) }
                    }
                }
            }

            let completed = model.visibleItems().filter {
                $0.state == .completed && !model.dwellingCompletedIDs.contains($0.id)
            }
            if !completed.isEmpty {
                SectionHeader(
                    title: "Recently completed",
                    count: completed.count,
                    collapsed: !(completedExpanded || !model.query.isEmpty),
                    active: false,
                    onActivate: nil,
                    onToggle: {
                        completedExpanded.toggle()
                        model.clearSelection()
                    }
                )
                if completedExpanded || !model.query.isEmpty {
                    ForEach(completed) { item in itemCard(item, sections: document.sections) }
                    Button("Archive completed") { model.archiveCompleted() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
            }

            Button {
                newSectionTitle = ""
                showingNewSection = true
            } label: {
                Label("New section", systemImage: "plus")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.top, 1)
        }
    }

    @ViewBuilder
    private var archiveContent: some View {
        let items = model.visibleItems()
        if items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "archivebox")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(model.query.isEmpty ? "Archive is clear" : "No archived matches")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else if let sections = model.document?.sections {
            ForEach(items) { item in itemCard(item, sections: sections) }
        }
    }

    private func itemCard(_ item: WorkItem, sections: [WorkSection]) -> some View {
        WorkItemCard(
            item: item,
            selected: model.selectedItemIDs.contains(item.id),
            focused: model.focusedItemID == item.id,
            sections: sections,
            onSelect: {
                let flags = NSEvent.modifierFlags
                model.select(
                    item.id,
                    extending: flags.contains(.shift),
                    toggling: flags.contains(.command),
                    visibleOrder: displayedItemIDs
                )
                focus = .list
            },
            onToggle: { model.toggleCompletion([item.id]) },
            onCopy: { model.copy(ids: [item.id], asList: false) },
            onEdit: { editingItem = item },
            onArchive: { model.archive([item.id]) },
            onRestore: { model.restore([item.id]) },
            onPin: { model.togglePin(item.id) },
            onMove: { model.moveItem(item.id, to: $0) },
            onDropBefore: { model.moveItem($0, before: item.id) }
        )
        .id(WorkItemRenderID(itemID: item.id, state: item.state.rawValue))
    }

    private var batchBar: some View {
        HStack(spacing: 6) {
            Text("\(model.selectedItemIDs.count) selected")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            batchButton("doc.on.doc", "Copy list") { model.copySelectedAsList() }
            if !model.showingArchive {
                batchButton("rectangle.on.rectangle.angled", "Merge") { model.prepareMerge(model.selectedItemIDs) }
                batchButton("checkmark.circle", "Complete") { model.markCompleted(model.selectedItemIDs) }
                batchButton("archivebox", "Archive") { model.archive(model.selectedItemIDs) }
            } else {
                batchButton("arrow.uturn.backward", "Restore") { model.restore(model.selectedItemIDs) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.08))
    }

    private func batchButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 28, height: 28) }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)
    }

    private func composer(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.message")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tint)
                Text("NEXT IN \(model.activeWorkspaceTitle.uppercased()) · \(model.activeSectionTitle.uppercased())")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if !compact {
                    Text("⌘↩")
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            ComposerTextView(text: $model.composerText, onCommit: model.queueComposer)
                .frame(height: compact ? 32 : 40)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .textBackgroundColor).opacity(0.82)))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.075)))
                .overlay(alignment: .topLeading) {
                    if model.composerText.isEmpty {
                        Text("Type a prompt to use next…")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 12)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.top, compact ? 5 : 7)
        .padding(.bottom, compact ? 6 : 9)
    }

    @ViewBuilder
    private var storageBanner: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(storageMessage).font(.system(size: 12, weight: .semibold))
                Text("Unsaved content stays in Cue until you choose.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.recoveryMarkdown != nil {
                Menu("Resolve…") {
                    Button("Review safe merge") { model.prepareConflictMerge() }
                    Button("Save recovery copy") { model.saveConflictCopy() }
                    Button("Copy recovery text") { model.performReceiptAction(.copyRecovery) }
                    Divider()
                    Button("Discard local change and reload") { model.reloadAfterExternalEdit() }
                }
                .controlSize(.small)
            } else if case .externallyModified = model.storageHealth {
                Button("Reload") { model.reloadAfterExternalEdit() }.controlSize(.small)
                Button("Save Copy") { model.saveConflictCopy() }.controlSize(.small)
            } else {
                Button("Reveal") { model.revealWorkspace() }.controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.11))
    }

    private var storageMessage: String {
        switch model.storageHealth {
        case .ready: "Workspace ready"
        case .externallyModified: "Workspace changed outside Cue"
        case .fileMissing: "Workspace package moved"
        case let .writeFailed(message): message
        case .recoveryBuffered: "Workspace write paused"
        }
    }

    private var displayedItemIDs: [UUID] {
        if model.showingArchive { return model.visibleItems().map(\.id) }
        guard let document = model.document else { return [] }

        var ids: [UUID] = []
        for section in document.sections.sorted(by: { $0.order < $1.order }) where !section.isCollapsed {
            ids.append(contentsOf: model.visibleItems(in: section.id).filter {
                $0.state == .queued || model.dwellingCompletedIDs.contains($0.id)
            }.map(\.id))
        }
        if completedExpanded || !model.query.isEmpty {
            ids.append(contentsOf: model.visibleItems().filter {
                $0.state == .completed && !model.dwellingCompletedIDs.contains($0.id)
            }.map(\.id))
        }
        return ids
    }

    private func createSection() {
        model.createSection(title: newSectionTitle)
        showingNewSection = false
    }

    private func showCreatePanel() {
        let panel = NSSavePanel()
        panel.title = "Create Cue Workspace"
        panel.nameFieldStringValue = "Cue Workspace.cue"
        panel.allowedContentTypes = [UTType(filenameExtension: "cue") ?? .package]
        if panel.runModalForCue() == .OK, let url = panel.url {
            model.createWorkspace(title: url.deletingPathExtension().lastPathComponent, at: url)
        }
    }

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Cue Workspace"
        panel.allowedContentTypes = [UTType(filenameExtension: "cue") ?? .package]
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModalForCue() == .OK, let url = panel.url { model.addExistingWorkspace(url: url) }
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var compact: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 13 : 18) {
            HStack {
                Spacer()
                PanelPinToggle(model: model)
            }
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.12))
                Image(systemName: "tray.2.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 8) {
                Text("Keep the next thought\nwithout leaving your work.")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(-0.35)
                Text("Cue keeps selected fragments and future prompts in one small, completable queue. Each item stays readable inside your local workspace package.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 9) {
                Button {
                    model.createDefaultWorkspace()
                } label: {
                    Label("Create a workspace in Documents", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [UTType(filenameExtension: "cue") ?? .package]
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = true
                    panel.treatsFilePackagesAsDirectories = false
                    if panel.runModalForCue() == .OK, let url = panel.url { model.addExistingWorkspace(url: url) }
                } label: {
                    Label("Open an existing Cue workspace", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            HStack(spacing: 7) {
                Image(systemName: "lock.shield")
                Text("No account · no telemetry · typed capture works without Accessibility")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            Spacer()
            }
            .padding(compact ? 16 : 24)
        }
    }
}

private struct PanelPinToggle: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Toggle(isOn: Binding(
            get: { model.settings.panelPinned },
            set: { pinned in model.updateSettings { $0.panelPinned = pinned } }
        )) {
            Image(systemName: model.settings.panelPinned ? "pin.fill" : "pin")
                .frame(width: 28, height: 28)
                .foregroundStyle(model.settings.panelPinned ? Color.accentColor : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(model.settings.panelPinned ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                )
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .help("When off, Cue retracts at the screen edge after you move away.")
        .accessibilityLabel("Keep Cue panel open")
        .accessibilityValue(model.settings.panelPinned ? "On" : "Off")
    }
}

private struct SectionHeader: View {
    var title: String
    var count: Int
    var collapsed: Bool
    var active: Bool
    var onActivate: (() -> Void)?
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Button(action: onToggle) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(collapsed ? "Expand \(title)" : "Collapse \(title)")

            Button(action: onActivate ?? onToggle) {
                HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.65)
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    if active {
                        Image(systemName: "scope")
                            .font(.system(size: 9, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
                }
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(active ? "\(title), capture target" : title)
        }
        .padding(.horizontal, 2)
        .padding(.top, 1)
    }
}

private struct EmptyQueueView: View {
    var hasQuery: Bool
    var hasPermission: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: hasQuery ? "magnifyingglass" : "text.cursor")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text(hasQuery ? "No matching thoughts" : "Your next thought lands here")
                .font(.system(size: 13, weight: .semibold))
            Text(hasQuery ? "Try a different search." : (hasPermission ? "Select text and press Shift twice, or type below." : "Type below now. Enable selection capture when you want it."))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

private struct ReceiptView: View {
    var receipt: Receipt
    var action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: receipt.symbol)
                .foregroundStyle(receipt.isError ? Color.orange : Color.accentColor)
            Text(receipt.message).lineLimit(1)
            if let title = receipt.actionTitle {
                Divider().frame(height: 14)
                Button(title, action: action).buttonStyle(.plain).foregroundStyle(.tint)
            }
        }
        .font(.system(size: 11.5, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.11), radius: 9, y: 4)
    }
}

private struct EditItemSheet: View {
    var item: WorkItem
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(item: WorkItem, onSave: @escaping (String) -> Void) {
        self.item = item
        self.onSave = onSave
        _text = State(initialValue: item.body)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit \(item.kind.label.lowercased())").font(.title2.weight(.semibold))
            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { onSave(text); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 430, height: 300)
    }
}

private struct MergePreviewSheet: View {
    @ObservedObject var model: AppModel
    var request: AppModel.MergeRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Merge \(request.itemIDs.count) items").font(.title2.weight(.semibold))
            Picker("Format", selection: Binding(
                get: { request.asBullets },
                set: { model.setMergeStyle(asBullets: $0) }
            )) {
                Text("Paragraphs").tag(false)
                Text("Bulleted list").tag(true)
            }
            .pickerStyle(.segmented)
            ScrollView {
                Text(request.preview)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
            Text("Original items move to Archive with provenance. Undo restores them.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { model.cancelMerge() }
                Button("Merge") { model.confirmMerge() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460, height: 390)
    }
}

private struct ConflictMergeSheet: View {
    @ObservedObject var model: AppModel
    var request: AppModel.ConflictMergeRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review workspace merge").font(.title2.weight(.semibold))
            Text(request.summary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(request.preview)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
            Text("Cue stops before this preview if both sides changed the same item or section. Confirming creates a backup and remains undoable.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { model.cancelConflictMerge() }
                Button("Merge safely") { model.confirmConflictMerge() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560, height: 470)
    }
}
