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

checkModifierTapDetector()
checkSelectionModel()
checkMarkdown()
checkStorage()
checkDuplicatePolicy()

print("\nCue core checks: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }
