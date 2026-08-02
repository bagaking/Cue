import Foundation

private var passed = 0
private var failed = 0

private func check(_ condition: @autoclosure () throws -> Bool, _ name: String) {
    do {
        if try condition() {
            passed += 1
            print("PASS  \(name)")
        } else {
            failed += 1
            print("FAIL  \(name)")
        }
    } catch {
        failed += 1
        print("FAIL  \(name): \(error)")
    }
}

private func checkModifierTapDetector() {
    var detector = ModifierTapDetector(window: 0.35)
    check(detector.handleModifiers(.targetAlone(side: .left), timestamp: 1.00) == false, "modifier first down waits")
    check(detector.handleModifiers(.none, timestamp: 1.04) == false, "modifier first release waits")
    _ = detector.handleModifiers(.targetAlone(side: .left), timestamp: 1.20)
    check(detector.handleModifiers(.none, timestamp: 1.24), "modifier second clean release fires")

    detector = ModifierTapDetector(window: 0.35)
    _ = detector.handleModifiers(.targetAlone(side: .left), timestamp: 2.00)
    detector.handleGestureBreak()
    _ = detector.handleModifiers(.none, timestamp: 2.04)
    _ = detector.handleModifiers(.targetAlone(side: .left), timestamp: 2.12)
    check(detector.handleModifiers(.none, timestamp: 2.16) == false, "typing breaks modifier gesture")

    detector = ModifierTapDetector(window: 0.35)
    _ = detector.handleModifiers(.targetAlone(side: .left), timestamp: 3.00)
    _ = detector.handleModifiers(.none, timestamp: 3.04)
    _ = detector.handleModifiers(.targetAlone(side: .right), timestamp: 3.12)
    check(detector.handleModifiers(.none, timestamp: 3.16) == false, "opposite Shift sides do not complete the gesture")
    _ = detector.handleModifiers(.targetAlone(side: .right), timestamp: 3.22)
    check(detector.handleModifiers(.none, timestamp: 3.26), "same-side Shift restarts and completes cleanly")
}

private func checkSelectionModel() {
    let ids = (0..<4).map { _ in UUID() }
    var selection = ItemSelectionModel()
    selection.select(ids[0])
    _ = selection.step(1, order: ids, extending: true)
    _ = selection.step(1, order: ids, extending: true)
    check(selection.selected == Set(ids[0...2]), "shift-arrow grows from stable anchor")
    check(selection.anchor == ids[0] && selection.lead == ids[2], "selection preserves anchor and lead")
}

private func sampleDocument() -> WorkspaceDocument {
    let section = WorkSection(title: "Research", order: 0)
    let source = SourceMetadata(appName: "Safari", bundleIdentifier: "com.apple.Safari")
    let body = "**Claim** with [source](https://example.com)\n\n- evidence one\n- evidence two"
    let item = WorkItem(
        body: body,
        kind: .selection,
        state: .completed,
        sectionID: section.id,
        source: source,
        contentHash: ContentHasher.hash(body),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_010),
        completedAt: Date(timeIntervalSince1970: 1_700_000_020),
        pinned: true,
        order: 0
    )
    return WorkspaceDocument(title: "Launch", sections: [section], items: [item])
}

private func checkMarkdown() {
    do {
        let source = sampleDocument()
        let markdown = try MarkdownWorkspaceCodec.encode(source)
        let decoded = try MarkdownWorkspaceCodec.decode(markdown)
        check(decoded.title == source.title, "Markdown preserves workspace title")
        check(decoded.items.first?.body == source.items.first?.body, "Markdown preserves multiline rich body")
        check(decoded.items.first?.source == source.items.first?.source, "Markdown preserves privacy-controlled source")
        check(decoded.items.first?.state == .completed && decoded.items.first?.pinned == true, "Markdown preserves lifecycle")

        let exactBody = "  let answer = 42\n\treturn answer\n"
        var exactDocument = source
        exactDocument.items[0].body = exactBody
        exactDocument.items[0].contentHash = ContentHasher.hash(exactBody)
        let exactDecoded = try MarkdownWorkspaceCodec.decode(MarkdownWorkspaceCodec.encode(exactDocument))
        check(exactDecoded.items.first?.body == exactBody, "Markdown preserves leading indentation and trailing newlines")

        let externallyAnnotated = markdown.replacingOccurrences(
            of: "> This file is the Cue workspace source of truth.",
            with: "> This file is the Cue workspace source of truth.\n\nExternal prose that Cue does not own."
        )
        let annotated = try MarkdownWorkspaceCodec.decode(externallyAnnotated)
        let reencoded = try MarkdownWorkspaceCodec.encode(annotated)
        check(reencoded.contains("External prose that Cue does not own."), "Markdown preserves unknown external prose")
        let secondReencode = try MarkdownWorkspaceCodec.encode(MarkdownWorkspaceCodec.decode(reencoded))
        check(secondReencode == reencoded, "Markdown repeated writes do not grow whitespace")

        let closing = "<!-- /cue:item -->"
        let insideSection = externallyAnnotated.replacingOccurrences(
            of: closing,
            with: "\(closing)\n\n- [ ] Hand-added external task",
            options: .backwards
        )
        let adopted = try MarkdownWorkspaceCodec.decode(insideSection)
        check(adopted.items.contains(where: { $0.body == "Hand-added external task" }), "Markdown adopts hand-added tasks in managed sections")
    } catch {
        failed += 1
        print("FAIL  Markdown round trip: \(error)")
    }
}

private func checkStorage() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CueCoreChecks-\(UUID())", isDirectory: true)
    let url = directory.appendingPathComponent("workspace.cue", isDirectory: true)
    let store = WorkspaceStore(cacheDirectoryURL: directory.appendingPathComponent("Cache", isDirectory: true))
    var document = sampleDocument()

    do {
        let fingerprint = try store.create(document: document, at: url)
        check(FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.yaml").path), "package writes a readable manifest")
        check(FileManager.default.fileExists(atPath: url.appendingPathComponent(WorkspacePackageCodec.sectionPath(document.sections[0])).path), "package writes one section record per section")
        let itemURL = url.appendingPathComponent(WorkspacePackageCodec.itemPath(document.items[0]))
        check(FileManager.default.fileExists(atPath: itemURL.path), "package writes one Markdown document per item")
        check(FileManager.default.fileExists(atPath: url.appendingPathComponent("assets/sha256").path), "package reserves content-addressed assets")
        let readableItem = try String(contentsOf: itemURL, encoding: .utf8)
        check(readableItem.contains(document.items[0].body), "item Markdown keeps the body directly readable")

        document.title = "Local change"
        let externalItem = readableItem.replacingOccurrences(of: "**Claim**", with: "**External claim**")
        try Data(externalItem.utf8).write(to: itemURL, options: .atomic)
        do {
            _ = try store.write(document: document, to: url, expectedFingerprint: fingerprint)
            check(false, "external edit blocks overwrite")
        } catch WorkspaceStoreError.externalModification {
            check(true, "external edit blocks overwrite")
        } catch {
            check(false, "external edit reports the correct conflict")
        }
        check(try String(contentsOf: itemURL, encoding: .utf8) == externalItem, "conflict leaves external item bytes untouched")
        check(try store.load(from: url).0.items[0].body.contains("External claim"), "reload adopts a direct Markdown body edit")

        let firstCopy = try store.saveConflictCopy(document: document, nextTo: url)
        let secondCopy = try store.saveConflictCopy(document: document, nextTo: url)
        check(try store.load(from: firstCopy).0.title == "Local change", "conflict copy preserves the intended package")
        check(firstCopy != secondCopy, "same-second conflict copies never overwrite each other")
    } catch {
        failed += 1
        print("FAIL  external conflict setup: \(error)")
    }

    let backupDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("CueCoreChecks-\(UUID())", isDirectory: true)
    let backupURL = backupDirectory.appendingPathComponent("workspace.cue", isDirectory: true)
    let backupStore = WorkspaceStore(cacheDirectoryURL: backupDirectory.appendingPathComponent("Cache", isDirectory: true))
    do {
        var backupDocument = sampleDocument()
        let removedID = backupDocument.items[0].id
        let removedItemPath = WorkspacePackageCodec.itemPath(backupDocument.items[0])
        let initial = try backupStore.create(document: backupDocument, at: backupURL)
        check(FileManager.default.fileExists(atPath: backupStore.searchIndexURL(for: backupDocument.id).path), "write rebuilds a local search cache")
        try FileManager.default.removeItem(at: backupStore.searchIndexURL(for: backupDocument.id))
        try backupStore.rebuildSearchIndex(for: backupDocument)
        check(FileManager.default.fileExists(atPath: backupStore.searchIndexURL(for: backupDocument.id).path), "search cache is rebuildable from package truth")

        backupDocument.items.append(WorkItem(body: "Next prompt", kind: .prompt, sectionID: backupDocument.inbox.id, contentHash: ContentHasher.hash("Next prompt"), order: 1))
        let secondFingerprint = try backupStore.write(document: backupDocument, to: backupURL, expectedFingerprint: initial)
        let backups = try FileManager.default.contentsOfDirectory(at: backupDirectory.appendingPathComponent(".cue-backups"), includingPropertiesForKeys: nil)
        check(backups.filter { $0.pathExtension == "cue" }.count == 1, "write creates a timestamped package backup")
        check(try backupStore.load(from: backupURL).0.items.contains(where: { $0.body == "Next prompt" }), "post-write package remains parseable")

        backupDocument.items.removeAll { $0.id == removedID }
        _ = try backupStore.write(document: backupDocument, to: backupURL, expectedFingerprint: secondFingerprint)
        check(FileManager.default.fileExists(atPath: backupURL.appendingPathComponent(WorkspacePackageCodec.tombstonePath(for: removedID)).path), "physical item deletion writes a tombstone")
        check(!FileManager.default.fileExists(atPath: backupURL.appendingPathComponent(removedItemPath).path), "deleted item document leaves the active item tree")

        let legacyURL = backupDirectory.appendingPathComponent("Legacy Workspace.md")
        try Data(MarkdownWorkspaceCodec.encode(sampleDocument()).utf8).write(to: legacyURL)
        do {
            _ = try backupStore.load(from: legacyURL)
            check(false, "legacy single-file workspaces stay outside the runtime path")
        } catch WorkspaceStoreError.invalidDocument {
            check(true, "legacy single-file workspaces stay outside the runtime path")
        }
        let importedURL = backupDirectory.appendingPathComponent("Imported Workspace.cue", isDirectory: true)
        _ = try backupStore.importLegacyWorkspace(from: legacyURL, to: importedURL)
        check(try backupStore.load(from: importedURL).0.items.count == 1, "one-time legacy importer rescues data into a package")
    } catch {
        failed += 1
        print("FAIL  backup and validation: \(error)")
    }
}

private func checkDuplicatePolicy() {
    let now = Date()
    let section = UUID()
    let body = "Same Thought"
    let item = WorkItem(body: body, kind: .selection, sectionID: section, contentHash: ContentHasher.hash(body), createdAt: now.addingTimeInterval(-1), order: 0)
    check(CapturePolicy.duplicate(body: "  same   thought ", now: now, items: [item], windowSeconds: 2)?.id == item.id, "normalized duplicate within window is suppressed")
    check(CapturePolicy.duplicate(body: body, now: now.addingTimeInterval(4), items: [item], windowSeconds: 2) == nil, "old capture does not suppress")
}

private func effectToken(
    _ effects: [PanelPresentationEffect],
    matching predicate: (PanelPresentationEffect) -> Int?
) -> Int? {
    effects.compactMap(predicate).first
}

private func checkPanelPresentation() {
    var machine = PanelPresentationMachine()
    let explicit = machine.handle(.show(reason: .explicit))
    check(machine.state == .expanded, "explicit show enters expanded presentation")
    check(explicit.contains(.presentExpanded(reason: .explicit)) && PanelRevealReason.explicit.allowsFocus, "explicit reveal is the focus-capable contract")

    let firstExit = machine.handle(.hoverExited)
    let firstRetractToken = effectToken(firstExit) { effect in
        if case let .scheduleRetraction(token) = effect { return token }
        return nil
    }!
    _ = machine.handle(.hoverEntered)
    let staleRetract = machine.handle(.retractDeadline(token: firstRetractToken, edge: .right))
    check(machine.state == .expanded && staleRetract.isEmpty, "re-enter invalidates a stale retract deadline")

    let secondExit = machine.handle(.hoverExited)
    let retractToken = effectToken(secondExit) { effect in
        if case let .scheduleRetraction(token) = effect { return token }
        return nil
    }!
    let retract = machine.handle(.retractDeadline(token: retractToken, edge: .right))
    check(machine.state == .retracted(.right) && retract.contains(.presentRetracted), "valid exit deadline retracts to its derived edge")

    let firstEnter = machine.handle(.hoverEntered)
    let staleHoverToken = effectToken(firstEnter) { effect in
        if case let .scheduleHoverReveal(token) = effect { return token }
        return nil
    }!
    _ = machine.handle(.hoverExited)
    let staleHover = machine.handle(.hoverRevealDeadline(token: staleHoverToken))
    check(machine.state == .retracted(.right) && staleHover.isEmpty, "rail exit invalidates a stale hover reveal")

    let secondEnter = machine.handle(.hoverEntered)
    let hoverToken = effectToken(secondEnter) { effect in
        if case let .scheduleHoverReveal(token) = effect { return token }
        return nil
    }!
    let hoverReveal = machine.handle(.hoverRevealDeadline(token: hoverToken))
    check(machine.state == .expanded && hoverReveal.contains(.presentExpanded(reason: .hover)), "bounded rail hover reveals the panel")
    check(!PanelRevealReason.hover.allowsFocus, "hover reveal cannot request focus")
    check(PanelRevealReason.hover.usesTemporaryFloatingLevel && !PanelRevealReason.railClick.usesTemporaryFloatingLevel, "only hover preview receives a temporary reachability level")
    check(PanelRevealReason.hover.usesRailAnchor, "hover preview remains anchored to its originating rail")
    check(PanelRevealReason.railClick.allowsFocus && PanelRevealReason.railClick.usesRailAnchor, "rail click is focus-capable without abandoning its originating edge")
    check(PanelRevealReason.explicit.allowsFocus && !PanelRevealReason.explicit.usesRailAnchor, "global explicit reveal restores canonical expanded geometry")

    let pinExit = machine.handle(.hoverExited)
    let pinDeadline = effectToken(pinExit) { effect in
        if case let .scheduleRetraction(token) = effect { return token }
        return nil
    }!
    _ = machine.handle(.retractDeadline(token: pinDeadline, edge: .left))
    let pinEffects = machine.handle(.setPinned(true))
    check(machine.state == .expanded && pinEffects.contains(.presentExpanded(reason: .pin)), "Panel Pin forces a visible rail expanded and cancels work")
    let unpinEffects = machine.handle(.setPinned(false))
    check(machine.state == .expanded && !unpinEffects.contains(where: { if case .scheduleRetraction = $0 { return true }; return false }), "unpin does not instantly retract")

    let escapeExit = machine.handle(.hoverExited)
    let escapeToken = effectToken(escapeExit) { effect in
        if case let .scheduleRetraction(token) = effect { return token }
        return nil
    }!
    _ = machine.handle(.hide)
    _ = machine.handle(.retractDeadline(token: escapeToken, edge: .left))
    check(machine.state == .hidden, "Escape or close invalidates older presentation callbacks")

    _ = machine.handle(.toggle)
    check(machine.state == .expanded, "status or hotkey toggle explicitly expands hidden Cue")
    let toggleExit = machine.handle(.hoverExited)
    let toggleToken = effectToken(toggleExit) { effect in
        if case let .scheduleRetraction(token) = effect { return token }
        return nil
    }!
    _ = machine.handle(.retractDeadline(token: toggleToken, edge: .right))
    let railToggle = machine.handle(.toggle)
    check(machine.state == .expanded && railToggle.contains(.presentExpanded(reason: .explicit)), "status or hotkey toggle explicitly expands a rail")

    for _ in 0..<20 {
        let exit = machine.handle(.hoverExited)
        let token = effectToken(exit) { effect in
            if case let .scheduleRetraction(token) = effect { return token }
            return nil
        }!
        _ = machine.handle(.retractDeadline(token: token, edge: .right))
        let enter = machine.handle(.hoverEntered)
        let hover = effectToken(enter) { effect in
            if case let .scheduleHoverReveal(token) = effect { return token }
            return nil
        }!
        _ = machine.handle(.hoverRevealDeadline(token: hover))
    }
    check(machine.state == .expanded, "20 retract and reveal cycles finish without state drift")
}

private func checkPanelTrackingPolicy() {
    check(!PanelTrackingPolicy.accepts(.entered, eventTimestamp: 20, fence: 10, isAnimating: true, actualPointerInside: true, actualPointerMovedSinceSettle: true, requiresPhysicalMotionEvidence: true), "tracking enter during programmatic animation is ignored")
    check(!PanelTrackingPolicy.accepts(.exited, eventTimestamp: 10, fence: 10, isAnimating: false, actualPointerInside: false, actualPointerMovedSinceSettle: true, requiresPhysicalMotionEvidence: true), "queued tracking event at the settle fence is ignored")
    check(!PanelTrackingPolicy.accepts(.entered, eventTimestamp: 20, fence: 10, isAnimating: false, actualPointerInside: true, actualPointerMovedSinceSettle: false, requiresPhysicalMotionEvidence: true), "window movement under a stationary pointer cannot manufacture rail entry")
    check(!PanelTrackingPolicy.accepts(.entered, eventTimestamp: 20, fence: 10, isAnimating: false, actualPointerInside: true, actualPointerMovedSinceSettle: nil, requiresPhysicalMotionEvidence: true), "post-move rail entry fails closed when physical motion cannot be proved")
    check(!PanelTrackingPolicy.accepts(.entered, eventTimestamp: 20, fence: 10, isAnimating: false, actualPointerInside: false, actualPointerMovedSinceSettle: true, requiresPhysicalMotionEvidence: true), "tracking enter contradicted by Quartz position is rejected")
    check(!PanelTrackingPolicy.accepts(.exited, eventTimestamp: 20, fence: 10, isAnimating: false, actualPointerInside: true, actualPointerMovedSinceSettle: true, requiresPhysicalMotionEvidence: true), "tracking exit contradicted by Quartz position is rejected")
    check(PanelTrackingPolicy.accepts(.entered, eventTimestamp: 20, fence: 10, isAnimating: false, actualPointerInside: true, actualPointerMovedSinceSettle: true, requiresPhysicalMotionEvidence: true), "genuine post-fence tracking enter is accepted")
    check(PanelTrackingPolicy.accepts(.exited, eventTimestamp: 20, fence: 10, isAnimating: false, actualPointerInside: false, actualPointerMovedSinceSettle: true, requiresPhysicalMotionEvidence: true), "genuine post-fence tracking exit is accepted")
    check(PanelTrackingPolicy.accepts(.entered, eventTimestamp: 20, fence: 10, isAnimating: false, actualPointerInside: nil, actualPointerMovedSinceSettle: nil, requiresPhysicalMotionEvidence: false), "native tracking remains usable before any programmatic frame settle")

    let rail = CGRect(x: 100, y: 200, width: 22, height: 88)
    check(!PanelTrackingPolicy.shouldReplayRailEntry(transitionStartPointer: CGPoint(x: 110, y: 220), settledPointer: CGPoint(x: 110, y: 220), railFrame: rail), "stationary cursor covered by a moving rail never replays entry")
    check(PanelTrackingPolicy.shouldReplayRailEntry(transitionStartPointer: CGPoint(x: 20, y: 20), settledPointer: CGPoint(x: 110, y: 220), railFrame: rail), "real movement into the rail during animation replays entry once at settle")
    check(!PanelTrackingPolicy.shouldReplayRailEntry(transitionStartPointer: CGPoint(x: 20, y: 20), settledPointer: CGPoint(x: 90, y: 220), railFrame: rail), "animation-period motion outside the final rail does not replay entry")
}

private func checkPanelGeometry() {
    let left = PanelScreenGeometry(
        id: "left",
        frame: CGRect(x: -1440, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: -1440, y: 0, width: 1440, height: 875)
    )
    let main = PanelScreenGeometry(
        id: "main",
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
    )
    let mostlyLeft = CGRect(x: -300, y: 180, width: 500, height: 600)
    check(PanelGeometryPolicy.ownerScreenIndex(for: mostlyLeft, screens: [left, main]) == 0, "owner screen uses greatest physical overlap across a negative origin")

    let mainExpanded = CGRect(x: 24, y: 140, width: 372, height: 600)
    let sharedPlacement = PanelGeometryPolicy.railPlacement(for: mainExpanded, screens: [left, main])
    check(sharedPlacement?.screenID == "main" && sharedPlacement?.edge == .right && sharedPlacement?.isPhysicalOuterEdge == true, "shared horizontal seam prefers the true outer edge")
    if let sharedPlacement {
        let totalVisibleArea = [left, main].reduce(CGFloat.zero) { partial, screen in
            let intersection = sharedPlacement.frame.intersection(screen.frame)
            return partial + (intersection.isNull ? 0 : intersection.width * intersection.height)
        }
        check(totalVisibleArea == sharedPlacement.frame.width * sharedPlacement.frame.height, "compact rail intersects displays only by its own area")
    }

    let docked = PanelScreenGeometry(
        id: "dock",
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 82, y: 0, width: 1358, height: 875)
    )
    check(PanelGeometryPolicy.railPlacement(for: mainExpanded, screens: [docked])?.edge == .right, "rail avoids a Dock or Stage Manager side inset when the other edge is clear")

    let upper = PanelScreenGeometry(
        id: "upper",
        frame: CGRect(x: 0, y: 900, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 900, width: 1440, height: 875)
    )
    let upperFrame = CGRect(x: 900, y: 1040, width: 420, height: 620)
    check(PanelGeometryPolicy.ownerScreenIndex(for: upperFrame, screens: [main, upper]) == 1, "vertical display layouts choose the screen containing the panel")

    let oversized = CGRect(x: 3000, y: -200, width: 900, height: 1200)
    let repaired = PanelGeometryPolicy.repairExpandedFrame(oversized, screens: [main])
    check(repaired?.width == 560 && repaired?.height == 859, "screen repair clamps expanded size to configured and visible limits")
    check(repaired.map { main.visibleFrame.insetBy(dx: 8, dy: 8).contains($0) } == true, "screen removal repairs expanded geometry into the remaining visible frame")

    let minimum = CGRect(x: 100, y: 100, width: 100, height: 100)
    let minimumRepair = PanelGeometryPolicy.repairExpandedFrame(minimum, screens: [main])
    check(minimumRepair?.size == PanelGeometryPolicy.minimumExpandedSize, "expanded geometry enforces the 352 by 500 minimum")

    let stable = CGRect(x: 900, y: 120, width: 420, height: 620)
    let stableRepair = PanelGeometryPolicy.repairExpandedFrame(stable, screens: [main])
    let stableRail = PanelGeometryPolicy.railPlacement(for: stable, screens: [main])?.frame
    check(stableRepair == stable, "deriving a rail leaves canonical expanded size and position unchanged")
    check((0..<20).allSatisfy { _ in PanelGeometryPolicy.railPlacement(for: stable, screens: [main])?.frame == stableRail }, "20 geometry derivations are deterministic and drift-free")

    let runtimeCanonical = CGRect(x: 1649, y: 87, width: 399, height: 592)
    let runtimeRail = PanelRailPlacement(
        edge: .right,
        frame: CGRect(x: 2034, y: 339, width: 22, height: 88),
        screenID: "main",
        isPhysicalOuterEdge: true
    )
    let rightHover = PanelGeometryPolicy.hoverExpandedFrame(canonicalExpandedFrame: runtimeCanonical, railPlacement: runtimeRail)
    check(rightHover.maxX == runtimeRail.frame.maxX, "right-edge hover preview closes the observed 8-point rail gap")
    check(rightHover.intersects(runtimeRail.frame), "right-edge rail and hover preview form one continuous pointer target")
    check(runtimeCanonical.maxX == 2048, "deriving a hover bridge leaves canonical expanded geometry unchanged")

    let leftCanonical = CGRect(x: -1432, y: 100, width: 400, height: 600)
    let leftRail = PanelRailPlacement(edge: .left, frame: CGRect(x: -1440, y: 356, width: 22, height: 88), screenID: "left", isPhysicalOuterEdge: true)
    let leftHover = PanelGeometryPolicy.hoverExpandedFrame(canonicalExpandedFrame: leftCanonical, railPlacement: leftRail)
    check(leftHover.minX == leftRail.frame.minX && leftHover.intersects(leftRail.frame), "negative-origin left-edge hover preview remains gap-free")

    let tiny = PanelScreenGeometry(id: "tiny", frame: CGRect(x: 0, y: 0, width: 30, height: 40), visibleFrame: CGRect(x: 0, y: 0, width: 30, height: 40))
    check(PanelGeometryPolicy.railPlacement(for: stable, screens: [tiny]) == nil, "no usable rail geometry safely keeps Cue expanded")
}

private func checkPanelEngagementPolicy() {
    let idleKeyPanel = PanelEngagementSnapshot(
        panelPinned: false,
        pointerInside: false,
        isKeyWindow: true,
        isTextEditing: false
    )
    check(PanelEngagementPolicy.allowsAutoRetraction(idleKeyPanel), "an idle nonactivating key panel may retract")

    var editing = idleKeyPanel
    editing.isTextEditing = true
    check(!PanelEngagementPolicy.allowsAutoRetraction(editing), "actual text editing suppresses retraction")

    var notKeyButEditing = editing
    notKeyButEditing.isKeyWindow = false
    check(!PanelEngagementPolicy.allowsAutoRetraction(notKeyButEditing), "editing protection does not depend on the unreliable key flag")

    var mouseDrag = idleKeyPanel
    mouseDrag.mouseButtonDown = true
    check(!PanelEngagementPolicy.allowsAutoRetraction(mouseDrag), "mouse-down or drag suppresses retraction")

    var menu = idleKeyPanel
    menu.isMenuTracking = true
    check(!PanelEngagementPolicy.allowsAutoRetraction(menu), "menu tracking suppresses retraction")

    var sheet = idleKeyPanel
    sheet.hasAttachedSheet = true
    check(!PanelEngagementPolicy.allowsAutoRetraction(sheet), "an attached sheet suppresses retraction")

    var modal = idleKeyPanel
    modal.hasModalWindow = true
    check(!PanelEngagementPolicy.allowsAutoRetraction(modal), "a modal window suppresses retraction")

    var pinned = idleKeyPanel
    pinned.panelPinned = true
    check(!PanelEngagementPolicy.allowsAutoRetraction(pinned), "Panel Pin remains the explicit persistent hold")
}

private func checkPanelSettings() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CuePanelSettings-\(UUID())", isDirectory: true)
    let store = SettingsStore(directoryURL: root)
    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let oldJSON = """
        {
          "captureSourceApp" : true,
          "keepPanelOnTop" : false,
          "showInDock" : false,
          "workspaces" : []
        }
        """
        try Data(oldJSON.utf8).write(to: store.settingsURL, options: .atomic)
        let forwardFilled = store.load()
        check(forwardFilled.panelPinned == false && forwardFilled.keepPanelOnTop == false, "old settings JSON forward-fills Panel Pin as off")

        var settings = forwardFilled
        settings.panelPinned = true
        settings.keepPanelOnTop = false
        try store.save(settings)
        let roundTrip = store.load()
        check(roundTrip.panelPinned && !roundTrip.keepPanelOnTop, "Panel Pin round-trips independently from Always on Top")

        var item = WorkItem(body: "Pinned item", kind: .prompt, sectionID: UUID(), contentHash: "hash", pinned: true, order: 0)
        settings.panelPinned = false
        check(item.pinned && !settings.panelPinned, "WorkItem Pin is independent from Panel Pin")
        item.pinned = false
        settings.panelPinned = true
        check(!item.pinned && settings.panelPinned, "Panel Pin never mutates WorkItem metadata")
    } catch {
        failed += 1
        print("FAIL  Panel settings: \(error)")
    }
}

checkModifierTapDetector()
checkSelectionModel()
checkMarkdown()
checkStorage()
checkDuplicatePolicy()
checkPanelPresentation()
checkPanelTrackingPolicy()
checkPanelGeometry()
checkPanelEngagementPolicy()
checkPanelSettings()

print("\nCue core checks: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }
