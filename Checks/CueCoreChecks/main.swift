@_spi(Testing) import CueCore
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

private func writeSchema2Package(_ source: WorkspaceDocument, to url: URL) throws {
    let fileManager = FileManager.default
    var document = source
    document.ensureInbox()
    document.normalizeOrder()
    try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
    for path in ["sections", "items", "tombstones", "assets/sha256"] {
        try fileManager.createDirectory(
            at: url.appendingPathComponent(path, isDirectory: true),
            withIntermediateDirectories: true
        )
    }
    let formatter = ISO8601DateFormatter()
    func date(_ value: Date?) -> Any { value.map(formatter.string) ?? NSNull() }
    func nullable(_ value: String?) -> Any {
        if let value { return value }
        return NSNull()
    }
    func json(_ object: Any, pretty: Bool = true) throws -> Data {
        var options: JSONSerialization.WritingOptions = [.sortedKeys]
        if pretty { options.insert(.prettyPrinted) }
        var data = try JSONSerialization.data(withJSONObject: object, options: options)
        data.append(0x0A)
        return data
    }
    func sectionPath(_ section: WorkSection) -> String {
        "sections/\(section.id.uuidString.lowercased()).yaml"
    }
    func itemPath(_ item: WorkItem) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month], from: item.createdAt)
        return String(
            format: "items/%04d/%02d/%@.md",
            parts.year ?? 1970,
            parts.month ?? 1,
            item.id.uuidString.lowercased()
        )
    }
    let manifest: [String: Any] = [
        "cue_schema": 2,
        "cue_workspace_id": document.id.uuidString,
        "title": document.title,
        "sections": document.sections.map(sectionPath).sorted(),
        "items": document.items.map(itemPath).sorted(),
    ]
    try json(manifest).write(to: url.appendingPathComponent("manifest.yaml"))
    for section in document.sections {
        try json([
            "id": section.id.uuidString,
            "title": section.title,
            "order": section.order,
            "is_collapsed": section.isCollapsed,
        ]).write(to: url.appendingPathComponent(sectionPath(section)))
    }
    for item in document.items {
        let metadata: [String: Any] = [
            "cue_schema": 2,
            "cue_workspace_id": document.id.uuidString,
            "id": item.id.uuidString,
            "kind": item.kind.rawValue,
            "state": item.state.rawValue,
            "section_id": item.sectionID.uuidString,
            "source": [
                "appName": nullable(item.source.appName),
                "bundleIdentifier": nullable(item.source.bundleIdentifier),
                "windowTitle": nullable(item.source.windowTitle),
                "url": nullable(item.source.url),
            ] as [String: Any],
            "sensitivity": item.sensitivity.rawValue,
            "created_at": formatter.string(from: item.createdAt),
            "updated_at": formatter.string(from: item.updatedAt),
            "completed_at": date(item.completedAt),
            "archived_at": date(item.archivedAt),
            "pinned": item.pinned,
            "order": item.order,
            "merged_from": item.mergedFrom.map(\.uuidString),
            "merged_into": item.mergedInto?.uuidString ?? NSNull(),
        ]
        var metadataData = try json(metadata, pretty: false)
        metadataData.removeLast()
        var data = Data("<!-- cue:item ".utf8)
        data.append(metadataData)
        data.append(Data(" -->\n".utf8))
        data.append(Data(item.body.utf8))
        data.append(Data("\n<!-- /cue:item -->\n".utf8))
        let destination = url.appendingPathComponent(itemPath(item))
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination)
    }
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

private func checkItemRecordCodec() {
    func expectInvalid(_ data: Data, _ message: String) {
        do {
            _ = try CueItemRecordCodec.decode(data)
            check(false, message)
        } catch WorkspaceStoreError.invalidDocument {
            check(true, message)
        } catch {
            check(false, "\(message) (unexpected error: \(error))")
        }
    }

    do {
        let document = sampleDocument()
        let item = document.items[0]
        let fresh = CueItemRecord(workspaceID: document.id, item: item)
        let canonical = try CueItemRecordCodec.encode(fresh)
        check(try CueItemRecordCodec.encode(fresh) == canonical, "fresh cue.md encoding is deterministic")
        let canonicalDecoded = try CueItemRecordCodec.decode(canonical)
        check(canonicalDecoded.workspaceID == document.id && canonicalDecoded.item.body == item.body, "shared cue.md codec round-trips a fresh record")
        check(try CueItemRecordCodec.encode(canonicalDecoded) == canonical, "unchanged cue.md record bytes round-trip exactly")

        let canonicalString = String(data: canonical, encoding: .utf8)!
        var nilOptionalItem = item
        nilOptionalItem.completedAt = nil
        nilOptionalItem.archivedAt = nil
        nilOptionalItem.mergedInto = nil
        nilOptionalItem.source = .none
        let nilOptionalString = String(
            data: try CueItemRecordCodec.encode(CueItemRecord(workspaceID: document.id, item: nilOptionalItem)),
            encoding: .utf8
        )!
        check(nilOptionalString.contains(#""archived_at":null"#) && nilOptionalString.contains(#""completed_at":null"#) && nilOptionalString.contains(#""merged_into":null"#), "fresh cue.md records emit absent optional known fields explicitly as null")
        check(nilOptionalString.contains(#""appName":null"#) && nilOptionalString.contains(#""bundleIdentifier":null"#) && nilOptionalString.contains(#""windowTitle":null"#) && nilOptionalString.contains(#""url":null"#), "fresh cue.md source metadata emits absent optional known fields explicitly as null")
        let cueLine = canonicalString.split(separator: "\n", omittingEmptySubsequences: false)
            .first(where: { $0.hasPrefix("cue: ") })!
        let canonicalObject = String(cueLine.dropFirst("cue: ".count))
        let unknownMember = #", "future" : { "nested" : [1, { "glyph" : "\u0065\u0301" }] }"#
        let nestedUnknownMember = #" "future_context" : { "escaped" : "\u0065\u0301", "array" : [1, 2] } ,"#
        let sourceOpening = #""source":{"#
        let objectWithNestedUnknown = canonicalObject.replacingOccurrences(
            of: sourceOpening,
            with: sourceOpening + nestedUnknownMember
        )
        let customObject = String(objectWithNestedUnknown.dropLast()) + unknownMember + "}"
        let prefix = "---\r\n# frontmatter comment\r\ntitle: External title\r\ncue: "
        let suffix = "   \r\ntags: [one, two] # keep\r\n\r\n---\r\n"
        let body = "\r\n  leading\r\nNUL:\0\ndecomposed: e\u{0301}\nno final newline"
        let custom = Data((prefix + customObject + suffix + body).utf8)
        let decoded = try CueItemRecordCodec.decode(custom)
        check(try CueItemRecordCodec.encode(decoded) == custom, "cue.md preserves CRLF frontmatter, comments, unknown Cue bytes, and body bytes")

        var metadataEdit = decoded
        metadataEdit.item.pinned.toggle()
        let metadataEdited = try CueItemRecordCodec.encode(metadataEdit)
        check(metadataEdited.starts(with: Data(prefix.utf8)), "known metadata edits preserve non-Cue frontmatter prefix bytes")
        check(metadataEdited.range(of: Data(unknownMember.utf8)) != nil, "known metadata edits preserve unknown Cue member bytes and order")
        check(metadataEdited.range(of: Data(nestedUnknownMember.utf8)) != nil, "known metadata edits preserve nested unknown Cue member bytes and order")
        let originalBodyData = Data(body.utf8)
        check(metadataEdited.range(of: Data(suffix.utf8)) != nil && metadataEdited.suffix(originalBodyData.count) == originalBodyData, "known metadata edits preserve frontmatter suffix and unchanged body bytes")

        var bodyEdit = decoded
        bodyEdit.item.body = "replacement body\r\nwithout final LF"
        let bodyEdited = try CueItemRecordCodec.encode(bodyEdit)
        let originalFrontmatter = Data((prefix + customObject + suffix).utf8)
        check(bodyEdited.starts(with: originalFrontmatter), "body-only edits preserve the complete frontmatter byte slice")
        let editedBodyData = Data(bodyEdit.item.body.utf8)
        check(bodyEdited.suffix(editedBodyData.count) == editedBodyData, "body-only edits write exactly the requested UTF-8 body bytes")

        let composedBody = "\r\n  leading\r\nNUL:\0\ndecomposed: \u{00E9}\nno final newline"
        var normalizationEdit = decoded
        normalizationEdit.item.body = composedBody
        let normalizationEdited = try CueItemRecordCodec.encode(normalizationEdit)
        check(normalizationEdited.suffix(Data(composedBody.utf8).count) == Data(composedBody.utf8), "canonically equivalent body edits still write the requested UTF-8 bytes")
        var normalizationAndMetadataEdit = normalizationEdit
        normalizationAndMetadataEdit.item.pinned.toggle()
        let normalizationAndMetadataEdited = try CueItemRecordCodec.encode(normalizationAndMetadataEdit)
        check(normalizationAndMetadataEdited.suffix(Data(composedBody.utf8).count) == Data(composedBody.utf8), "metadata edits cannot restore canonically equivalent original body bytes")

        expectInvalid(Data("---\nname: no cue key\n---\nbody".utf8), "cue.md without a top-level cue key is rejected")
        let duplicateCue = Data((prefix + customObject + "\r\ncue: " + customObject + suffix + body).utf8)
        expectInvalid(duplicateCue, "cue.md with duplicate top-level cue keys is rejected")

        let duplicateKnown = customObject.replacingOccurrences(of: "{", with: "{\"id\":\"\(item.id.uuidString)\",", options: [], range: customObject.startIndex..<customObject.index(after: customObject.startIndex))
        expectInvalid(Data((prefix + duplicateKnown + suffix + body).utf8), "cue.md with duplicate Cue JSON members is rejected")

        let duplicateManagedNested = customObject.replacingOccurrences(
            of: sourceOpening,
            with: sourceOpening + #""appName":"duplicate","#
        )
        expectInvalid(Data((prefix + duplicateManagedNested + suffix + body).utf8), "cue.md with duplicate managed nested Cue members is rejected")
        let duplicateUnknownNested = String(canonicalObject.dropLast()) + #", "future_duplicate" : {"same":1,"same":2}}"#
        expectInvalid(Data((prefix + duplicateUnknownNested + suffix + body).utf8), "cue.md with duplicate unknown nested Cue members is rejected")

        expectInvalid(Data(("---\n  cue: " + canonicalObject + "\n---\nbody").utf8), "indented cue substitutes are rejected")
        expectInvalid(Data(("---\n\"cue\": " + canonicalObject + "\n---\nbody").utf8), "quoted cue substitutes are rejected")
        expectInvalid(Data("---\ncue: true\n---\nbody".utf8), "non-object cue values are rejected")
        expectInvalid(Data("---\ncue: {\n  \"schema\": 3\n}\n---\nbody".utf8), "multiline cue objects are rejected")
        expectInvalid(Data(("---\ncue: " + String(canonicalObject.dropLast()) + ",}\n---\nbody").utf8), "malformed cue JSON is rejected")
        expectInvalid(Data(("---\ncue: " + canonicalObject + " # comment\n---\nbody").utf8), "inline comments after cue JSON are rejected")

        let missingKnownObject = canonicalObject.replacingOccurrences(of: #""archived_at":null,"#, with: "")
        expectInvalid(Data(("---\ncue: " + missingKnownObject + "\n---\nbody").utf8), "cue JSON missing a known member is rejected")
        let missingNestedKnownObject = canonicalObject.replacingOccurrences(of: #""url":null,"#, with: "")
        expectInvalid(Data(("---\ncue: " + missingNestedKnownObject + "\n---\nbody").utf8), "cue JSON missing a known nested source member is typed invalid")

        var invalidUTF8 = custom
        invalidUTF8.append(0xFF)
        expectInvalid(invalidUTF8, "cue.md with invalid UTF-8 is rejected")
    } catch {
        failed += 1
        print("FAIL  shared cue.md codec: \(error)")
    }
}

private func checkPackagePlan() {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("CuePackagePlanChecks-\(UUID())", isDirectory: true)

    func entryType(at url: URL) throws -> FileAttributeType {
        try fileManager.attributesOfItem(atPath: url.path)[.type] as! FileAttributeType
    }

    func treeState(at url: URL) throws -> [String: Data] {
        var state: [String: Data] = [:]
        func walk(_ current: URL, relative: String) throws {
            let type = try entryType(at: current)
            var value = Data(type.rawValue.utf8)
            if type == .typeSymbolicLink {
                value.append(Data((try fileManager.destinationOfSymbolicLink(atPath: current.path)).utf8))
            } else if type == .typeRegular {
                value.append(try Data(contentsOf: current))
            }
            state[relative] = value
            guard type == .typeDirectory else { return }
            for child in try fileManager.contentsOfDirectory(at: current, includingPropertiesForKeys: nil, options: [])
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let childRelative = relative == "." ? child.lastPathComponent : "\(relative)/\(child.lastPathComponent)"
                try walk(child, relative: childRelative)
            }
        }
        try walk(url, relative: ".")
        return state
    }

    func parentNames(of url: URL) throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: url.deletingLastPathComponent().path).sorted()
    }

    func itemFile(in package: URL, suffix: String) throws -> URL {
        let items = package.appendingPathComponent("items", isDirectory: true)
        guard let enumerator = fileManager.enumerator(at: items, includingPropertiesForKeys: nil) else {
            throw WorkspaceStoreError.invalidDocument("test fixture has no item enumerator")
        }
        for case let candidate as URL in enumerator where candidate.lastPathComponent.hasSuffix(suffix) {
            if try entryType(at: candidate) == .typeRegular { return candidate }
        }
        throw WorkspaceStoreError.invalidDocument("test fixture has no item file")
    }

    func writePlan(_ plan: CueSchema3PackagePlan, to package: URL) throws {
        try fileManager.createDirectory(at: package, withIntermediateDirectories: false)
        for directory in plan.directories {
            try fileManager.createDirectory(
                at: package.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        for file in plan.files {
            let destination = package.appendingPathComponent(file.path)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.data.write(to: destination)
        }
    }

    func rewriteManifest(at package: URL, mutate: (inout [String: Any]) -> Void) throws {
        let manifestURL = package.appendingPathComponent("manifest.yaml")
        try rewriteJSONObject(at: manifestURL, mutate: mutate)
    }

    func rewriteJSONObject(at url: URL, mutate: (inout [String: Any]) -> Void) throws {
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        mutate(&object)
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        data.append(0x0A)
        try data.write(to: url)
    }

    func prependJSONMember(_ member: String, at url: URL) throws {
        var text = try String(contentsOf: url, encoding: .utf8)
        guard let opening = text.firstIndex(of: "{") else {
            throw WorkspaceStoreError.invalidDocument("test fixture has no JSON object")
        }
        text.insert(contentsOf: "\(member),", at: text.index(after: opening))
        try Data(text.utf8).write(to: url)
    }

    func copyPackage(_ source: URL, named name: String) throws -> URL {
        let destination = root.appendingPathComponent("\(name).cue", isDirectory: true)
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    func expectInvalid(_ package: URL, _ name: String) {
        do {
            let before = try treeState(at: package)
            let siblings = try parentNames(of: package)
            do {
                _ = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: package)
                check(false, name)
            } catch WorkspaceStoreError.invalidDocument {
                check(true, name)
            } catch {
                check(false, "\(name) (unexpected error: \(error))")
            }
            check(try treeState(at: package) == before && parentNames(of: package) == siblings, "\(name) is observational")
        } catch {
            check(false, "\(name) fixture: \(error)")
        }
    }

    do {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let schema2URL = root.appendingPathComponent("source.cue", isDirectory: true)
        var source = sampleDocument()
        let exactBody = "Case Fold\r\nNUL:\0\ndecomposed: e\u{0301}\nno final newline"
        source.items[0].body = exactBody
        source.items[0].contentHash = ContentHasher.hash(exactBody)
        try writeSchema2Package(source, to: schema2URL)

        let legacyItemURL = try itemFile(in: schema2URL, suffix: ".md")
        var legacyText = try String(contentsOf: legacyItemURL, encoding: .utf8)
        legacyText = legacyText.replacingOccurrences(
            of: #""source":{"#,
            with: #""source":{"future_source":{"keep":true},"#
        )
        let metadataEnd = legacyText.range(of: " -->\n")!.lowerBound
        let insertAt = legacyText.index(before: metadataEnd)
        legacyText.insert(contentsOf: #", "future_item" : {"keep":"yes"}"#, at: insertAt)
        try Data(legacyText.utf8).write(to: legacyItemURL)

        let tombstoneURL = schema2URL.appendingPathComponent("tombstones/\(source.items[0].id.uuidString.lowercased()).json")
        let legacyTombstone = """
        {"cue_workspace_id":"\(source.id.uuidString)","item_id":"\(source.items[0].id.uuidString)","deleted_at":"2020-01-01T00:00:00Z"}
        """
        try Data(legacyTombstone.utf8).write(to: tombstoneURL)

        let before = try treeState(at: schema2URL)
        let parentBefore = try parentNames(of: schema2URL)
        let legacyInspection = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: schema2URL)
        let plan = try CuePackagePlanner.planSchema3Migration(from: legacyInspection)
        check(try treeState(at: schema2URL) == before, "schema-2 inspection and planning preserve every package path, type, and byte")
        check(try parentNames(of: schema2URL) == parentBefore, "schema-2 planning creates no sibling stage, backup, or conflict copy")
        check(legacyInspection.writeCapability == .requiresVerifiedSchema2Migration, "schema-2 inspection exposes verified-migration capability")
        check(legacyInspection.document?.items.count == 1 && legacyInspection.conflicts.count == 1, "schema-2 manifest membership stays authoritative and clock tombstones preserve edits")
        check(plan.sourcePackageRevision == legacyInspection.packageRevision, "migration plan binds the observed recursive path and byte revision")

        let manifestData = plan.files.first(where: { $0.path == "manifest.yaml" })!.data
        let manifestObject = try JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
        check(Set(manifestObject.keys) == Set(["cue_schema", "cue_workspace_id", "title", "required_features"]), "schema-3 manifest has exactly four membership-free keys")
        check(manifestObject["items"] == nil && manifestObject["sections"] == nil, "schema-3 manifest stores no item or section membership")

        let plannedItem = plan.files.first(where: { $0.path.hasSuffix(".cue.md") })!
        check(plannedItem.data.range(of: Data(#""future_item" : {"keep":"yes"}"#.utf8)) != nil, "migration preserves unknown schema-2 item metadata")
        check(plannedItem.data.range(of: Data(#""future_source":{"keep":true}"#.utf8)) != nil, "migration preserves unknown schema-2 source metadata")
        check(plannedItem.data.suffix(Data(exactBody.utf8).count) == Data(exactBody.utf8), "migration preserves exact schema-2 Markdown body bytes")

        let schema3URL = root.appendingPathComponent("planned.cue", isDirectory: true)
        try writePlan(plan, to: schema3URL)
        var schema3 = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: schema3URL)
        check(schema3.writeCapability == .writableSchema3 && schema3.document?.items.count == 1, "verified schema-3 plan reopens through the public inventory owner")
        check(schema3.workspaceID == legacyInspection.workspaceID && schema3.title == legacyInspection.title && schema3.document?.sections == legacyInspection.document?.sections && schema3.document?.items == legacyInspection.document?.items && schema3.tombstones == legacyInspection.tombstones, "verified migration plan preserves the complete workspace, section, item, body, and tombstone closure")
        let migratedDeletedAt = ISO8601DateFormatter().date(from: "2020-01-01T00:00:00Z")!
        check(schema3.conflicts == [.legacyDeleteEdit(itemID: source.items[0].id, recordRevision: schema3.itemRecords[0].revision, deletedAt: migratedDeletedAt)], "migrated legacyUnbound tombstone retains the exact typed conflict evidence")

        let stableManifest = try Data(contentsOf: schema3URL.appendingPathComponent("manifest.yaml"))
        let secondID = UUID()
        var secondItem = source.items[0]
        secondItem.id = secondID
        secondItem.body = "Directory member"
        secondItem.contentHash = ContentHasher.hash(secondItem.body)
        let secondPath = schema3URL.appendingPathComponent("items/2023/11/\(secondID.uuidString.lowercased()).cue.md")
        try CueItemRecordCodec.encode(CueItemRecord(workspaceID: source.id, item: secondItem)).write(to: secondPath)
        schema3 = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: schema3URL)
        let unchangedManifest = try Data(contentsOf: schema3URL.appendingPathComponent("manifest.yaml"))
        check(schema3.itemRecords.count == 2 && unchangedManifest == stableManifest, "schema-3 item membership derives from the directory while manifest bytes stay unchanged")
        try fileManager.removeItem(at: secondPath)
        let afterDirectoryRemoval = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: schema3URL)
        let removalManifest = try Data(contentsOf: schema3URL.appendingPathComponent("manifest.yaml"))
        check(afterDirectoryRemoval.itemRecords.count == 1 && removalManifest == stableManifest, "schema-3 directory removal updates membership without changing manifest bytes")

        let currentItemURL = try itemFile(in: schema3URL, suffix: ".cue.md")
        let currentInspection = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: schema3URL)
        let current = currentInspection.itemRecords[0]
        let originalMTime = Date(timeIntervalSince1970: 1_800_000_000)
        try fileManager.setAttributes([.modificationDate: originalMTime], ofItemAtPath: currentItemURL.path)
        let beforeMTimeOnly = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: schema3URL)
        try fileManager.setAttributes([.modificationDate: originalMTime.addingTimeInterval(100)], ofItemAtPath: currentItemURL.path)
        let afterMTimeOnly = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: schema3URL)
        check(beforeMTimeOnly.itemRecords[0].revision == afterMTimeOnly.itemRecords[0].revision && beforeMTimeOnly.packageRevision == afterMTimeOnly.packageRevision, "exact revisions exclude mtime")

        var caseEdit = current.record
        caseEdit.item.body = "case fold\r\nNUL:\0\ndecomposed: e\u{0301}\nno final newline"
        check(ContentHasher.hash(caseEdit.item.body) == ContentHasher.hash(current.record.item.body), "revision counterexample keeps the normalized content hash equal")
        let changedBytes = try CueItemRecordCodec.encode(caseEdit)
        check(changedBytes.count == current.data.count, "revision counterexample keeps record size equal")
        try changedBytes.write(to: currentItemURL)
        let changedInspection = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: schema3URL)
        let changed = changedInspection.itemRecords[0]
        check(changed.revision != current.revision, "record revision hashes exact complete cue.md bytes")
        check(changedInspection.packageRevision != currentInspection.packageRevision, "package revision changes for an equal-size equal-ContentHasher record byte edit")

        let observedTombstone = """
        {"cue_schema":3,"cue_workspace_id":"\(source.id.uuidString)","item_id":"\(source.items[0].id.uuidString)","kind":"observed","observed_revision":"\(current.revision.rawValue)"}
        """
        try Data(observedTombstone.utf8).write(to: tombstoneURLFor(schema3URL, itemID: source.items[0].id))
        let divergent = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: schema3URL)
        check(divergent.document?.items.count == 1 && divergent.tombstones.count == 1, "divergent edit/delete retains both record and tombstone")
        check(divergent.conflicts == [.editDelete(itemID: source.items[0].id, recordRevision: changed.revision, observedRevision: current.revision)], "divergent edit/delete exposes both exact revisions in a typed conflict")

        try current.data.write(to: currentItemURL)
        let equalDelete = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: schema3URL)
        check(equalDelete.document?.items.isEmpty == true && equalDelete.itemRecords.count == 1 && equalDelete.conflicts.isEmpty, "equal observed tombstone suppresses the matching record without losing raw evidence")

        let earlyLegacy = """
        {"cue_schema":3,"cue_workspace_id":"\(source.id.uuidString)","item_id":"\(source.items[0].id.uuidString)","kind":"legacy_unbound","deleted_at":"1999-01-01T00:00:00Z"}
        """
        try Data(earlyLegacy.utf8).write(to: tombstoneURLFor(schema3URL, itemID: source.items[0].id))
        let early = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: schema3URL)
        let lateLegacy = earlyLegacy.replacingOccurrences(of: "1999-01-01", with: "2099-01-01")
        try Data(lateLegacy.utf8).write(to: tombstoneURLFor(schema3URL, itemID: source.items[0].id))
        let late = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: schema3URL)
        let dateFormatter = ISO8601DateFormatter()
        let earlyDate = dateFormatter.date(from: "1999-01-01T00:00:00Z")!
        let lateDate = dateFormatter.date(from: "2099-01-01T00:00:00Z")!
        check(early.conflicts == [.legacyDeleteEdit(itemID: source.items[0].id, recordRevision: early.itemRecords[0].revision, deletedAt: earlyDate)], "early legacyUnbound exposes an exact typed conflict without dominance")
        check(late.conflicts == [.legacyDeleteEdit(itemID: source.items[0].id, recordRevision: late.itemRecords[0].revision, deletedAt: lateDate)], "late legacyUnbound exposes an exact typed conflict without dominance")

        try fileManager.removeItem(at: currentItemURL)
        let legacyWithoutRecord = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: schema3URL)
        check(legacyWithoutRecord.document?.items.isEmpty == true && legacyWithoutRecord.tombstones.count == 1 && legacyWithoutRecord.conflicts.isEmpty, "legacyUnbound without a record remains audit evidence without inventing a conflict")
        try Data(observedTombstone.utf8).write(to: tombstoneURLFor(schema3URL, itemID: source.items[0].id))
        let deleted = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: schema3URL)
        check(deleted.document?.items.isEmpty == true && deleted.conflicts.isEmpty, "observed tombstone without a record is a clean deletion")

        let newer = try copyPackage(schema3URL, named: "newer")
        try rewriteManifest(at: newer) { $0["cue_schema"] = 4 }
        check(try CuePackagePlanner.inspect(atCoordinatedAccessorURL: newer).writeCapability == .readOnly(.newerSchema(4)), "newer schema is a typed read-only capability")
        let feature = try copyPackage(schema3URL, named: "feature")
        try rewriteManifest(at: feature) { $0["required_features"] = ["future_assets"] }
        check(try CuePackagePlanner.inspect(atCoordinatedAccessorURL: feature).writeCapability == .readOnly(.unsupportedRequiredFeatures(["future_assets"])), "unsupported required feature is a typed read-only capability")

        let extraManifest = try copyPackage(schema3URL, named: "extra-manifest")
        try rewriteManifest(at: extraManifest) { $0["items"] = [] }
        expectInvalid(extraManifest, "schema-3 manifest rejects membership and every fifth key")
        let duplicateFeatures = try copyPackage(schema3URL, named: "duplicate-features")
        try rewriteManifest(at: duplicateFeatures) { $0["required_features"] = ["known", "known"] }
        expectInvalid(duplicateFeatures, "schema-3 manifest rejects duplicate required features")

        let unlistedURL = try copyPackage(schema2URL, named: "unlisted")
        var unlistedItem = source.items[0]
        unlistedItem.id = UUID()
        let unlistedPath = unlistedURL.appendingPathComponent("items/2023/11/\(unlistedItem.id.uuidString.lowercased()).md")
        let listedLegacyData = try Data(contentsOf: itemFile(in: unlistedURL, suffix: ".md"))
        let unlistedData = String(data: listedLegacyData, encoding: .utf8)!
            .replacingOccurrences(of: source.items[0].id.uuidString, with: unlistedItem.id.uuidString)
        try Data(unlistedData.utf8).write(to: unlistedPath)
        let unlistedInspection = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: unlistedURL)
        check(unlistedInspection.document?.items.count == 1 && unlistedInspection.unlistedManagedPaths.count == 1, "schema-2 open keeps manifest membership authoritative")
        check(unlistedInspection.writeCapability == .readOnly(.unlistedLegacyManagedRecords(unlistedInspection.unlistedManagedPaths)), "unlisted schema-2 managed records are a typed read-only reason")
        do {
            _ = try CuePackagePlanner.planSchema3Migration(from: unlistedInspection)
            check(false, "unlisted schema-2 managed record blocks migration")
        } catch WorkspaceStoreError.invalidDocument {
            check(true, "unlisted schema-2 managed record blocks migration")
        }

        check(CueRecordRevision(rawValue: String(repeating: "a", count: 64)) != nil && CueRecordRevision(rawValue: String(repeating: "A", count: 64)) == nil, "record revisions accept only lowercase ASCII SHA-256")
        check(CuePackageRevision(rawValue: String(repeating: "1", count: 64)) != nil && CuePackageRevision(rawValue: String(repeating: "１", count: 64)) == nil, "package revisions reject non-ASCII digits")

        let pureURL = try copyPackage(schema2URL, named: "pure-plan-source")
        let pureInspection = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: pureURL)
        try rewriteManifest(at: pureURL) { $0["title"] = "Changed after inspection" }
        let purePlan = try CuePackagePlanner.planSchema3Migration(from: pureInspection)
        let pureManifestData = purePlan.files.first(where: { $0.path == "manifest.yaml" })!.data
        let pureManifest = try JSONSerialization.jsonObject(with: pureManifestData) as! [String: Any]
        check(pureManifest["title"] as? String == source.title, "migration planning is pure over the retained one-read inspection")

        let unknownManifestURL = try copyPackage(schema2URL, named: "unknown-legacy-manifest")
        try rewriteManifest(at: unknownManifestURL) { $0["future_manifest"] = ["keep": true] }
        let unknownManifestInspection = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: unknownManifestURL)
        check(unknownManifestInspection.writeCapability == .readOnly(.unknownLegacyManifestMetadata(["future_manifest"])), "unknown schema-2 manifest metadata is a typed read-only reason")
        do {
            _ = try CuePackagePlanner.planSchema3Migration(from: unknownManifestInspection)
            check(false, "unknown schema-2 manifest metadata blocks migration")
        } catch WorkspaceStoreError.invalidDocument {
            check(true, "unknown schema-2 manifest metadata blocks migration")
        }

        let collisionURL = try copyPackage(schema2URL, named: "legacy-item-collision")
        let collisionItemURL = try itemFile(in: collisionURL, suffix: ".md")
        var collisionText = try String(contentsOf: collisionItemURL, encoding: .utf8)
        let collisionMetadataEnd = collisionText.range(of: " -->\n")!.lowerBound
        collisionText.insert(
            contentsOf: #", "\u0073chema" : "future", "workspace_id" : "future""#,
            at: collisionText.index(before: collisionMetadataEnd)
        )
        try Data(collisionText.utf8).write(to: collisionItemURL)
        let collisionInspection = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: collisionURL)
        let resolvedCollisionURL = collisionURL.resolvingSymlinksInPath()
        let resolvedCollisionItemURL = collisionItemURL.resolvingSymlinksInPath()
        let collisionPath = String(resolvedCollisionItemURL.path.dropFirst(resolvedCollisionURL.path.count + 1))
        var collisionKeys: [String] = []
        if case let .readOnly(.unpreservableLegacyItemMetadata(keys)) = collisionInspection.writeCapability {
            collisionKeys = keys
        }
        check(
            collisionKeys.count == 2 &&
                collisionKeys.allSatisfy { $0.hasPrefix("\(collisionPath)#") } &&
                collisionKeys.contains(where: { $0.hasSuffix("#schema") }) &&
                collisionKeys.contains(where: { $0.hasSuffix("#workspace_id") }),
            "escaped and plain legacy item key collisions are a typed read-only reason"
        )
        do {
            _ = try CuePackagePlanner.planSchema3Migration(from: collisionInspection)
            check(false, "unpreservable legacy item metadata blocks migration during inspection")
        } catch WorkspaceStoreError.invalidDocument {
            check(true, "unpreservable legacy item metadata blocks migration during inspection")
        }

        let legacyAssetURL = try copyPackage(schema2URL, named: "legacy-assets")
        let legacyAsset = legacyAssetURL.appendingPathComponent("assets/sha256/\(String(repeating: "a", count: 64))")
        try Data("reserved".utf8).write(to: legacyAsset)
        let legacyAssetInspection = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: legacyAssetURL)
        check(legacyAssetInspection.writeCapability == .readOnly(.nonemptyAssets(["assets/sha256/\(String(repeating: "a", count: 64))"])), "nonempty schema-2 assets are typed read-only before T-007")
        do {
            _ = try CuePackagePlanner.planSchema3Migration(from: legacyAssetInspection)
            check(false, "B2 never copies nonempty legacy assets into a plan")
        } catch WorkspaceStoreError.invalidDocument {
            check(true, "B2 never copies nonempty legacy assets into a plan")
        }

        let validationBase = root.appendingPathComponent("validation-base.cue", isDirectory: true)
        try writePlan(plan, to: validationBase)

        let malformedManifest = try copyPackage(validationBase, named: "malformed-manifest")
        try rewriteManifest(at: malformedManifest) { $0["title"] = 3 }
        expectInvalid(malformedManifest, "malformed manifest stays typed invalidDocument")
        let malformedSection = try copyPackage(validationBase, named: "malformed-section")
        let malformedSectionURL = malformedSection.appendingPathComponent(
            "sections/\(source.sections[0].id.uuidString.lowercased()).yaml"
        )
        try rewriteJSONObject(at: malformedSectionURL) { $0["title"] = 3 }
        expectInvalid(malformedSection, "malformed section stays typed invalidDocument")
        let malformedTombstone = try copyPackage(validationBase, named: "malformed-tombstone")
        try rewriteJSONObject(at: tombstoneURLFor(malformedTombstone, itemID: source.items[0].id)) {
            $0["kind"] = 3
        }
        expectInvalid(malformedTombstone, "malformed tombstone stays typed invalidDocument")

        let missingPackage = root.appendingPathComponent("missing.cue", isDirectory: true)
        do {
            _ = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: missingPackage)
            check(false, "missing package root stays typed missingFile")
        } catch WorkspaceStoreError.missingFile {
            check(true, "missing package root stays typed missingFile")
        } catch {
            check(false, "missing package root stays typed missingFile (unexpected error: \(error))")
        }

        do {
            let unreadablePackage = try copyPackage(validationBase, named: "unreadable-items")
            let unreadableItems = unreadablePackage.appendingPathComponent("items", isDirectory: true)
            let originalPermissions = try fileManager.attributesOfItem(atPath: unreadableItems.path)[.posixPermissions]!
            try fileManager.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadableItems.path)
            defer {
                do {
                    try fileManager.setAttributes(
                        [.posixPermissions: originalPermissions],
                        ofItemAtPath: unreadableItems.path
                    )
                    try fileManager.removeItem(at: unreadablePackage)
                } catch {
                    failed += 1
                    print("FAIL  filesystem permission fixture cleanup: \(error)")
                }
            }
            do {
                _ = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: unreadablePackage)
                check(false, "filesystem read permission failure preserves its Cocoa error")
            } catch WorkspaceStoreError.invalidDocument {
                check(false, "filesystem read permission failure is not mislabeled invalidDocument")
            } catch let error as CocoaError {
                check(
                    error.code == .fileReadNoPermission,
                    "filesystem read permission failure preserves its Cocoa error"
                )
            } catch {
                check(false, "filesystem read permission failure preserves its Cocoa error (unexpected error: \(error))")
            }
        }

        let validationManifest = try Data(contentsOf: validationBase.appendingPathComponent("manifest.yaml"))
        let addedSectionID = UUID()
        let addedSectionURL = validationBase.appendingPathComponent("sections/\(addedSectionID.uuidString.lowercased()).yaml")
        let addedSection = """
        {"schema":3,"workspace_id":"\(source.id.uuidString)","id":"\(addedSectionID.uuidString)","title":"Added","order":2,"is_collapsed":false}
        """
        try Data(addedSection.utf8).write(to: addedSectionURL)
        let withSection = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: validationBase)
        let sectionManifest = try Data(contentsOf: validationBase.appendingPathComponent("manifest.yaml"))
        check(withSection.document?.sections.count == 2 && sectionManifest == validationManifest, "schema-3 section membership derives from the directory while manifest bytes stay unchanged")
        try fileManager.removeItem(at: addedSectionURL)

        let assetRevisionURL = try copyPackage(validationBase, named: "asset-path-revision")
        let firstAssetURL = assetRevisionURL.appendingPathComponent("assets/sha256/\(String(repeating: "a", count: 64))")
        let secondAssetURL = assetRevisionURL.appendingPathComponent("assets/sha256/\(String(repeating: "b", count: 64))")
        try Data("same bytes".utf8).write(to: firstAssetURL)
        let firstAssetInspection = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: assetRevisionURL)
        try fileManager.moveItem(at: firstAssetURL, to: secondAssetURL)
        let secondAssetInspection = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: assetRevisionURL)
        check(firstAssetInspection.packageRevision != secondAssetInspection.packageRevision, "package revision binds canonical relative paths as well as bytes")
        check(firstAssetInspection.writeCapability == .readOnly(.nonemptyAssets(["assets/sha256/\(String(repeating: "a", count: 64))"])), "nonempty schema-3 assets stay typed read-only in B2")

        let badFeatureLexeme = try copyPackage(validationBase, named: "bad-feature-lexeme")
        try rewriteManifest(at: badFeatureLexeme) { $0["required_features"] = ["ｆｕｔｕｒｅ"] }
        expectInvalid(badFeatureLexeme, "required feature names reject non-ASCII letters")
        let badDateLexeme = try copyPackage(validationBase, named: "bad-date-lexeme")
        let badDateTombstone = tombstoneURLFor(badDateLexeme, itemID: source.items[0].id)
        try rewriteJSONObject(at: badDateTombstone) { $0["deleted_at"] = "２０２０-01-01T00:00:00Z" }
        expectInvalid(badDateLexeme, "tombstone dates reject non-ASCII year digits")
        let uppercaseAssetHash = try copyPackage(validationBase, named: "uppercase-asset-hash")
        try Data("x".utf8).write(to: uppercaseAssetHash.appendingPathComponent("assets/sha256/\(String(repeating: "A", count: 64))"))
        expectInvalid(uppercaseAssetHash, "asset paths reject uppercase SHA-256 lexemes")
        let nonASCIIAssetHash = try copyPackage(validationBase, named: "non-ascii-asset-hash")
        try Data("x".utf8).write(to: nonASCIIAssetHash.appendingPathComponent("assets/sha256/\(String(repeating: "１", count: 64))"))
        expectInvalid(nonASCIIAssetHash, "asset paths reject non-ASCII SHA-256 lexemes")

        let badSectionSchema = try copyPackage(validationBase, named: "bad-section-schema")
        let badSectionSchemaURL = badSectionSchema.appendingPathComponent("sections/\(source.sections[0].id.uuidString.lowercased()).yaml")
        try rewriteJSONObject(at: badSectionSchemaURL) { $0["schema"] = 4 }
        expectInvalid(badSectionSchema, "schema-3 section rejects unsupported schema")
        let badSectionWorkspace = try copyPackage(validationBase, named: "bad-section-workspace")
        let badSectionWorkspaceURL = badSectionWorkspace.appendingPathComponent("sections/\(source.sections[0].id.uuidString.lowercased()).yaml")
        try rewriteJSONObject(at: badSectionWorkspaceURL) { $0["workspace_id"] = UUID().uuidString }
        expectInvalid(badSectionWorkspace, "schema-3 section rejects workspace mismatch")
        let badSectionID = try copyPackage(validationBase, named: "bad-section-id")
        let badSectionIDURL = badSectionID.appendingPathComponent("sections/\(source.sections[0].id.uuidString.lowercased()).yaml")
        try rewriteJSONObject(at: badSectionIDURL) { $0["id"] = UUID().uuidString }
        expectInvalid(badSectionID, "schema-3 section rejects filename and record ID mismatch")
        let duplicateSectionWorkspace = try copyPackage(validationBase, named: "duplicate-section-workspace")
        let duplicateSectionWorkspaceURL = duplicateSectionWorkspace.appendingPathComponent("sections/\(source.sections[0].id.uuidString.lowercased()).yaml")
        try prependJSONMember(#""\u0077orkspace_id":"\#(source.id.uuidString)""#, at: duplicateSectionWorkspaceURL)
        expectInvalid(duplicateSectionWorkspace, "schema-3 section rejects escaped duplicate workspace identity")
        let duplicateLegacySectionID = try copyPackage(schema2URL, named: "duplicate-legacy-section-id")
        let duplicateLegacySectionURL = duplicateLegacySectionID.appendingPathComponent("sections/\(source.sections[0].id.uuidString.lowercased()).yaml")
        try prependJSONMember(#""\u0069d":"\#(source.sections[0].id.uuidString)""#, at: duplicateLegacySectionURL)
        expectInvalid(duplicateLegacySectionID, "schema-2 section rejects escaped duplicate record identity")

        let badItemID = try copyPackage(validationBase, named: "bad-item-id")
        let badItemIDURL = try itemFile(in: badItemID, suffix: ".cue.md")
        let renamedItemURL = badItemIDURL.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString.lowercased()).cue.md")
        try fileManager.moveItem(at: badItemIDURL, to: renamedItemURL)
        expectInvalid(badItemID, "schema-3 item rejects filename and record ID mismatch")

        let badItemDate = try copyPackage(validationBase, named: "bad-item-date")
        let badItemDateURL = try itemFile(in: badItemDate, suffix: ".cue.md")
        let wrongMonth = badItemDate.appendingPathComponent("items/2023/12", isDirectory: true)
        try fileManager.createDirectory(at: wrongMonth, withIntermediateDirectories: true)
        try fileManager.moveItem(at: badItemDateURL, to: wrongMonth.appendingPathComponent(badItemDateURL.lastPathComponent))
        expectInvalid(badItemDate, "schema-3 item rejects UTC created_at path mismatch")

        let badItemWorkspace = try copyPackage(validationBase, named: "bad-item-workspace")
        let badItemWorkspaceURL = try itemFile(in: badItemWorkspace, suffix: ".cue.md")
        var workspaceRecord = try CueItemRecordCodec.decode(Data(contentsOf: badItemWorkspaceURL))
        workspaceRecord.workspaceID = UUID()
        try CueItemRecordCodec.encode(workspaceRecord).write(to: badItemWorkspaceURL)
        expectInvalid(badItemWorkspace, "schema-3 item rejects workspace mismatch")

        let badSectionReference = try copyPackage(validationBase, named: "bad-section-reference")
        let badSectionReferenceURL = try itemFile(in: badSectionReference, suffix: ".cue.md")
        var missingSectionRecord = try CueItemRecordCodec.decode(Data(contentsOf: badSectionReferenceURL))
        missingSectionRecord.item.sectionID = UUID()
        try CueItemRecordCodec.encode(missingSectionRecord).write(to: badSectionReferenceURL)
        expectInvalid(badSectionReference, "schema-3 item rejects nonexistent section reference")

        let duplicateItem = try copyPackage(validationBase, named: "duplicate-item")
        let duplicateSourceURL = try itemFile(in: duplicateItem, suffix: ".cue.md")
        var duplicateRecord = try CueItemRecordCodec.decode(Data(contentsOf: duplicateSourceURL))
        duplicateRecord.item.createdAt = ISO8601DateFormatter().date(from: "2024-12-01T00:00:00Z")!
        let duplicateURL = duplicateItem.appendingPathComponent("items/2024/12/\(duplicateRecord.item.id.uuidString.lowercased()).cue.md")
        try fileManager.createDirectory(at: duplicateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try CueItemRecordCodec.encode(duplicateRecord).write(to: duplicateURL)
        expectInvalid(duplicateItem, "schema-3 inventory rejects duplicate item IDs across individually valid UTC paths")

        let badTombstoneWorkspace = try copyPackage(validationBase, named: "bad-tombstone-workspace")
        let badTombstoneWorkspaceURL = tombstoneURLFor(badTombstoneWorkspace, itemID: source.items[0].id)
        try rewriteJSONObject(at: badTombstoneWorkspaceURL) { $0["cue_workspace_id"] = UUID().uuidString }
        expectInvalid(badTombstoneWorkspace, "schema-3 tombstone rejects workspace mismatch")
        let badTombstoneID = try copyPackage(validationBase, named: "bad-tombstone-id")
        let badTombstoneIDURL = tombstoneURLFor(badTombstoneID, itemID: source.items[0].id)
        try fileManager.moveItem(
            at: badTombstoneIDURL,
            to: badTombstoneIDURL.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString.lowercased()).json")
        )
        expectInvalid(badTombstoneID, "schema-3 tombstone rejects filename and record ID mismatch")

        let rootTarget = try copyPackage(validationBase, named: "root-link-target")
        let rootLink = root.appendingPathComponent("root-link.cue", isDirectory: true)
        try fileManager.createSymbolicLink(atPath: rootLink.path, withDestinationPath: rootTarget.path)
        expectInvalid(rootLink, "package root symbolic link is rejected")

        let manifestLink = try copyPackage(validationBase, named: "manifest-link")
        let manifestLinkURL = manifestLink.appendingPathComponent("manifest.yaml")
        let manifestTarget = root.appendingPathComponent("manifest-link-target.json")
        try fileManager.moveItem(at: manifestLinkURL, to: manifestTarget)
        try fileManager.createSymbolicLink(atPath: manifestLinkURL.path, withDestinationPath: manifestTarget.path)
        expectInvalid(manifestLink, "manifest symbolic link is rejected")

        for controlled in ["sections", "items", "tombstones", "assets"] {
            let package = try copyPackage(validationBase, named: "\(controlled)-link")
            let controlledURL = package.appendingPathComponent(controlled, isDirectory: true)
            let target = root.appendingPathComponent("\(controlled)-link-target", isDirectory: true)
            try fileManager.moveItem(at: controlledURL, to: target)
            try fileManager.createSymbolicLink(atPath: controlledURL.path, withDestinationPath: target.path)
            expectInvalid(package, "controlled \(controlled) directory symbolic link is rejected")
        }

        let yearLink = try copyPackage(validationBase, named: "year-link")
        let yearURL = yearLink.appendingPathComponent("items/2023", isDirectory: true)
        let yearTarget = root.appendingPathComponent("year-link-target", isDirectory: true)
        try fileManager.moveItem(at: yearURL, to: yearTarget)
        try fileManager.createSymbolicLink(atPath: yearURL.path, withDestinationPath: yearTarget.path)
        expectInvalid(yearLink, "item intermediate directory symbolic link is rejected")

        let itemLink = try copyPackage(validationBase, named: "item-link")
        let itemLinkURL = try itemFile(in: itemLink, suffix: ".cue.md")
        let itemTarget = root.appendingPathComponent("item-link-target.cue.md")
        try fileManager.moveItem(at: itemLinkURL, to: itemTarget)
        try fileManager.createSymbolicLink(atPath: itemLinkURL.path, withDestinationPath: itemTarget.path)
        expectInvalid(itemLink, "item record symbolic link is rejected")

        let sectionLink = try copyPackage(validationBase, named: "section-link")
        let sectionLinkURL = sectionLink.appendingPathComponent("sections/\(source.sections[0].id.uuidString.lowercased()).yaml")
        let sectionTarget = root.appendingPathComponent("section-link-target.yaml")
        try fileManager.moveItem(at: sectionLinkURL, to: sectionTarget)
        try fileManager.createSymbolicLink(atPath: sectionLinkURL.path, withDestinationPath: sectionTarget.path)
        expectInvalid(sectionLink, "section record symbolic link is rejected")

        let tombstoneLink = try copyPackage(validationBase, named: "tombstone-link")
        let tombstoneLinkURL = tombstoneURLFor(tombstoneLink, itemID: source.items[0].id)
        let tombstoneTarget = root.appendingPathComponent("tombstone-link-target.json")
        try fileManager.moveItem(at: tombstoneLinkURL, to: tombstoneTarget)
        try fileManager.createSymbolicLink(atPath: tombstoneLinkURL.path, withDestinationPath: tombstoneTarget.path)
        expectInvalid(tombstoneLink, "tombstone record symbolic link is rejected")

        let danglingLink = try copyPackage(validationBase, named: "dangling-link")
        let danglingURL = danglingLink.appendingPathComponent("sections/ignored.txt")
        try fileManager.createSymbolicLink(atPath: danglingURL.path, withDestinationPath: root.appendingPathComponent("missing-target").path)
        expectInvalid(danglingLink, "dangling wrong-extension symbolic link is rejected before filtering")

        let rootFile = root.appendingPathComponent("root-file.cue")
        try Data("not a package".utf8).write(to: rootFile)
        expectInvalid(rootFile, "regular file cannot substitute for a package root")
        let manifestDirectory = try copyPackage(validationBase, named: "manifest-directory")
        try fileManager.removeItem(at: manifestDirectory.appendingPathComponent("manifest.yaml"))
        try fileManager.createDirectory(at: manifestDirectory.appendingPathComponent("manifest.yaml"), withIntermediateDirectories: false)
        expectInvalid(manifestDirectory, "manifest directory cannot substitute for a regular file")
        let sectionsFile = try copyPackage(validationBase, named: "sections-file")
        try fileManager.removeItem(at: sectionsFile.appendingPathComponent("sections"))
        try Data("not a directory".utf8).write(to: sectionsFile.appendingPathComponent("sections"))
        expectInvalid(sectionsFile, "controlled directory rejects regular-file substitution")
        let itemDirectory = try copyPackage(validationBase, named: "item-directory")
        let itemDirectoryURL = try itemFile(in: itemDirectory, suffix: ".cue.md")
        try fileManager.removeItem(at: itemDirectoryURL)
        try fileManager.createDirectory(at: itemDirectoryURL, withIntermediateDirectories: false)
        expectInvalid(itemDirectory, "item record rejects directory substitution")

        let sectionDepth = try copyPackage(validationBase, named: "section-depth")
        let nestedSectionURL = sectionDepth.appendingPathComponent("sections/nested/\(UUID().uuidString.lowercased()).yaml")
        try fileManager.createDirectory(at: nestedSectionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: nestedSectionURL)
        expectInvalid(sectionDepth, "section inventory rejects unexpected depth")
        let shallowItem = try copyPackage(validationBase, named: "shallow-item")
        try Data("x".utf8).write(to: shallowItem.appendingPathComponent("items/\(UUID().uuidString.lowercased()).cue.md"))
        expectInvalid(shallowItem, "item inventory rejects shallow paths")
        let deepTombstone = try copyPackage(validationBase, named: "deep-tombstone")
        let deepTombstoneURL = deepTombstone.appendingPathComponent("tombstones/nested/\(UUID().uuidString.lowercased()).json")
        try fileManager.createDirectory(at: deepTombstoneURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: deepTombstoneURL)
        expectInvalid(deepTombstone, "tombstone inventory rejects unexpected depth")
        let wrongExtension = try copyPackage(validationBase, named: "wrong-extension")
        try Data("{}".utf8).write(to: wrongExtension.appendingPathComponent("sections/\(UUID().uuidString.lowercased()).json"))
        expectInvalid(wrongExtension, "section inventory rejects wrong extensions")
        let unexpectedRoot = try copyPackage(validationBase, named: "unexpected-root")
        try Data("x".utf8).write(to: unexpectedRoot.appendingPathComponent("other.txt"))
        expectInvalid(unexpectedRoot, "package inventory rejects unexpected root entries")

        let badYear = try copyPackage(validationBase, named: "bad-year")
        let badYearItem = try itemFile(in: badYear, suffix: ".cue.md")
        let nonASCIIYear = badYear.appendingPathComponent("items/２０２３/11", isDirectory: true)
        try fileManager.createDirectory(at: nonASCIIYear, withIntermediateDirectories: true)
        try fileManager.moveItem(at: badYearItem, to: nonASCIIYear.appendingPathComponent(badYearItem.lastPathComponent))
        expectInvalid(badYear, "item inventory rejects non-ASCII UTC year digits")
        let badMonth = try copyPackage(validationBase, named: "bad-month")
        let badMonthItem = try itemFile(in: badMonth, suffix: ".cue.md")
        let month13 = badMonth.appendingPathComponent("items/2023/13", isDirectory: true)
        try fileManager.createDirectory(at: month13, withIntermediateDirectories: true)
        try fileManager.moveItem(at: badMonthItem, to: month13.appendingPathComponent(badMonthItem.lastPathComponent))
        expectInvalid(badMonth, "item inventory rejects out-of-range UTC month")
        let bracedID = try copyPackage(validationBase, named: "braced-id")
        let bracedItem = try itemFile(in: bracedID, suffix: ".cue.md")
        try fileManager.moveItem(
            at: bracedItem,
            to: bracedItem.deletingLastPathComponent().appendingPathComponent("{\(source.items[0].id.uuidString.lowercased())}.cue.md")
        )
        expectInvalid(bracedID, "item inventory rejects noncanonical UUID filenames")

        let unsafeLegacy = try copyPackage(schema2URL, named: "unsafe-legacy-path")
        try rewriteManifest(at: unsafeLegacy) {
            var items = $0["items"] as! [String]
            items.append("../escape.md")
            $0["items"] = items
        }
        expectInvalid(unsafeLegacy, "schema-2 manifest rejects escaping relative paths")
        let duplicateLegacyPath = try copyPackage(schema2URL, named: "duplicate-legacy-path")
        try rewriteManifest(at: duplicateLegacyPath) {
            var items = $0["items"] as! [String]
            items.append(items[0])
            $0["items"] = items
        }
        expectInvalid(duplicateLegacyPath, "schema-2 manifest rejects duplicate membership paths")
    } catch {
        failed += 1
        print("FAIL  package planning setup: \(error)")
    }
}

private func tombstoneURLFor(_ package: URL, itemID: UUID) -> URL {
    package.appendingPathComponent("tombstones/\(itemID.uuidString.lowercased()).json")
}

private func checkStorage() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CueCoreChecks-\(UUID())", isDirectory: true)
    let url = directory.appendingPathComponent("workspace.cue", isDirectory: true)
    let store = WorkspaceStore()
    var document = sampleDocument()

    do {
        let fingerprint = try store.create(document: document, at: url)
        check(FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.yaml").path), "package writes a readable manifest")
        let freshManifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url.appendingPathComponent("manifest.yaml"))
        ) as! [String: Any]
        check(
            Set(freshManifest.keys) == Set(["cue_schema", "cue_workspace_id", "title", "required_features"]),
            "fresh WorkspaceStore creation writes a membership-free schema-3 manifest"
        )
        let sectionURL = url.appendingPathComponent("sections/\(document.sections[0].id.uuidString.lowercased()).yaml")
        check(FileManager.default.fileExists(atPath: sectionURL.path), "package writes one section record per section")
        let itemURL = try FileManager.default.contentsOfDirectory(
            at: url.appendingPathComponent("items", isDirectory: true),
            includingPropertiesForKeys: nil
        ).flatMap { year in
            (try? FileManager.default.contentsOfDirectory(at: year, includingPropertiesForKeys: nil)) ?? []
        }.flatMap { month in
            (try? FileManager.default.contentsOfDirectory(at: month, includingPropertiesForKeys: nil)) ?? []
        }.first { $0.lastPathComponent == "\(document.items[0].id.uuidString.lowercased()).cue.md" }!
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
    let backupStore = WorkspaceStore()
    let searchIndexStore = WorkspaceSearchIndexStore(directoryURL: backupDirectory.appendingPathComponent("Cache", isDirectory: true))
    do {
        var backupDocument = sampleDocument()
        let removedID = backupDocument.items[0].id
        let initial = try backupStore.create(document: backupDocument, at: backupURL)
        let removedItemURL = try FileManager.default.contentsOfDirectory(
            at: backupURL.appendingPathComponent("items", isDirectory: true),
            includingPropertiesForKeys: nil
        ).flatMap { year in
            (try? FileManager.default.contentsOfDirectory(at: year, includingPropertiesForKeys: nil)) ?? []
        }.flatMap { month in
            (try? FileManager.default.contentsOfDirectory(at: month, includingPropertiesForKeys: nil)) ?? []
        }.first { $0.lastPathComponent == "\(removedID.uuidString.lowercased()).cue.md" }!
        try searchIndexStore.rebuild(for: backupDocument)
        check(FileManager.default.fileExists(atPath: searchIndexStore.url(for: backupDocument.id).path), "search cache is rebuildable from package truth")

        backupDocument.items.append(WorkItem(body: "Next prompt", kind: .prompt, sectionID: backupDocument.inbox.id, contentHash: ContentHasher.hash("Next prompt"), order: 1))
        let secondFingerprint = try backupStore.write(document: backupDocument, to: backupURL, expectedFingerprint: initial)
        let backups = try FileManager.default.contentsOfDirectory(at: backupDirectory.appendingPathComponent(".cue-backups"), includingPropertiesForKeys: nil)
        check(backups.filter { $0.pathExtension == "cue" }.count == 1, "write creates a timestamped package backup")
        check(try backupStore.load(from: backupURL).0.items.contains(where: { $0.body == "Next prompt" }), "post-write package remains parseable")

        backupDocument.items.removeAll { $0.id == removedID }
        _ = try backupStore.write(document: backupDocument, to: backupURL, expectedFingerprint: secondFingerprint)
        let tombstoneURL = backupURL.appendingPathComponent("tombstones/\(removedID.uuidString.lowercased()).json")
        check(FileManager.default.fileExists(atPath: tombstoneURL.path), "physical item deletion writes a tombstone")
        check(!FileManager.default.fileExists(atPath: removedItemURL.path), "deleted item document leaves the active item tree")

        let legacyURL = backupDirectory.appendingPathComponent("Legacy Workspace.md")
        try Data(MarkdownWorkspaceCodec.encode(sampleDocument()).utf8).write(to: legacyURL)
        do {
            _ = try backupStore.load(from: legacyURL)
            check(false, "legacy single-file workspaces stay outside the runtime path")
        } catch WorkspaceStoreError.invalidDocument {
            check(true, "legacy single-file workspaces stay outside the runtime path")
        }
        let importedURL = backupDirectory.appendingPathComponent("Imported Workspace.cue", isDirectory: true)
        _ = try WorkspaceLegacyImporter(workspaceStore: backupStore).importWorkspace(from: legacyURL, to: importedURL)
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

private enum TransactionFixtureError: Error { case injected }

private final class ReplaceThenThrowFileManager: FileManager, @unchecked Sendable {
    override func replaceItemAt(
        _ originalItemURL: URL,
        withItemAt newItemURL: URL,
        backupItemName: String? = nil,
        options: FileManager.ItemReplacementOptions = []
    ) throws -> URL? {
        _ = try super.replaceItemAt(
            originalItemURL,
            withItemAt: newItemURL,
            backupItemName: backupItemName,
            options: options
        )
        let displacedURL = backupItemName.map {
            originalItemURL.deletingLastPathComponent().appendingPathComponent($0, isDirectory: true)
        }
        throw NSError(
            domain: "CueCoreChecks.ReplaceThenThrow",
            code: 1,
            userInfo: displacedURL.map { ["NSFileOriginalItemLocationKey": $0] } ?? [:]
        )
    }
}

private struct TransactionChild {
    var process: Process
    var input: Pipe
    var output: Pipe
    var error: Pipe
}

private func siblingPackages(
    of package: URL,
    containing token: String
) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
        at: package.deletingLastPathComponent(),
        includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.contains(token) }
}

private func archivedBackups(of package: URL) throws -> [URL] {
    let directory = package.deletingLastPathComponent().appendingPathComponent(".cue-backups")
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "cue" }
}

private func transactionChildIfRequested() -> Bool {
    let arguments = CommandLine.arguments
    guard arguments.dropFirst().first == "--transaction-child" else { return false }
    guard arguments.count == 6 else { exit(64) }
    let failpoint: WorkspaceTransactionFailpoint?
    if arguments[5] == "none" {
        failpoint = nil
    } else if let value = WorkspaceTransactionFailpoint(rawValue: arguments[5]) {
        failpoint = value
    } else {
        exit(64)
    }
    let package = URL(fileURLWithPath: arguments[2])
    let title = arguments[3]
    let expectedRevision = arguments[4]
    do {
        let store = WorkspaceStore { phase, _ in
            if phase == failpoint { abort() }
        }
        let snapshot = try store.loadSnapshot(from: package)
        guard snapshot.revision.rawValue == expectedRevision, var draft = snapshot.document else {
            exit(72)
        }
        FileHandle.standardOutput.write(Data("READY \(snapshot.revision.rawValue)\n".utf8))
        guard FileHandle.standardInput.readData(ofLength: 1) == Data([0x47]) else { exit(71) }
        draft.title = title
        _ = try store.commit(document: draft, basedOn: snapshot)
        FileHandle.standardOutput.write(Data("SUCCESS\n".utf8))
        exit(0)
    } catch WorkspaceStoreError.externalModification {
        FileHandle.standardOutput.write(Data("CONFLICT\n".utf8))
        exit(73)
    } catch {
        FileHandle.standardError.write(Data("ERROR \(error)\n".utf8))
        exit(74)
    }
}

private func launchTransactionChild(
    package: URL,
    title: String,
    revision: CuePackageRevision,
    failpoint: WorkspaceTransactionFailpoint?
) throws -> TransactionChild {
    let input = Pipe()
    let output = Pipe()
    let error = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = [
        "--transaction-child",
        package.path,
        title,
        revision.rawValue,
        failpoint?.rawValue ?? "none",
    ]
    process.standardInput = input
    process.standardOutput = output
    process.standardError = error
    try process.run()
    return TransactionChild(process: process, input: input, output: output, error: error)
}

private func release(_ child: TransactionChild) {
    child.input.fileHandleForWriting.write(Data([0x47]))
    try? child.input.fileHandleForWriting.close()
}

private func readyRevision(_ child: TransactionChild) -> String {
    var data = Data()
    while true {
        let byte = child.output.fileHandleForReading.readData(ofLength: 1)
        guard !byte.isEmpty else { return "" }
        data.append(byte)
        if byte.last == 0x0A { break }
    }
    let line = String(data: data, encoding: .utf8) ?? ""
    guard line.hasPrefix("READY ") else { return "" }
    return line.dropFirst("READY ".count).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func checkWorkspaceTransaction() {
    let fileManager = FileManager.default

    do {
        let root = fileManager.temporaryDirectory.appendingPathComponent("CueSchema2Commit-\(UUID())")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: root) }
        let package = root.appendingPathComponent("legacy.cue")
        var legacy = sampleDocument()
        legacy.items[0].body = "decomposed e\u{0301}\nexact body"
        legacy.items[0].contentHash = ContentHasher.hash(legacy.items[0].body)
        try writeSchema2Package(legacy, to: package)
        let beforeRevision = try CuePackagePlanner.inspect(atCoordinatedAccessorURL: package).packageRevision
        let beforeSiblings = try fileManager.contentsOfDirectory(atPath: root.path).sorted()
        let store = WorkspaceStore()
        let snapshot = try store.loadSnapshot(from: package)
        check(snapshot.writeCapability == .requiresVerifiedSchema2Migration, "coordinated schema-2 load exposes verified migration")
        check(
            try CuePackagePlanner.inspect(atCoordinatedAccessorURL: package).packageRevision == beforeRevision &&
                fileManager.contentsOfDirectory(atPath: root.path).sorted() == beforeSiblings,
            "coordinated schema-2 open is observational"
        )
        var draft = snapshot.document!
        draft.title = "Migrated once"
        let failingStore = WorkspaceStore { phase, _ in
            if phase == .afterStageValidated { throw TransactionFixtureError.injected }
        }
        do {
            _ = try failingStore.commit(document: draft, basedOn: snapshot)
            check(false, "failed schema-2 migration stops before publication")
        } catch TransactionFixtureError.injected {
            check(true, "failed schema-2 migration stops before publication")
        }
        check(
            try CuePackagePlanner.inspect(atCoordinatedAccessorURL: package).packageRevision == beforeRevision &&
                fileManager.contentsOfDirectory(atPath: root.path).sorted() == beforeSiblings,
            "failed schema-2 migration preserves recursive old bytes, paths, types, and siblings"
        )
        let receipt = try store.commit(document: draft, basedOn: snapshot)
        check(receipt.snapshot.writeCapability == .writableSchema3, "first verified write migrates schema 2 to schema 3")
        check(
            try CuePackagePlanner.inspect(atCoordinatedAccessorURL: receipt.retainedBackupURL!).packageRevision == beforeRevision,
            "schema-2 migration retains the exact old package revision"
        )

        let secondSnapshot = receipt.snapshot
        var exactDraft = secondSnapshot.document!
        exactDraft.items[0].body = "composed é\nexact body"
        exactDraft.items[0].contentHash = ContentHasher.hash(exactDraft.items[0].body)
        let exactReceipt = try store.commit(document: exactDraft, basedOn: secondSnapshot)
        let exactRecord = exactReceipt.snapshot.itemRecords.first { $0.record.item.id == exactDraft.items[0].id }!
        check(
            exactRecord.data.suffix(Data(exactDraft.items[0].body.utf8).count) == Data(exactDraft.items[0].body.utf8),
            "transaction writes the exact requested canonically-equivalent body bytes"
        )
        do {
            _ = try store.commit(document: secondSnapshot.document!, basedOn: secondSnapshot)
            check(false, "stale snapshot loses the final coordinated CAS")
        } catch WorkspaceStoreError.externalModification {
            check(true, "stale snapshot loses the final coordinated CAS")
        }

        let deleteSnapshot = exactReceipt.snapshot
        let observed = deleteSnapshot.itemRecords[0].revision
        var deletedDraft = deleteSnapshot.document!
        let deletedID = deletedDraft.items.removeFirst().id
        let deleteReceipt = try store.commit(document: deletedDraft, basedOn: deleteSnapshot)
        check(
            deleteReceipt.snapshot.tombstones.contains {
                $0.itemID == deletedID && $0.binding == .observed(recordRevision: observed)
            },
            "transaction deletion binds the exact observed record revision"
        )
    } catch {
        failed += 1
        print("FAIL  schema-2 transaction closure: \(error)")
    }

    for phase in [
        WorkspaceTransactionFailpoint.afterStageSynchronized,
        .afterStageValidated,
        .afterRevisionConfirmed,
    ] {
        do {
            let root = fileManager.temporaryDirectory.appendingPathComponent("CueThrow-\(phase.rawValue)-\(UUID())")
            try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? fileManager.removeItem(at: root) }
            let package = root.appendingPathComponent("workspace.cue")
            let baseStore = WorkspaceStore()
            let created = try baseStore.createSnapshot(document: sampleDocument(), at: package)
            let store = WorkspaceStore { current, _ in if current == phase { throw TransactionFixtureError.injected } }
            var draft = created.snapshot.document!
            draft.title = phase.rawValue
            do {
                _ = try store.commit(document: draft, basedOn: created.snapshot)
                check(false, "\(phase.rawValue) ordinary failure stops publication")
            } catch TransactionFixtureError.injected {
                check(true, "\(phase.rawValue) ordinary failure stops publication")
            }
            check(try baseStore.loadSnapshot(from: package).revision == created.snapshot.revision, "\(phase.rawValue) leaves exact old live")
            check(try siblingPackages(of: package, containing: ".cue-stage-").isEmpty, "\(phase.rawValue) cleans only its stage")
            check(try archivedBackups(of: package).isEmpty, "\(phase.rawValue) creates no backup")
        } catch {
            failed += 1
            print("FAIL  \(phase.rawValue) ordinary fixture: \(error)")
        }
    }

    for phase in [
        WorkspaceTransactionFailpoint.afterReplacement,
        .afterPublishedValidation,
    ] {
        do {
            let root = fileManager.temporaryDirectory.appendingPathComponent("CueThrow-\(phase.rawValue)-\(UUID())")
            try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? fileManager.removeItem(at: root) }
            let package = root.appendingPathComponent("workspace.cue")
            let baseStore = WorkspaceStore()
            let created = try baseStore.createSnapshot(document: sampleDocument(), at: package)
            let store = WorkspaceStore { current, _ in if current == phase { throw TransactionFixtureError.injected } }
            var draft = created.snapshot.document!
            draft.title = phase.rawValue
            var recovery: WorkspacePublicationRecovery?
            do {
                _ = try store.commit(document: draft, basedOn: created.snapshot)
                check(false, "\(phase.rawValue) ordinary post-publication failure requires recovery")
            } catch let WorkspaceStoreError.publicationRecoveryRequired(evidence) {
                recovery = evidence
                check(true, "\(phase.rawValue) ordinary post-publication failure requires recovery")
            } catch {
                check(false, "\(phase.rawValue) ordinary post-publication failure is typed (unexpected error: \(error))")
            }
            let live = try baseStore.loadSnapshot(from: package)
            check(
                live.document?.title == phase.rawValue && live.revision == recovery?.targetRevision,
                "\(phase.rawValue) ordinary failure preserves exact new live"
            )
            check(
                recovery?.sourceRevision == created.snapshot.revision &&
                    recovery?.candidates.contains(where: {
                        $0.url.standardizedFileURL == package.standardizedFileURL && $0.state == .target
                    }) == true,
                "\(phase.rawValue) recovery identifies exact source and live target"
            )
            check(try siblingPackages(of: package, containing: ".cue-stage-").isEmpty, "\(phase.rawValue) consumes the stage without rollback")
            let adjacent = try siblingPackages(of: package, containing: ".cue-prior-")
            let archived = try archivedBackups(of: package)
            let backups = phase == .afterReplacement ? adjacent : archived
            check(
                try backups.count == 1 &&
                    CuePackagePlanner.inspect(atCoordinatedAccessorURL: backups[0]).packageRevision == created.snapshot.revision,
                "\(phase.rawValue) ordinary failure preserves exact old backup"
            )
            check(
                recovery?.candidates.contains(where: { $0.state == .source }) == true,
                "\(phase.rawValue) recovery exposes the exact old package"
            )
            check(
                phase == .afterReplacement ? archived.isEmpty : adjacent.isEmpty,
                "\(phase.rawValue) leaves the backup at its owned publication phase"
            )
        } catch {
            failed += 1
            print("FAIL  \(phase.rawValue) ordinary recovery fixture: \(error)")
        }
    }

    do {
        let root = fileManager.temporaryDirectory.appendingPathComponent("CueReplaceThenThrow-\(UUID())")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: root) }
        let package = root.appendingPathComponent("workspace.cue")
        let baseStore = WorkspaceStore()
        let created = try baseStore.createSnapshot(document: sampleDocument(), at: package)
        var draft = created.snapshot.document!
        draft.title = "replacement completed before error"
        let store = WorkspaceStore(fileManager: ReplaceThenThrowFileManager())
        var recovery: WorkspacePublicationRecovery?
        do {
            _ = try store.commit(document: draft, basedOn: created.snapshot)
            check(false, "replace-then-throw requires typed publication recovery")
        } catch let WorkspaceStoreError.publicationRecoveryRequired(evidence) {
            recovery = evidence
            check(true, "replace-then-throw requires typed publication recovery")
        } catch {
            check(false, "replace-then-throw is typed (unexpected error: \(error))")
        }
        let live = try baseStore.loadSnapshot(from: package)
        let backups = try siblingPackages(of: package, containing: ".cue-prior-")
        check(
            live.document?.title == draft.title && live.revision == recovery?.targetRevision,
            "replace-then-throw preserves exact new live"
        )
        check(
            try backups.count == 1 &&
                CuePackagePlanner.inspect(atCoordinatedAccessorURL: backups[0]).packageRevision == created.snapshot.revision,
            "replace-then-throw preserves exact displaced old package"
        )
        check(
            recovery?.sourceRevision == created.snapshot.revision &&
                recovery?.candidates.contains(where: { $0.state == .target }) == true &&
                recovery?.candidates.contains(where: { $0.state == .source }) == true,
            "replace-then-throw reports exact ambiguous replacement evidence"
        )
        check(try siblingPackages(of: package, containing: ".cue-stage-").isEmpty, "replace-then-throw never rolls live back through the consumed stage")
    } catch {
        failed += 1
        print("FAIL  replace-then-throw fixture: \(error)")
    }

    do {
        let root = fileManager.temporaryDirectory.appendingPathComponent("CuePreStageRejection-\(UUID())")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: root) }
        let store = WorkspaceStore()

        let readOnlyPackage = root.appendingPathComponent("read-only.cue")
        _ = try store.createSnapshot(document: sampleDocument(), at: readOnlyPackage)
        try rewriteManifest(at: readOnlyPackage) { $0["cue_schema"] = 4 }
        let readOnlySnapshot = try store.loadSnapshot(from: readOnlyPackage)
        let readOnlyRevision = readOnlySnapshot.revision
        let beforeReadOnlySiblings = try fileManager.contentsOfDirectory(atPath: root.path).sorted()
        do {
            _ = try store.commit(document: sampleDocument(), basedOn: readOnlySnapshot)
            check(false, "read-only snapshot rejects commit before staging")
        } catch WorkspaceStoreError.readOnly(.newerSchema(4)) {
            check(true, "read-only snapshot rejects commit before staging")
        } catch {
            check(false, "read-only rejection remains typed (unexpected error: \(error))")
        }
        check(
            try CuePackagePlanner.inspect(atCoordinatedAccessorURL: readOnlyPackage).packageRevision == readOnlyRevision &&
                fileManager.contentsOfDirectory(atPath: root.path).sorted() == beforeReadOnlySiblings,
            "read-only rejection has zero package or sibling side effects"
        )

        let conflictPackage = root.appendingPathComponent("conflict.cue")
        let created = try store.createSnapshot(document: sampleDocument(), at: conflictPackage)
        let observed = created.snapshot.itemRecords[0]
        var edited = observed.record
        edited.item.body += "\nexternal edit"
        edited.item.contentHash = ContentHasher.hash(edited.item.body)
        try CueItemRecordCodec.encode(edited).write(
            to: conflictPackage.appendingPathComponent(observed.path)
        )
        let tombstone = """
        {"cue_schema":3,"cue_workspace_id":"\(edited.workspaceID.uuidString)","item_id":"\(edited.item.id.uuidString)","kind":"observed","observed_revision":"\(observed.revision.rawValue)"}
        """
        try Data(tombstone.utf8).write(to: tombstoneURLFor(conflictPackage, itemID: edited.item.id))
        let conflictSnapshot = try store.loadSnapshot(from: conflictPackage)
        check(conflictSnapshot.conflicts.count == 1, "divergent edit/delete snapshot exposes one conflict before commit")
        let conflictRevision = conflictSnapshot.revision
        let beforeConflictSiblings = try fileManager.contentsOfDirectory(atPath: root.path).sorted()
        do {
            _ = try store.commit(document: conflictSnapshot.document!, basedOn: conflictSnapshot)
            check(false, "unresolved conflict rejects commit before staging")
        } catch WorkspaceStoreError.invalidDocument("workspace has unresolved storage conflicts") {
            check(true, "unresolved conflict rejects commit before staging")
        } catch {
            check(false, "unresolved conflict rejection remains typed (unexpected error: \(error))")
        }
        check(
            try CuePackagePlanner.inspect(atCoordinatedAccessorURL: conflictPackage).packageRevision == conflictRevision &&
                fileManager.contentsOfDirectory(atPath: root.path).sorted() == beforeConflictSiblings,
            "unresolved conflict rejection has zero package or sibling side effects"
        )
    } catch {
        failed += 1
        print("FAIL  pre-stage rejection fixtures: \(error)")
    }

    do {
        let root = fileManager.temporaryDirectory.appendingPathComponent("CueCorruptStage-\(UUID())")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: root) }
        let package = root.appendingPathComponent("workspace.cue")
        let base = WorkspaceStore()
        let created = try base.createSnapshot(document: sampleDocument(), at: package)
        let corrupting = WorkspaceStore { phase, context in
            if phase == .afterStageSynchronized {
                try Data("broken".utf8).write(to: context.stageURL.appendingPathComponent("manifest.yaml"))
            }
        }
        do {
            _ = try corrupting.commit(document: created.snapshot.document!, basedOn: created.snapshot)
            check(false, "corrupt stage fails before publication")
        } catch {
            check(true, "corrupt stage fails before publication")
        }
        check(try base.loadSnapshot(from: package).revision == created.snapshot.revision, "corrupt stage leaves exact old live")
        check(try siblingPackages(of: package, containing: ".cue-stage-").isEmpty, "corrupt stage is cleaned after validation failure")
    } catch {
        failed += 1
        print("FAIL  corrupt stage fixture: \(error)")
    }

    for phase in WorkspaceTransactionFailpoint.allCases {
        do {
            let root = fileManager.temporaryDirectory.appendingPathComponent("CueAbort-\(phase.rawValue)-\(UUID())")
            try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? fileManager.removeItem(at: root) }
            let package = root.appendingPathComponent("workspace.cue")
            let store = WorkspaceStore()
            let created = try store.createSnapshot(document: sampleDocument(), at: package)
            let child = try launchTransactionChild(
                package: package,
                title: "new-\(phase.rawValue)",
                revision: created.snapshot.revision,
                failpoint: phase
            )
            check(readyRevision(child) == created.snapshot.revision.rawValue, "\(phase.rawValue) child loads the exact base revision")
            release(child)
            child.process.waitUntilExit()
            check(child.process.terminationReason == .uncaughtSignal, "\(phase.rawValue) child stops at the named process failpoint")
            let live = try store.loadSnapshot(from: package)
            if [.afterStageSynchronized, .afterStageValidated, .afterRevisionConfirmed].contains(phase) {
                check(live.revision == created.snapshot.revision, "\(phase.rawValue) exposes complete old live")
                let stages = try siblingPackages(of: package, containing: ".cue-stage-")
                check(try stages.count == 1 && CuePackagePlanner.inspect(atCoordinatedAccessorURL: stages[0]).writeCapability == .writableSchema3, "\(phase.rawValue) retains one complete new stage")
                check(try archivedBackups(of: package).isEmpty, "\(phase.rawValue) has no backup")
            } else {
                check(live.document?.title == "new-\(phase.rawValue)", "\(phase.rawValue) exposes complete new live")
                check(try siblingPackages(of: package, containing: ".cue-stage-").isEmpty, "\(phase.rawValue) consumes the stage")
                let backups = phase == .afterReplacement
                    ? try siblingPackages(of: package, containing: ".cue-prior-")
                    : try archivedBackups(of: package)
                check(try backups.count == 1 && CuePackagePlanner.inspect(atCoordinatedAccessorURL: backups[0]).packageRevision == created.snapshot.revision, "\(phase.rawValue) retains exact old backup")
            }
        } catch {
            failed += 1
            print("FAIL  \(phase.rawValue) abort fixture: \(error)")
        }
    }

    do {
        let root = fileManager.temporaryDirectory.appendingPathComponent("CueRace-\(UUID())")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: root) }
        let package = root.appendingPathComponent("workspace.cue")
        let store = WorkspaceStore()
        let created = try store.createSnapshot(document: sampleDocument(), at: package)
        let a = try launchTransactionChild(package: package, title: "writer-a", revision: created.snapshot.revision, failpoint: nil)
        let b = try launchTransactionChild(package: package, title: "writer-b", revision: created.snapshot.revision, failpoint: nil)
        check(readyRevision(a) == created.snapshot.revision.rawValue && readyRevision(b) == created.snapshot.revision.rawValue, "two writers load the same exact revision before release")
        release(a)
        release(b)
        a.process.waitUntilExit()
        b.process.waitUntilExit()
        check([a.process.terminationStatus, b.process.terminationStatus].sorted() == [0, 73], "two same-revision writers produce exactly one winner")
        check(["writer-a", "writer-b"].contains(try store.loadSnapshot(from: package).document?.title ?? ""), "dual-writer live package is one complete winner")
        check(try siblingPackages(of: package, containing: ".cue-stage-").isEmpty, "dual-writer loser cleans its stage")
        check(try archivedBackups(of: package).count == 1, "dual-writer publication retains exactly one old backup")
    } catch {
        failed += 1
        print("FAIL  dual-writer fixture: \(error)")
    }
}

if !transactionChildIfRequested() {
    checkModifierTapDetector()
    checkSelectionModel()
    checkMarkdown()
    checkItemRecordCodec()
    checkPackagePlan()
    checkStorage()
    checkWorkspaceTransaction()
    checkDuplicatePolicy()
    checkPanelPresentation()
    checkPanelTrackingPolicy()
    checkPanelGeometry()
    checkPanelEngagementPolicy()
    checkPanelSettings()

    print("\nCue core checks: \(passed) passed, \(failed) failed")
    if failed > 0 { exit(1) }
}
