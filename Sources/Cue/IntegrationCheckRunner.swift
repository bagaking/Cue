import AppKit
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

        func runLoop(for duration: TimeInterval) {
            let deadline = Date().addingTimeInterval(duration)
            while Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
        }

        func isRetracted(_ state: PanelPresentationState) -> Bool {
            if case .retracted = state { return true }
            return false
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CueIntegration-\(UUID())", isDirectory: true)
        let settingsStore = SettingsStore(directoryURL: root.appendingPathComponent("Settings", isDirectory: true))
        let workspaceStore = WorkspaceStore(cacheDirectoryURL: root.appendingPathComponent("Cache", isDirectory: true))
        let externalStore = WorkspaceStore(cacheDirectoryURL: root.appendingPathComponent("ExternalCache", isDirectory: true))
        let model = AppModel(settingsStore: settingsStore, workspaceStore: workspaceStore)
        let firstURL = root.appendingPathComponent("Alpha.cue", isDirectory: true)
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

        let secondURL = root.appendingPathComponent("Beta.cue", isDirectory: true)
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
        let originalExternalFingerprint = try! externalStore.write(
            document: externalDocument,
            to: firstURL,
            expectedFingerprint: externalStore.fingerprint(for: firstURL)
        )
        let conflictOutcome = model.addItem(body: "Must survive conflict", kind: .prompt)
        check({ if case .storageFailure = conflictOutcome { return true }; return false }(), "external edit blocks a new write")
        check(model.recoveryMarkdown?.contains("Must survive conflict") == true, "failed write retains intended content in recovery buffer")
        check((try? externalStore.fingerprint(for: firstURL)) == originalExternalFingerprint, "external package files are never silently overwritten")
        let firstRecovery = model.recoveryMarkdown
        let blockedSecondMutation = model.addItem(body: "Must not replace first recovery", kind: .prompt)
        check({ if case .storageFailure = blockedSecondMutation { return true }; return false }(), "a buffered recovery blocks later mutations")
        check(model.recoveryMarkdown == firstRecovery && model.recoveryMarkdown?.contains("Must not replace") == false, "later actions cannot overwrite buffered recovery")

        model.saveConflictCopy()
        let conflictCopies = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.contains("cue-conflict") } ?? []
        let savedConflict = conflictCopies.compactMap { try? externalStore.load(from: $0).0 }.first
        check(savedConflict?.items.contains(where: { $0.body == "Must survive conflict" }) == true, "Save Copy writes the intended recovery package")
        check((try? externalStore.fingerprint(for: firstURL)) == originalExternalFingerprint, "Save Copy still preserves the external package")

        model.reloadAfterExternalEdit()
        check(model.activeWorkspaceTitle == "Alpha External" && model.document?.title == "Alpha External", "reload adopts the external workspace title consistently")
        let postReload = model.addItem(body: "Post reload change", kind: .prompt)
        check({ if case .captured = postReload { return true }; return false }(), "writes resume after an explicit reload")
        model.undo()
        let afterFirstUndo = try? externalStore.fingerprint(for: firstURL)
        model.undo()
        check((try? externalStore.fingerprint(for: firstURL)) == afterFirstUndo, "failed conflict snapshots cannot poison later Undo")

        var nextExternal = model.document!
        let nextExternalBody = "Concurrent external addition"
        nextExternal.items.append(WorkItem(
            body: nextExternalBody,
            kind: .selection,
            sectionID: nextExternal.inbox.id,
            contentHash: ContentHasher.hash(nextExternalBody),
            order: 200
        ))
        _ = try! externalStore.write(
            document: nextExternal,
            to: firstURL,
            expectedFingerprint: externalStore.fingerprint(for: firstURL)
        )
        _ = model.addItem(body: "Concurrent local addition", kind: .prompt)
        model.prepareConflictMerge()
        check(model.conflictMergeRequest?.preview.contains(nextExternalBody) == true && model.conflictMergeRequest?.preview.contains("Concurrent local addition") == true, "safe merge preview contains both non-overlapping sides")
        model.confirmConflictMerge()
        let mergedPackage = try? externalStore.load(from: firstURL).0
        check(mergedPackage?.items.contains(where: { $0.body == nextExternalBody }) == true && mergedPackage?.items.contains(where: { $0.body == "Concurrent local addition" }) == true, "confirmed safe merge preserves both sides")
        check(model.recoveryMarkdown == nil && model.storageHealth.needsAttention == false, "safe merge clears recovery only after a verified write")

        let sameItemID = model.document!.items[0].id
        var overlappingExternal = model.document!
        let externalIndex = overlappingExternal.items.firstIndex(where: { $0.id == sameItemID })!
        overlappingExternal.items[externalIndex].body = "External version of the same item"
        overlappingExternal.items[externalIndex].contentHash = ContentHasher.hash(overlappingExternal.items[externalIndex].body)
        overlappingExternal.items[externalIndex].updatedAt = Date()
        _ = try! externalStore.write(
            document: overlappingExternal,
            to: firstURL,
            expectedFingerprint: externalStore.fingerprint(for: firstURL)
        )
        model.editItem(sameItemID, body: "Local version of the same item")
        model.prepareConflictMerge()
        check(model.conflictMergeRequest == nil && model.recoveryMarkdown?.contains("Local version") == true, "same-object edits refuse automatic merge and retain local recovery")
        check((try? externalStore.load(from: firstURL).0.items.first(where: { $0.id == sameItemID })?.body) == "External version of the same item", "refused merge leaves the external item untouched")

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

        let outsidePointer = NSPoint(x: -10_000, y: -10_000)
        let directShowProbe = FloatingPanelController(
            model: model,
            pointerLocationProvider: { outsidePointer },
            mouseButtonStateProvider: { false }
        )
        directShowProbe.show()
        runLoop(for: 1.4)
        check(isRetracted(directShowProbe.integrationPresentationState), "public explicit show retracts when the pointer was already outside")
        directShowProbe.hide()
        runLoop(for: 0.2)

        let poisonedToggleProbe = FloatingPanelController(
            model: model,
            pointerLocationProvider: { outsidePointer },
            mouseButtonStateProvider: { false }
        )
        poisonedToggleProbe.show()
        poisonedToggleProbe.runIntegrationSeedTransientEngagement()
        poisonedToggleProbe.toggle()
        runLoop(for: 0.24)
        poisonedToggleProbe.toggle()
        runLoop(for: 1.4)
        check(isRetracted(poisonedToggleProbe.integrationPresentationState), "public toggle reveal cannot inherit editing, drag or menu holds from its hidden epoch")
        poisonedToggleProbe.hide()
        runLoop(for: 0.2)

        var terminalPointer = NSPoint.zero
        let terminalRearmProbe = FloatingPanelController(
            model: model,
            pointerLocationProvider: { terminalPointer },
            mouseButtonStateProvider: { false }
        )
        let initialTerminalFrame = terminalRearmProbe.integrationPanelFrame
        terminalPointer = NSPoint(x: initialTerminalFrame.midX, y: initialTerminalFrame.midY)
        terminalRearmProbe.show()
        runLoop(for: 0.4)
        check(terminalRearmProbe.integrationPresentationState == .expanded, "current inside pointer keeps an explicitly shown panel expanded")
        terminalPointer = outsidePointer
        terminalRearmProbe.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))
        runLoop(for: 1.2)
        check(isRetracted(terminalRearmProbe.integrationPresentationState), "resize terminal resamples a missed pointer exit and rearms retraction")
        terminalRearmProbe.hide()
        runLoop(for: 0.2)

        var probePointer = NSPoint(x: -10_000, y: -10_000)
        let panelProbe = FloatingPanelController(model: model, pointerLocationProvider: { probePointer })
        if let expectedRail = panelProbe.runIntegrationRetractionProbe() {
            let probeDeadline = Date().addingTimeInterval(1.4)
            while Date() < probeDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            let actualRail = panelProbe.integrationPanelFrame
            check(panelProbe.integrationPresentationState == .retracted(.right) || panelProbe.integrationPresentationState == .retracted(.left), "actual NSPanel remains retracted beyond a complete synthetic reveal/retract cycle")
            check(abs(actualRail.width - expectedRail.width) < 0.5 && abs(actualRail.height - expectedRail.height) < 0.5, "actual retained-Sidecar NSPanel accepts the 22 by 88 rail frame")
            check(abs(actualRail.minX - expectedRail.minX) < 0.5 && abs(actualRail.minY - expectedRail.minY) < 0.5, "actual NSPanel lands on the derived screen-edge target")
            check(panelProbe.integrationPanelMinSize.width <= expectedRail.width && panelProbe.integrationContentMinSize.width <= expectedRail.width, "retracted NSPanel constraints no longer retain expanded minimum geometry")

            let canonicalBeforeRailClick = panelProbe.integrationExpandedFrame
            panelProbe.runIntegrationRailClick()
            runLoop(for: 0.35)
            let actualRailClick = panelProbe.integrationPanelFrame
            check(panelProbe.integrationPresentationState == .expanded, "clicking the rail explicitly expands the actual NSPanel")
            check(panelProbe.integrationLastRevealReason == .railClick, "rail click retains distinct explicit reveal semantics")
            check(panelProbe.integrationExpandedFrame == canonicalBeforeRailClick, "rail click never mutates canonical expanded geometry")
            check(actualRailClick.intersects(actualRail), "rail click expansion remains connected to its originating rail")
            if actualRail.midX > actualRailClick.midX {
                check(abs(actualRailClick.maxX - actualRail.maxX) < 0.5, "right rail click keeps the expanded panel on the clicked outer edge")
            } else {
                check(abs(actualRailClick.minX - actualRail.minX) < 0.5, "left rail click keeps the expanded panel on the clicked outer edge")
            }

            runLoop(for: 1.0)
            let railAfterClick = panelProbe.integrationPanelFrame
            check(isRetracted(panelProbe.integrationPresentationState), "rail-click reveal returns to the same compact lifecycle after disengagement")
            probePointer = NSPoint(x: railAfterClick.midX, y: railAfterClick.midY)
            panelProbe.runIntegrationPointerEntered(timestamp: ProcessInfo.processInfo.systemUptime + 0.001)
            let revealDeadline = Date().addingTimeInterval(1.1)
            while Date() < revealDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            let actualHover = panelProbe.integrationPanelFrame
            check(panelProbe.integrationPresentationState == .expanded, "validated rail hover reveals exactly one stable expanded preview")
            check(actualHover.intersects(railAfterClick), "actual hover preview preserves a continuous rail-to-content pointer path")
            if railAfterClick.midX > actualHover.midX {
                check(abs(actualHover.maxX - railAfterClick.maxX) < 0.5, "actual right-edge hover preview closes the outer strip gap")
            } else {
                check(abs(actualHover.minX - railAfterClick.minX) < 0.5, "actual left-edge hover preview closes the outer strip gap")
            }
        } else {
            check(false, "actual NSPanel owner derives a rail target")
        }
        panelProbe.hide()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let screenChangeCenter = NotificationCenter()
        let screenChangeFrameKey = "CueIntegrationRailScreenChange-\(UUID().uuidString)"
        let initialScreen = PanelScreenGeometry(
            id: "integration-screen",
            frame: NSRect(x: 0, y: 0, width: 1_400, height: 900),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_400, height: 900)
        )
        let initialCanonical = NSRect(x: 1_000, y: 150, width: 372, height: 600)
        UserDefaults.standard.set(NSStringFromRect(initialCanonical), forKey: screenChangeFrameKey)
        var screenChangeGeometries = [initialScreen]
        var screenChangePointer = NSPoint(x: -10_000, y: -10_000)
        let screenChangeProbe = FloatingPanelController(
            model: model,
            pointerLocationProvider: { screenChangePointer },
            mouseButtonStateProvider: { false },
            screenGeometryProvider: { screenChangeGeometries },
            notificationCenter: screenChangeCenter,
            savedFrameKey: screenChangeFrameKey
        )
        screenChangeProbe.show()
        runLoop(for: 1.4)
        let oldScreenRail = screenChangeProbe.integrationPanelFrame
        check(isRetracted(screenChangeProbe.integrationPresentationState), "screen-change probe naturally retracts through the public show path")
        screenChangePointer = NSPoint(x: oldScreenRail.midX, y: oldScreenRail.midY)
        screenChangeProbe.runIntegrationPointerEntered(timestamp: ProcessInfo.processInfo.systemUptime + 0.001)
        runLoop(for: 1.1)
        check(
            screenChangeProbe.integrationPresentationState == .expanded &&
                screenChangeProbe.integrationLastRevealReason == .hover,
            "screen-change probe reaches a real hover-expanded presentation"
        )

        let changedScreen = PanelScreenGeometry(
            id: initialScreen.id,
            frame: initialScreen.frame,
            visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 900)
        )
        screenChangeGeometries = [changedScreen]
        let repairedCanonical = PanelGeometryPolicy.repairExpandedFrame(
            initialCanonical,
            screens: screenChangeGeometries
        )!
        let repairedRail = PanelGeometryPolicy.railPlacement(
            for: repairedCanonical,
            screens: screenChangeGeometries
        )!
        let repairedHover = PanelGeometryPolicy.hoverExpandedFrame(
            canonicalExpandedFrame: repairedCanonical,
            railPlacement: repairedRail
        )
        screenChangePointer = NSPoint(x: repairedRail.frame.midX, y: repairedRail.frame.midY)
        screenChangeCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        runLoop(for: 0.1)
        check(
            screenChangeProbe.integrationPanelFrame == repairedHover &&
                repairedRail.edge == .left &&
                abs(repairedRail.frame.minX - oldScreenRail.minX) > 0.5,
            "screen parameters repair the hover preview onto a materially new rail"
        )

        screenChangeProbe.runIntegrationRailClick()
        runLoop(for: 0.35)
        let promotedAfterScreenChange = screenChangeProbe.integrationPanelFrame
        check(
            screenChangeProbe.integrationLastRevealReason == .railClick &&
                abs(promotedAfterScreenChange.minX - repairedRail.frame.minX) < 0.5,
            "CuePanel mouse events promote hover from the repaired rail instead of the stale edge"
        )
        check(
            screenChangeProbe.integrationExpandedFrame == repairedCanonical,
            "screen-repaired rail promotion leaves canonical expanded geometry unchanged"
        )

        screenChangeProbe.show()
        runLoop(for: 0.35)
        check(
            screenChangeProbe.integrationPanelFrame == repairedCanonical &&
                screenChangeProbe.integrationExpandedFrame == repairedCanonical,
            "public show restores the repaired canonical frame after rail promotion"
        )
        screenChangeProbe.hide()
        UserDefaults.standard.removeObject(forKey: screenChangeFrameKey)
        runLoop(for: 0.2)

        var animationEntryPointer = NSPoint(x: -10_000, y: -10_000)
        let animationEntryProbe = FloatingPanelController(
            model: model,
            pointerLocationProvider: { animationEntryPointer }
        )
        if let expectedRail = animationEntryProbe.runIntegrationRetractionProbe() {
            let generationBeforeEntry = animationEntryProbe.integrationPresentationGeneration
            RunLoop.current.run(until: Date().addingTimeInterval(0.06))
            animationEntryPointer = NSPoint(x: expectedRail.midX, y: expectedRail.midY)
            let settleDeadline = Date().addingTimeInterval(1.1)
            while Date() < settleDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            check(animationEntryProbe.integrationPresentationState == .expanded, "real pointer entry during rail animation is replayed after settle")
            check(animationEntryProbe.integrationPresentationGeneration == generationBeforeEntry + 1, "animation-period rail entry schedules exactly one hover reveal")
            check(animationEntryProbe.integrationPanelFrame.intersects(expectedRail), "animation-period entry reveals the same gap-free hover target")
        } else {
            check(false, "animation-period entry probe derives a rail target")
        }
        animationEntryProbe.hide()

        print("\nCue integration checks: \(passed) passed, \(failed) failed")
        return failed == 0 ? 0 : 1
    }
}
