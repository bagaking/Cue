import Foundation

enum MarkdownWorkspaceCodec {
    private struct SectionMetadata: Codable {
        var id: UUID
        var order: Double
        var isCollapsed: Bool
    }

    private struct ItemMetadata: Codable {
        var id: UUID
        var kind: WorkItemKind
        var state: WorkItemState
        var sectionID: UUID
        var source: SourceMetadata
        var sensitivity: Sensitivity
        var contentHash: String
        var createdAt: Date
        var updatedAt: Date
        var completedAt: Date?
        var archivedAt: Date?
        var pinned: Bool
        var order: Double
        var mergedFrom: [UUID]
        var mergedInto: UUID?
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func encode(_ source: WorkspaceDocument) throws -> String {
        var document = source
        document.ensureInbox()
        document.normalizeOrder()

        var lines: [String] = [
            "---",
            "cue_schema: \(document.schemaVersion)",
            "cue_workspace_id: \(document.id.uuidString.lowercased())",
            "title: \(quoted(document.title))",
            "---",
        ]

        var emittedSections = Set<UUID>()
        var emittedItems = Set<UUID>()
        var currentSectionID: UUID?

        func appendSection(_ section: WorkSection) throws {
            let metadata = SectionMetadata(
                id: section.id,
                order: section.order,
                isCollapsed: section.isCollapsed
            )
            lines.append("## \(section.title)")
            lines.append("<!-- cue:section \(try json(metadata)) -->")
            lines.append("")
            emittedSections.insert(section.id)
            currentSectionID = section.id
        }

        func appendItem(_ item: WorkItem) throws {
            let metadata = ItemMetadata(
                id: item.id,
                kind: item.kind,
                state: item.state,
                sectionID: item.sectionID,
                source: item.source,
                sensitivity: item.sensitivity,
                contentHash: item.contentHash,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                completedAt: item.completedAt,
                archivedAt: item.archivedAt,
                pinned: item.pinned,
                order: item.order,
                mergedFrom: item.mergedFrom,
                mergedInto: item.mergedInto
            )
            lines.append("<!-- cue:item \(try json(metadata)) -->")
            let bodyLines = item.body
                .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                .map(String.init)
            let check = item.state == .queued ? " " : "x"
            lines.append("- [\(check)] \(bodyLines.first ?? "")")
            for bodyLine in bodyLines.dropFirst() {
                lines.append(bodyLine.isEmpty ? "" : "  \(bodyLine)")
            }
            lines.append("<!-- /cue:item -->")
            lines.append("")
            emittedItems.insert(item.id)
        }

        func flushMissingItems(in sectionID: UUID?) throws {
            guard let sectionID else { return }
            let missing = document.items
                .filter { $0.sectionID == sectionID && !emittedItems.contains($0.id) }
                .sorted { lhs, rhs in
                    if lhs.state != rhs.state { return stateOrder(lhs.state) < stateOrder(rhs.state) }
                    return lhs.order < rhs.order
                }
            for item in missing { try appendItem(item) }
        }

        if document.layout.isEmpty {
            lines.append(contentsOf: [
                "",
                "# \(document.title)",
                "",
                "> This file is the Cue workspace source of truth. You can edit item text and add prose; keep `cue:` comments intact for lifecycle metadata.",
                "",
            ])
        } else {
            for entry in document.layout {
                switch entry {
                case let .verbatim(line):
                    lines.append(line)
                case let .section(id):
                    try flushMissingItems(in: currentSectionID)
                    if let section = document.sections.first(where: { $0.id == id }) {
                        try appendSection(section)
                    } else {
                        currentSectionID = nil
                    }
                case let .item(id):
                    guard let item = document.items.first(where: { $0.id == id }),
                          item.sectionID == currentSectionID else { continue }
                    try appendItem(item)
                }
            }
            try flushMissingItems(in: currentSectionID)
        }

        for section in document.sections.sorted(by: { $0.order < $1.order }) where !emittedSections.contains(section.id) {
            if lines.last != "" { lines.append("") }
            try appendSection(section)
            try flushMissingItems(in: section.id)
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func decode(_ markdown: String) throws -> WorkspaceDocument {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first == "---", let frontmatterEnd = lines.dropFirst().firstIndex(of: "---") else {
            throw WorkspaceStoreError.invalidDocument("missing Cue frontmatter")
        }

        var schema = WorkspaceDocument.currentSchema
        var workspaceID: UUID?
        var title = "Cue Workspace"

        for line in lines[1..<frontmatterEnd] {
            if line.hasPrefix("cue_schema:") {
                schema = Int(value(after: ":", in: line)) ?? WorkspaceDocument.currentSchema
            } else if line.hasPrefix("cue_workspace_id:") {
                workspaceID = UUID(uuidString: value(after: ":", in: line))
            } else if line.hasPrefix("title:") {
                title = unquoted(value(after: ":", in: line))
            }
        }

        guard let workspaceID else {
            throw WorkspaceStoreError.invalidDocument("missing workspace identifier")
        }
        guard schema <= WorkspaceDocument.currentSchema else {
            throw WorkspaceStoreError.invalidDocument("workspace schema \(schema) is newer than Cue supports")
        }

        var sections: [WorkSection] = []
        var items: [WorkItem] = []
        var layout: [MarkdownLayoutEntry] = []
        var currentSectionID: UUID?
        var index = frontmatterEnd + 1

        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("## "), index + 1 < lines.count,
               let payload = payload(from: lines[index + 1], prefix: "<!-- cue:section ") {
                let metadata: SectionMetadata = try decodeJSON(payload)
                sections.append(WorkSection(
                    id: metadata.id,
                    title: String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces),
                    order: metadata.order,
                    isCollapsed: metadata.isCollapsed
                ))
                layout.append(.section(metadata.id))
                currentSectionID = metadata.id
                index += 2
                // Cue owns one visual separator after managed section metadata.
                // Consume only that separator so repeated read/write cycles are
                // byte-stable while additional user-authored whitespace remains.
                if index < lines.count, lines[index].isEmpty { index += 1 }
                continue
            }

            if line.hasPrefix("<!-- cue:item "), let payload = payload(from: line, prefix: "<!-- cue:item ") {
                let metadata: ItemMetadata = try decodeJSON(payload)
                index += 1
                var bodyLines: [String] = []

                while index < lines.count, lines[index] != "<!-- /cue:item -->" {
                    let bodyLine = lines[index]
                    if bodyLines.isEmpty {
                        if bodyLine.hasPrefix("- [ ] ") || bodyLine.hasPrefix("- [x] ") || bodyLine.hasPrefix("- [X] ") {
                            bodyLines.append(String(bodyLine.dropFirst(6)))
                        } else {
                            bodyLines.append(bodyLine)
                        }
                    } else if bodyLine.hasPrefix("  ") {
                        bodyLines.append(String(bodyLine.dropFirst(2)))
                    } else {
                        bodyLines.append(bodyLine)
                    }
                    index += 1
                }

                guard index < lines.count else {
                    throw WorkspaceStoreError.invalidDocument("item \(metadata.id) has no closing marker")
                }

                let body = bodyLines.joined(separator: "\n")
                items.append(WorkItem(
                    id: metadata.id,
                    body: body,
                    kind: metadata.kind,
                    state: metadata.state,
                    sectionID: metadata.sectionID,
                    source: metadata.source,
                    sensitivity: metadata.sensitivity,
                    contentHash: ContentHasher.hash(body),
                    createdAt: metadata.createdAt,
                    updatedAt: metadata.updatedAt,
                    completedAt: metadata.completedAt,
                    archivedAt: metadata.archivedAt,
                    pinned: metadata.pinned,
                    order: metadata.order,
                    mergedFrom: metadata.mergedFrom,
                    mergedInto: metadata.mergedInto
                ))
                layout.append(.item(metadata.id))
                index += 1
                // `appendItem` emits one canonical separator after the closing
                // marker. Avoid reclassifying it as external prose and growing
                // another blank line on every save.
                if index < lines.count, lines[index].isEmpty { index += 1 }
                continue
            }

            if let sectionID = currentSectionID,
               line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                let done = !line.hasPrefix("- [ ] ")
                var bodyLines = [String(line.dropFirst(6))]
                index += 1
                while index < lines.count, lines[index].hasPrefix("  ") {
                    bodyLines.append(String(lines[index].dropFirst(2)))
                    index += 1
                }
                let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty {
                    let id = UUID()
                    let now = Date()
                    items.append(WorkItem(
                        id: id,
                        body: body,
                        kind: .prompt,
                        state: done ? .completed : .queued,
                        sectionID: sectionID,
                        contentHash: ContentHasher.hash(body),
                        createdAt: now,
                        updatedAt: now,
                        completedAt: done ? now : nil,
                        order: Double(items.filter { $0.sectionID == sectionID }.count)
                    ))
                    layout.append(.item(id))
                    // Once adopted, the task becomes a Cue-owned item and its
                    // first following blank line becomes the owned separator.
                    if index < lines.count, lines[index].isEmpty { index += 1 }
                } else {
                    layout.append(.verbatim(line))
                }
                continue
            }
            layout.append(.verbatim(line))
            index += 1
        }

        var document = WorkspaceDocument(
            schemaVersion: schema,
            id: workspaceID,
            title: title,
            sections: sections,
            items: items,
            layout: layout
        )
        document.ensureInbox()

        guard Set(document.sections.map(\.id)).count == document.sections.count else {
            throw WorkspaceStoreError.invalidDocument("duplicate section identifiers")
        }
        guard Set(document.items.map(\.id)).count == document.items.count else {
            throw WorkspaceStoreError.invalidDocument("duplicate item identifiers")
        }

        let validSectionIDs = Set(document.sections.map(\.id))
        let inboxID = document.inbox.id
        for itemIndex in document.items.indices where !validSectionIDs.contains(document.items[itemIndex].sectionID) {
            document.items[itemIndex].sectionID = inboxID
        }
        document.normalizeOrder()
        return document
    }

    private static func stateOrder(_ state: WorkItemState) -> Int {
        switch state {
        case .queued: 0
        case .completed: 1
        case .archived: 2
        }
    }

    private static func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func decodeJSON<T: Decodable>(_ value: String) throws -> T {
        do {
            return try decoder.decode(T.self, from: Data(value.utf8))
        } catch {
            throw WorkspaceStoreError.invalidDocument("invalid Cue metadata: \(error.localizedDescription)")
        }
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func unquoted(_ value: String) -> String {
        guard value.first == "\"", value.last == "\"", value.count >= 2 else { return value }
        return String(value.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func value(after separator: Character, in line: String) -> String {
        guard let index = line.firstIndex(of: separator) else { return "" }
        return String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespaces)
    }

    private static func payload(from line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix), line.hasSuffix(" -->") else { return nil }
        return String(line.dropFirst(prefix.count).dropLast(4))
    }
}
