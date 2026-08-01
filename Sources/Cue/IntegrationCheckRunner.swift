import Foundation

@MainActor
enum IntegrationCheckRunner {
    static func run() -> Int32 {
        var passed = 0
        var failed = 0

        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            if condition() {
                passed += 1
                print("PASS  \(name)")
            } else {
                failed += 1
                print("FAIL  \(name)")
            }
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CueIntegration-\(UUID())", isDirectory: true)
        let settingsStore = SettingsStore(directoryURL: root.appendingPathComponent("Settings", isDirectory: true))
        let model = AppModel(settingsStore: settingsStore, workspaceStore: WorkspaceStore())
        let firstURL = root.appendingPathComponent("Alpha.md")
        model.createWorkspace(title: "Alpha", at: firstURL)
        check(model.hasWorkspace && model.activeWorkspaceTitle == "Alpha", "workspace creation becomes active")

        let first = model.addItem(body: "First future prompt", kind: .prompt)
        let second = model.addItem(body: "Second future prompt", kind: .prompt)
        check(model.queuedCount == 2, "typed prompts share one queued lifecycle")
        check({ if case .captured = first { return true }; return false }(), "first prompt is captured")
        let exactWhitespace = "  indented code\n  stays indented\n"
        let exactCapture = model.addItem(body: exactWhitespace, kind: .selection)
        check({
            if case let .captured(item) = exactCapture { return item.body == exactWhitespace }
            return false
        }(), "captured content preserves meaningful edge whitespace")

        model.createSection(title: "Research")
        let researchID = model.activeSectionID!
        model.activateSection(model.document!.inbox.id)
        check(model.activeSectionTitle == "Inbox", "section headers can change the capture target")
        model.activateSection(researchID)
        check(model.activeSectionTitle == "Research", "the chosen capture target is explicit")
        model.activateSection(model.document!.inbox.id)

        let duplicate = model.addItem(body: "  second   FUTURE prompt ", kind: .selection)
        check({ if case .duplicate = duplicate { return true }; return false }(), "normalized duplicate is suppressed across kinds")

        guard case let .captured(firstItem) = first,
              case let .captured(secondItem) = second else {
            print("Cue integration checks: \(passed) passed, \(failed + 1) failed")
            return 1
        }

        model.togglePin(secondItem.id)
        check(model.visibleItems().first?.id == secondItem.id, "pinned items lead their visible section")
        model.togglePin(secondItem.id)
        model.clearSelection()
        model.moveFocus(offset: 1, extending: false, visibleOrder: [secondItem.id])
        check(model.focusedItemID == secondItem.id, "keyboard focus stays inside the rendered order")

        model.toggleCompletion([firstItem.id])
        check(model.document?.items.first(where: { $0.id == firstItem.id })?.state == .completed, "explicit completion changes state")
        model.updateSettings { $0.completeOnCopy = true }
        model.copy(ids: [firstItem.id], asList: false)
        check(model.document?.items.first(where: { $0.id == firstItem.id })?.state == .completed, "complete-on-copy never requeues a completed item")
        model.updateSettings { $0.completeOnCopy = false }
        model.undo()
        check(model.document?.items.first(where: { $0.id == firstItem.id })?.state == .queued, "completion undo restores queued state")

        model.prepareMerge([firstItem.id, secondItem.id])
        check(model.mergeRequest?.itemIDs.count == 2, "merge always presents a preview")
        model.setMergeStyle(asBullets: true)
        model.confirmMerge()
        let merged = model.document?.items.first(where: { $0.mergedFrom.count == 2 })
        check(merged?.body.hasPrefix("- First future prompt") == true, "merge respects chosen list format")
        check(model.document?.items.filter { [firstItem.id, secondItem.id].contains($0.id) }.allSatisfy { $0.state == .archived } == true, "merge archives originals with provenance")
        model.undo()
        check(model.document?.items.first(where: { $0.id == firstItem.id })?.state == .queued && model.document?.items.first(where: { $0.id == secondItem.id })?.state == .queued, "merge undo restores both originals")

        model.archive([firstItem.id])
        check(model.archiveCount == 1, "archive removes an item from the active queue")
        model.restore([firstItem.id])
        check(model.document?.items.first(where: { $0.id == firstItem.id })?.state == .queued, "Archive restore is recoverable")

        let secondURL = root.appendingPathComponent("Beta.md")
        model.createWorkspace(title: "Beta", at: secondURL)
        let betaID = model.settings.activeWorkspaceID!
        let alphaID = model.settings.workspaces.first(where: { $0.title == "Alpha" })!.id
        model.updateSettings { settings in
            settings.contextMappings = [
                ContextMapping(appBundleIdentifier: "com.example.Editor", titlePattern: "", workspaceID: betaID),
                ContextMapping(appBundleIdentifier: "com.example.Editor", titlePattern: "Alpha", workspaceID: alphaID),
            ]
        }
        let mappedSelection = SelectionCaptureService.Selection(
            text: "Mapped selection",
            source: SourceMetadata(appName: "Editor", bundleIdentifier: "com.example.Editor"),
            sourceBundleIdentifierForMapping: "com.example.Editor",
            sourceWindowTitleForMapping: "Alpha — release notes"
        )
        _ = model.addCapturedSelection(mappedSelection)
        check(model.settings.activeWorkspaceID == alphaID && model.activeWorkspaceTitle == "Alpha", "specific confirmed mapping wins over a generic app mapping")
        check(model.settings.activeWorkspaceID != betaID, "mapping does not remain in the wrong workspace")

        var externalDocument = model.document!
        externalDocument.title = "Alpha External"
        let externalBody = "External owner item"
        externalDocument.items.append(WorkItem(
            body: externalBody,
            kind: .prompt,
            sectionID: externalDocument.inbox.id,
            contentHash: ContentHasher.hash(externalBody),
            order: 99
        ))
        let originalExternalBytes = try! MarkdownWorkspaceCodec.encode(externalDocument)
        try? Data(originalExternalBytes.utf8).write(to: firstURL, options: .atomic)
        let conflictOutcome = model.addItem(body: "Must survive conflict", kind: .prompt)
        check({ if case .storageFailure = conflictOutcome { return true }; return false }(), "external edit blocks a new write")
        check(model.recoveryMarkdown?.contains("Must survive conflict") == true, "failed write retains intended content in recovery buffer")
        check((try? String(contentsOf: firstURL, encoding: .utf8)) == originalExternalBytes, "external file bytes are never silently overwritten")
        let firstRecovery = model.recoveryMarkdown
        let blockedSecondMutation = model.addItem(body: "Must not replace first recovery", kind: .prompt)
        check({ if case .storageFailure = blockedSecondMutation { return true }; return false }(), "a buffered recovery blocks later mutations")
        check(model.recoveryMarkdown == firstRecovery && model.recoveryMarkdown?.contains("Must not replace") == false, "later actions cannot overwrite buffered recovery")

        model.saveConflictCopy()
        let conflictCopies = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.contains("cue-conflict") } ?? []
        let savedConflict = conflictCopies.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.first
        check(savedConflict?.contains("Must survive conflict") == true, "Save Copy writes the intended recovery Markdown")
        check((try? String(contentsOf: firstURL, encoding: .utf8)) == originalExternalBytes, "Save Copy still preserves external owner bytes")

        model.reloadAfterExternalEdit()
        check(model.activeWorkspaceTitle == "Alpha External" && model.document?.title == "Alpha External", "reload adopts the external workspace title consistently")
        let postReload = model.addItem(body: "Post reload change", kind: .prompt)
        check({ if case .captured = postReload { return true }; return false }(), "writes resume after an explicit reload")
        model.undo()
        let afterFirstUndo = try? String(contentsOf: firstURL, encoding: .utf8)
        model.undo()
        check((try? String(contentsOf: firstURL, encoding: .utf8)) == afterFirstUndo, "failed conflict snapshots cannot poison later Undo")

        var nextExternal = model.document!
        let nextExternalBody = "Concurrent external addition"
        nextExternal.items.append(WorkItem(
            body: nextExternalBody,
            kind: .selection,
            sectionID: nextExternal.inbox.id,
            contentHash: ContentHasher.hash(nextExternalBody),
            order: 200
        ))
        let nextExternalMarkdown = try! MarkdownWorkspaceCodec.encode(nextExternal)
        try? Data(nextExternalMarkdown.utf8).write(to: firstURL, options: .atomic)
        _ = model.addItem(body: "Concurrent local addition", kind: .prompt)
        model.prepareConflictMerge()
        check(model.conflictMergeRequest?.preview.contains(nextExternalBody) == true && model.conflictMergeRequest?.preview.contains("Concurrent local addition") == true, "safe merge preview contains both non-overlapping sides")
        model.confirmConflictMerge()
        let mergedBytes = try? String(contentsOf: firstURL, encoding: .utf8)
        check(mergedBytes?.contains(nextExternalBody) == true && mergedBytes?.contains("Concurrent local addition") == true, "confirmed safe merge preserves both sides")
        check(model.recoveryMarkdown == nil && model.storageHealth.needsAttention == false, "safe merge clears recovery only after a verified write")

        let sameItemID = model.document!.items[0].id
        var overlappingExternal = model.document!
        let externalIndex = overlappingExternal.items.firstIndex(where: { $0.id == sameItemID })!
        overlappingExternal.items[externalIndex].body = "External version of the same item"
        overlappingExternal.items[externalIndex].contentHash = ContentHasher.hash(overlappingExternal.items[externalIndex].body)
        overlappingExternal.items[externalIndex].updatedAt = Date()
        let overlappingBytes = try! MarkdownWorkspaceCodec.encode(overlappingExternal)
        try? Data(overlappingBytes.utf8).write(to: firstURL, options: .atomic)
        model.editItem(sameItemID, body: "Local version of the same item")
        model.prepareConflictMerge()
        check(model.conflictMergeRequest == nil && model.recoveryMarkdown?.contains("Local version") == true, "same-object edits refuse automatic merge and retain local recovery")
        check((try? String(contentsOf: firstURL, encoding: .utf8))?.contains("External version") == true, "refused merge leaves the external owner file untouched")

        try? FileManager.default.removeItem(at: secondURL)
        model.updateSettings { settings in
            settings.contextMappings = [ContextMapping(
                appBundleIdentifier: "com.example.Missing",
                titlePattern: "",
                workspaceID: betaID
            )]
        }
        let alphaCount = model.document?.items.count
        let unavailableMapping = model.addCapturedSelection(.init(
            text: "Must not enter the wrong workspace",
            source: .none,
            sourceBundleIdentifierForMapping: "com.example.Missing",
            sourceWindowTitleForMapping: nil
        ))
        check({ if case .storageFailure = unavailableMapping { return true }; return false }(), "unavailable mapped workspace blocks capture")
        check(model.settings.activeWorkspaceID == alphaID && model.document?.items.count == alphaCount, "failed mapping never contaminates the current workspace")

        print("\nCue integration checks: \(passed) passed, \(failed) failed")
        return failed == 0 ? 0 : 1
    }
}
