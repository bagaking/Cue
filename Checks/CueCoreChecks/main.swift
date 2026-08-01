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
    let url = directory.appendingPathComponent("workspace.md")
    let store = WorkspaceStore()
    var document = sampleDocument()

    do {
        let fingerprint = try store.create(document: document, at: url)
        document.title = "Local change"
        try Data("external edit".utf8).write(to: url, options: .atomic)
        do {
            _ = try store.write(document: document, to: url, expectedFingerprint: fingerprint)
            check(false, "external edit blocks overwrite")
        } catch WorkspaceStoreError.externalModification {
            check(true, "external edit blocks overwrite")
        } catch {
            check(false, "external edit reports the correct conflict")
        }
        check(try String(contentsOf: url, encoding: .utf8) == "external edit", "conflict leaves external bytes untouched")

        let recovery = try MarkdownWorkspaceCodec.encode(document)
        let firstCopy = try store.saveConflictCopy(markdown: recovery, nextTo: url)
        let secondCopy = try store.saveConflictCopy(markdown: recovery, nextTo: url)
        check(try String(contentsOf: firstCopy, encoding: .utf8) == recovery, "conflict copy preserves exact recovery Markdown")
        check(firstCopy != secondCopy, "same-second conflict copies never overwrite each other")
    } catch {
        failed += 1
        print("FAIL  external conflict setup: \(error)")
    }

    let backupDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("CueCoreChecks-\(UUID())", isDirectory: true)
    let backupURL = backupDirectory.appendingPathComponent("workspace.md")
    do {
        let initial = try store.create(document: document, at: backupURL)
        document.items.append(WorkItem(body: "Next prompt", kind: .prompt, sectionID: document.inbox.id, contentHash: ContentHasher.hash("Next prompt"), order: 1))
        _ = try store.write(document: document, to: backupURL, expectedFingerprint: initial)
        let backups = try FileManager.default.contentsOfDirectory(at: backupDirectory.appendingPathComponent(".cue-backups"), includingPropertiesForKeys: nil)
        check(backups.filter { $0.pathExtension == "md" }.count == 1, "write creates timestamped backup")
        check(try store.load(from: backupURL).0.items.contains(where: { $0.body == "Next prompt" }), "post-write document remains parseable")
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
