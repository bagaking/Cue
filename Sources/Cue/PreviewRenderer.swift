import AppKit
import CueCore
import SwiftUI

@MainActor
enum PreviewRenderer {
    static func renderAll(outputDirectory: URL) throws {
        try installPreviewApplicationIcon()
        let model = try makePreviewModel()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try render(view: SidecarView(model: model), size: NSSize(width: 372, height: 600), appearance: .aqua, to: outputDirectory.appendingPathComponent("Cue-preview-light.png"))
        try render(view: SidecarView(model: model), size: NSSize(width: 372, height: 600), appearance: .darkAqua, to: outputDirectory.appendingPathComponent("Cue-preview-dark.png"))
        try render(view: SidecarView(model: model), size: NSSize(width: 352, height: 500), appearance: .aqua, to: outputDirectory.appendingPathComponent("Cue-preview-min-light.png"))
        try render(view: SidecarView(model: model), size: NSSize(width: 560, height: 500), appearance: .darkAqua, to: outputDirectory.appendingPathComponent("Cue-preview-wide-short-dark.png"))
        model.updateSettings { $0.panelPinned = true }
        try render(view: SidecarView(model: model), size: NSSize(width: 352, height: 500), appearance: .aqua, to: outputDirectory.appendingPathComponent("Cue-preview-min-panel-pinned.png"))
        model.updateSettings { $0.panelPinned = false }
        let emptyRailModel = try makePreviewModel()
        let emptyRailIDs = Set(emptyRailModel.document?.items.filter { $0.state == .queued }.map(\.id) ?? [])
        emptyRailModel.archive(emptyRailIDs)
        let leftRailChrome = PanelChromeModel()
        leftRailChrome.state = .retracted(.left)
        try render(
            view: EdgeTabPreviewScene(model: emptyRailModel, chrome: leftRailChrome, edge: .left),
            size: NSSize(width: 214, height: 136),
            appearance: .aqua,
            to: outputDirectory.appendingPathComponent("Cue-edge-tab-left-light-count0.png")
        )

        let rightRailChrome = PanelChromeModel()
        rightRailChrome.state = .retracted(.right)
        try render(
            view: EdgeTabPreviewScene(model: model, chrome: rightRailChrome, edge: .right),
            size: NSSize(width: 214, height: 136),
            appearance: .darkAqua,
            to: outputDirectory.appendingPathComponent("Cue-edge-tab-right-dark-count2.png")
        )

        let opaqueRailModel = try makePreviewModel()
        opaqueRailModel.updateSettings { $0.reduceTranslucency = true }
        let opaqueRailChrome = PanelChromeModel()
        opaqueRailChrome.state = .retracted(.right)
        try render(
            view: EdgeTabPreviewScene(model: opaqueRailModel, chrome: opaqueRailChrome, edge: .right),
            size: NSSize(width: 214, height: 136),
            appearance: .aqua,
            to: outputDirectory.appendingPathComponent("Cue-edge-tab-right-opaque-count2.png")
        )
        model.selectedItemIDs = Set(model.visibleItems().prefix(2).map(\.id))
        model.publishReceipt(Receipt(message: "2 items copied", symbol: "doc.on.doc.fill"))
        try render(view: SidecarView(model: model), size: NSSize(width: 352, height: 500), appearance: .aqua, to: outputDirectory.appendingPathComponent("Cue-preview-min-batch-receipt.png"))
        model.clearSelection()
        try render(view: SettingsView(model: model), size: NSSize(width: 700, height: 480), appearance: .aqua, to: outputDirectory.appendingPathComponent("Cue-settings-light.png"))
        try render(view: SettingsView(model: model), size: NSSize(width: 700, height: 480), appearance: .darkAqua, to: outputDirectory.appendingPathComponent("Cue-settings-dark.png"))

        let emptyRoot = FileManager.default.temporaryDirectory.appendingPathComponent("CueOnboardingPreview-\(UUID())", isDirectory: true)
        let emptyModel = AppModel(settingsStore: SettingsStore(directoryURL: emptyRoot), workspaceStore: WorkspaceStore())
        try render(view: SidecarView(model: emptyModel), size: NSSize(width: 372, height: 600), appearance: .aqua, to: outputDirectory.appendingPathComponent("Cue-onboarding-light.png"))
        try render(view: SidecarView(model: emptyModel), size: NSSize(width: 352, height: 500), appearance: .aqua, to: outputDirectory.appendingPathComponent("Cue-onboarding-min-light.png"))
    }

    private static func installPreviewApplicationIcon() throws {
        let iconURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/AppIcon.icns")
        guard let icon = NSImage(contentsOf: iconURL) else {
            throw NSError(
                domain: "CuePreview",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not load Resources/AppIcon.icns for preview rendering"]
            )
        }
        NSApplication.shared.applicationIconImage = icon
    }

    private static func makePreviewModel() throws -> AppModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CuePreview-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let workspaceURL = root.appendingPathComponent("Product Launch.cue", isDirectory: true)
        let settingsStore = SettingsStore(directoryURL: root.appendingPathComponent("Settings", isDirectory: true))
        let workspaceStore = WorkspaceStore()

        var document = WorkspaceDocument(title: "Product Launch")
        let inbox = document.inbox.id
        let research = WorkSection(title: "Research", order: 1)
        document.sections.append(research)
        let now = Date()
        let first = "Compare the onboarding friction in the three strongest local-first tools."
        let second = "The useful unit is the next unresolved thought, not a clipboard entry or a permanent note."
        let third = "Draft the launch prompt with privacy boundaries stated before features."
        document.items = [
            WorkItem(body: first, kind: .prompt, sectionID: inbox, contentHash: ContentHasher.hash(first), createdAt: now.addingTimeInterval(-340), updatedAt: now, order: 0),
            WorkItem(body: second, kind: .selection, sectionID: research.id, source: SourceMetadata(appName: "Safari", bundleIdentifier: "com.apple.Safari"), contentHash: ContentHasher.hash(second), createdAt: now.addingTimeInterval(-220), updatedAt: now, pinned: true, order: 0),
            WorkItem(body: third, kind: .prompt, state: .completed, sectionID: research.id, contentHash: ContentHasher.hash(third), createdAt: now.addingTimeInterval(-110), updatedAt: now, completedAt: now.addingTimeInterval(-20), order: 1),
        ]
        _ = try workspaceStore.create(document: document, at: workspaceURL)

        var settings = AppSettings()
        settings.workspaces = [WorkspaceDescriptor(id: document.id, title: document.title, path: workspaceURL.path, lastOpenedAt: now)]
        settings.activeWorkspaceID = document.id
        try settingsStore.save(settings)
        return AppModel(settingsStore: settingsStore, workspaceStore: workspaceStore)
    }

    private static func render<V: View>(view: V, size: NSSize, appearance: NSAppearance.Name, to url: URL) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))

        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw NSError(domain: "CuePreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create preview bitmap"])
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "CuePreview", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode preview PNG"])
        }
        try data.write(to: url)
    }
}

@MainActor
private struct EdgeTabPreviewScene: View {
    @ObservedObject var model: AppModel
    @ObservedObject var chrome: PanelChromeModel
    var edge: PanelEdge

    var body: some View {
        HStack(spacing: 0) {
            if edge == .left { outsideDisplay }
            screenSurface
            if edge == .right { outsideDisplay }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var screenSurface: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            VStack(alignment: .leading, spacing: 11) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.11))
                    .frame(width: 112, height: 8)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.065))
                    .frame(width: 146, height: 6)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.065))
                    .frame(width: 128, height: 6)
            }
            .padding(.horizontal, 30)
            .padding(.top, 25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 0) {
                if edge == .right { Spacer(minLength: 0) }
                PanelRootView(model: model, chrome: chrome)
                    .frame(width: PanelGeometryPolicy.railSize.width, height: PanelGeometryPolicy.railSize.height)
                if edge == .left { Spacer(minLength: 0) }
            }
        }
    }

    private var outsideDisplay: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            Rectangle()
                .fill(Color.primary.opacity(0.045))
                .padding(.horizontal, 7)
        }
        .frame(width: 24)
        .overlay(alignment: edge == .left ? .trailing : .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.28))
                .frame(width: 1)
        }
    }
}
