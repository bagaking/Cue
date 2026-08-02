import AppKit
import CueCore
import SwiftUI

@MainActor
enum PreviewRenderer {
    static func renderAll(outputDirectory: URL) throws {
        let model = try makePreviewModel()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try render(view: SidecarView(model: model), size: NSSize(width: 372, height: 600), appearance: .aqua, to: outputDirectory.appendingPathComponent("Cue-preview-light.png"))
        try render(view: SidecarView(model: model), size: NSSize(width: 372, height: 600), appearance: .darkAqua, to: outputDirectory.appendingPathComponent("Cue-preview-dark.png"))
        try render(view: SidecarView(model: model), size: NSSize(width: 352, height: 500), appearance: .aqua, to: outputDirectory.appendingPathComponent("Cue-preview-min-light.png"))
        try render(view: SidecarView(model: model), size: NSSize(width: 560, height: 500), appearance: .darkAqua, to: outputDirectory.appendingPathComponent("Cue-preview-wide-short-dark.png"))
        model.updateSettings { $0.panelPinned = true }
        try render(view: SidecarView(model: model), size: NSSize(width: 352, height: 500), appearance: .aqua, to: outputDirectory.appendingPathComponent("Cue-preview-min-panel-pinned.png"))
        model.updateSettings { $0.panelPinned = false }
        let railChrome = PanelChromeModel()
        railChrome.state = .retracted(.right)
        try render(view: PanelRootView(model: model, chrome: railChrome), size: PanelGeometryPolicy.railSize, appearance: .aqua, to: outputDirectory.appendingPathComponent("Cue-edge-rail.png"))
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

    private static func makePreviewModel() throws -> AppModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CuePreview-\(UUID())", isDirectory: true)
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
