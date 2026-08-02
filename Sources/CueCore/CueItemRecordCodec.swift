import Foundation

public struct CueItemRecord: Equatable, Sendable {
    public var workspaceID: UUID
    public var item: WorkItem
    var envelope: CueItemRecordEnvelope?

    public init(workspaceID: UUID, item: WorkItem) {
        self.workspaceID = workspaceID
        self.item = item
        envelope = nil
    }

    init(workspaceID: UUID, item: WorkItem, envelope: CueItemRecordEnvelope) {
        self.workspaceID = workspaceID
        self.item = item
        self.envelope = envelope
    }

    public static func == (lhs: CueItemRecord, rhs: CueItemRecord) -> Bool {
        lhs.workspaceID == rhs.workspaceID && lhs.item == rhs.item
    }
}

struct CueItemRecordEnvelope: Equatable, Sendable {
    var originalData: Data
    var beforeCueObject: Data
    var cueObject: CueJSONObjectEnvelope
    var afterCueObjectThroughClosingDelimiter: Data
    var originalBody: Data
    var originalItem: WorkItem
    var workspaceID: UUID
}

struct CueJSONObjectEnvelope: Equatable, Sendable {
    struct Member: Equatable, Sendable {
        var key: String
        var memberRange: Range<Int>
        var valueRange: Range<Int>
    }

    var original: Data
    var members: [Member]
}

/// The one codec for package item records and explicit external `.cue.md`
/// import/export. Cue owns only the top-level `cue` frontmatter key.
public enum CueItemRecordCodec {
    public static let schemaVersion = 3

    private struct SourceRecord: Codable, Equatable {
        var appName: String?
        var bundleIdentifier: String?
        var windowTitle: String?
        var url: String?

        enum CodingKeys: String, CodingKey, CaseIterable {
            case appName
            case bundleIdentifier
            case windowTitle
            case url
        }

        init(_ source: SourceMetadata) {
            appName = source.appName
            bundleIdentifier = source.bundleIdentifier
            windowTitle = source.windowTitle
            url = source.url
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            for key in CodingKeys.allCases where !values.contains(key) {
                throw DecodingError.keyNotFound(
                    key,
                    DecodingError.Context(codingPath: values.codingPath, debugDescription: "source metadata is missing \(key.rawValue)")
                )
            }
            appName = try values.decodeIfPresent(String.self, forKey: .appName)
            bundleIdentifier = try values.decodeIfPresent(String.self, forKey: .bundleIdentifier)
            windowTitle = try values.decodeIfPresent(String.self, forKey: .windowTitle)
            url = try values.decodeIfPresent(String.self, forKey: .url)
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            if let appName { try values.encode(appName, forKey: .appName) } else { try values.encodeNil(forKey: .appName) }
            if let bundleIdentifier { try values.encode(bundleIdentifier, forKey: .bundleIdentifier) } else { try values.encodeNil(forKey: .bundleIdentifier) }
            if let windowTitle { try values.encode(windowTitle, forKey: .windowTitle) } else { try values.encodeNil(forKey: .windowTitle) }
            if let url { try values.encode(url, forKey: .url) } else { try values.encodeNil(forKey: .url) }
        }

        var sourceMetadata: SourceMetadata {
            SourceMetadata(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle,
                url: url
            )
        }
    }

    private struct ItemMetadata: Codable, Equatable {
        var schemaVersion: Int
        var workspaceID: UUID
        var id: UUID
        var kind: WorkItemKind
        var state: WorkItemState
        var sectionID: UUID
        var source: SourceRecord
        var sensitivity: Sensitivity
        var createdAt: Date
        var updatedAt: Date
        var completedAt: Date?
        var archivedAt: Date?
        var pinned: Bool
        var order: Double
        var mergedFrom: [UUID]
        var mergedInto: UUID?

        enum CodingKeys: String, CodingKey, CaseIterable {
            case schemaVersion = "schema"
            case workspaceID = "workspace_id"
            case id
            case kind
            case state
            case sectionID = "section_id"
            case source
            case sensitivity
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case completedAt = "completed_at"
            case archivedAt = "archived_at"
            case pinned
            case order
            case mergedFrom = "merged_from"
            case mergedInto = "merged_into"
        }

        init(item: WorkItem, workspaceID: UUID) {
            schemaVersion = CueItemRecordCodec.schemaVersion
            self.workspaceID = workspaceID
            id = item.id
            kind = item.kind
            state = item.state
            sectionID = item.sectionID
            source = SourceRecord(item.source)
            sensitivity = item.sensitivity
            createdAt = item.createdAt
            updatedAt = item.updatedAt
            completedAt = item.completedAt
            archivedAt = item.archivedAt
            pinned = item.pinned
            order = item.order
            mergedFrom = item.mergedFrom
            mergedInto = item.mergedInto
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
            workspaceID = try values.decode(UUID.self, forKey: .workspaceID)
            id = try values.decode(UUID.self, forKey: .id)
            kind = try values.decode(WorkItemKind.self, forKey: .kind)
            state = try values.decode(WorkItemState.self, forKey: .state)
            sectionID = try values.decode(UUID.self, forKey: .sectionID)
            source = try values.decode(SourceRecord.self, forKey: .source)
            sensitivity = try values.decode(Sensitivity.self, forKey: .sensitivity)
            createdAt = try values.decode(Date.self, forKey: .createdAt)
            updatedAt = try values.decode(Date.self, forKey: .updatedAt)
            completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
            archivedAt = try values.decodeIfPresent(Date.self, forKey: .archivedAt)
            pinned = try values.decode(Bool.self, forKey: .pinned)
            order = try values.decode(Double.self, forKey: .order)
            mergedFrom = try values.decode([UUID].self, forKey: .mergedFrom)
            mergedInto = try values.decodeIfPresent(UUID.self, forKey: .mergedInto)
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(schemaVersion, forKey: .schemaVersion)
            try values.encode(workspaceID, forKey: .workspaceID)
            try values.encode(id, forKey: .id)
            try values.encode(kind, forKey: .kind)
            try values.encode(state, forKey: .state)
            try values.encode(sectionID, forKey: .sectionID)
            try values.encode(source, forKey: .source)
            try values.encode(sensitivity, forKey: .sensitivity)
            try values.encode(createdAt, forKey: .createdAt)
            try values.encode(updatedAt, forKey: .updatedAt)
            if let completedAt {
                try values.encode(completedAt, forKey: .completedAt)
            } else {
                try values.encodeNil(forKey: .completedAt)
            }
            if let archivedAt {
                try values.encode(archivedAt, forKey: .archivedAt)
            } else {
                try values.encodeNil(forKey: .archivedAt)
            }
            try values.encode(pinned, forKey: .pinned)
            try values.encode(order, forKey: .order)
            try values.encode(mergedFrom, forKey: .mergedFrom)
            if let mergedInto {
                try values.encode(mergedInto, forKey: .mergedInto)
            } else {
                try values.encodeNil(forKey: .mergedInto)
            }
        }

        var item: WorkItem {
            WorkItem(
                id: id,
                body: "",
                kind: kind,
                state: state,
                sectionID: sectionID,
                source: source.sourceMetadata,
                sensitivity: sensitivity,
                contentHash: "",
                createdAt: createdAt,
                updatedAt: updatedAt,
                completedAt: completedAt,
                archivedAt: archivedAt,
                pinned: pinned,
                order: order,
                mergedFrom: mergedFrom,
                mergedInto: mergedInto
            )
        }
    }

    private struct Line {
        var content: Range<Int>
        var full: Range<Int>
    }

    private static let managedKeys = Set(ItemMetadata.CodingKeys.allCases.map(\.rawValue))
    private static let sourceManagedKeys = Set(SourceRecord.CodingKeys.allCases.map(\.rawValue))

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func decode(_ data: Data) throws -> CueItemRecord {
        do {
            return try decodeRecord(data)
        } catch let error as WorkspaceStoreError {
            throw error
        } catch {
            throw WorkspaceStoreError.invalidDocument(error.localizedDescription)
        }
    }

    private static func decodeRecord(_ data: Data) throws -> CueItemRecord {
        guard String(data: data, encoding: .utf8) != nil else {
            throw WorkspaceStoreError.invalidDocument("item record is not UTF-8")
        }

        let lines = lineRanges(in: data)
        guard let opening = lines.first, data[opening.content] == Data("---".utf8) else {
            throw WorkspaceStoreError.invalidDocument("item record is missing YAML frontmatter")
        }
        guard let closingIndex = lines.indices.dropFirst().first(where: {
            data[lines[$0].content] == Data("---".utf8)
        }) else {
            throw WorkspaceStoreError.invalidDocument("item record frontmatter is not closed")
        }

        let cuePrefix = Data("cue:".utf8)
        let frontmatterLines = lines[lines.index(after: lines.startIndex)..<closingIndex]
        let cueLines = frontmatterLines.filter { data[$0.content].starts(with: cuePrefix) }
        guard cueLines.count == 1, let cueLine = cueLines.first else {
            throw WorkspaceStoreError.invalidDocument("item record must contain exactly one top-level cue key")
        }

        let payloadStart = data.index(cueLine.content.lowerBound, offsetBy: cuePrefix.count)
        let payloadRange = data.asciiWhitespaceTrimmedRange(in: payloadStart..<cueLine.content.upperBound)
        guard !payloadRange.isEmpty else {
            throw WorkspaceStoreError.invalidDocument("cue frontmatter value is empty")
        }
        let cueObjectData = Data(data[payloadRange])
        let cueObject = try parseJSONObjectEnvelope(cueObjectData)
        let keys = Set(cueObject.members.map(\.key))
        guard managedKeys.isSubset(of: keys) else {
            let missing = managedKeys.subtracting(keys).sorted().joined(separator: ", ")
            throw WorkspaceStoreError.invalidDocument("cue metadata is missing required keys: \(missing)")
        }

        let metadata = try makeDecoder().decode(ItemMetadata.self, from: cueObjectData)
        guard metadata.schemaVersion == schemaVersion else {
            throw WorkspaceStoreError.invalidDocument("item schema \(metadata.schemaVersion) is unsupported")
        }

        let closing = lines[closingIndex]
        let bodyStart = closing.full.upperBound
        let bodyData = bodyStart < data.endIndex ? Data(data[bodyStart...]) : Data()
        guard let body = String(data: bodyData, encoding: .utf8) else {
            throw WorkspaceStoreError.invalidDocument("item body is not UTF-8")
        }
        var item = metadata.item
        item.body = body
        item.contentHash = ContentHasher.hash(body)

        let envelope = CueItemRecordEnvelope(
            originalData: data,
            beforeCueObject: Data(data[..<payloadRange.lowerBound]),
            cueObject: cueObject,
            afterCueObjectThroughClosingDelimiter: Data(data[payloadRange.upperBound..<bodyStart]),
            originalBody: bodyData,
            originalItem: item,
            workspaceID: metadata.workspaceID
        )
        return CueItemRecord(workspaceID: metadata.workspaceID, item: item, envelope: envelope)
    }

    public static func encode(_ record: CueItemRecord) throws -> Data {
        if let envelope = record.envelope,
           envelope.workspaceID == record.workspaceID,
           sameManagedRecord(record.item, envelope.originalItem) {
            return envelope.originalData
        }

        let metadata = ItemMetadata(item: record.item, workspaceID: record.workspaceID)
        let canonicalObject = try makeEncoder().encode(metadata)
        let canonicalEnvelope = try parseJSONObjectEnvelope(canonicalObject)

        let cueObjectData: Data
        if let envelope = record.envelope {
            var replacementValues = Dictionary(uniqueKeysWithValues: canonicalEnvelope.members.map {
                ($0.key, Data(canonicalObject[$0.valueRange]))
            })
            if let originalSource = envelope.cueObject.members.first(where: { $0.key == ItemMetadata.CodingKeys.source.rawValue }),
               let canonicalSource = canonicalEnvelope.members.first(where: { $0.key == ItemMetadata.CodingKeys.source.rawValue }) {
                replacementValues[ItemMetadata.CodingKeys.source.rawValue] = try replacingManagedValues(
                    in: Data(envelope.cueObject.original[originalSource.valueRange]),
                    with: Data(canonicalObject[canonicalSource.valueRange]),
                    managedKeys: sourceManagedKeys
                )
            }
            var updated = envelope.cueObject.original
            for member in envelope.cueObject.members
                .filter({ managedKeys.contains($0.key) })
                .sorted(by: { $0.valueRange.lowerBound > $1.valueRange.lowerBound }) {
                guard let replacement = replacementValues[member.key] else {
                    throw WorkspaceStoreError.invalidDocument("Cue could not encode metadata key \(member.key)")
                }
                updated.replaceSubrange(member.valueRange, with: replacement)
            }
            cueObjectData = updated
        } else {
            cueObjectData = canonicalObject
        }

        let bodyData: Data
        if let envelope = record.envelope, Data(record.item.body.utf8) == envelope.originalBody {
            bodyData = envelope.originalBody
        } else {
            bodyData = Data(record.item.body.utf8)
        }

        if let envelope = record.envelope {
            var data = envelope.beforeCueObject
            data.append(cueObjectData)
            data.append(envelope.afterCueObjectThroughClosingDelimiter)
            data.append(bodyData)
            return data
        }

        var data = Data("---\ncue: ".utf8)
        data.append(cueObjectData)
        data.append(Data("\n---\n".utf8))
        data.append(bodyData)
        return data
    }

    private static func sameManagedRecord(_ lhs: WorkItem, _ rhs: WorkItem) -> Bool {
        guard Data(lhs.body.utf8) == Data(rhs.body.utf8) else { return false }
        var normalizedLHS = lhs
        var normalizedRHS = rhs
        normalizedLHS.body = ""
        normalizedRHS.body = ""
        normalizedLHS.contentHash = ""
        normalizedRHS.contentHash = ""
        return normalizedLHS == normalizedRHS
    }

    private static func replacingManagedValues(
        in original: Data,
        with canonical: Data,
        managedKeys: Set<String>
    ) throws -> Data {
        let originalEnvelope = try parseJSONObjectEnvelope(original)
        let canonicalEnvelope = try parseJSONObjectEnvelope(canonical)
        let originalKeys = Set(originalEnvelope.members.map(\.key))
        guard managedKeys.isSubset(of: originalKeys) else {
            let missing = managedKeys.subtracting(originalKeys).sorted().joined(separator: ", ")
            throw WorkspaceStoreError.invalidDocument("Cue metadata is missing required keys: \(missing)")
        }
        let replacements = Dictionary(uniqueKeysWithValues: canonicalEnvelope.members.map {
            ($0.key, Data(canonical[$0.valueRange]))
        })
        var updated = original
        for member in originalEnvelope.members
            .filter({ managedKeys.contains($0.key) })
            .sorted(by: { $0.valueRange.lowerBound > $1.valueRange.lowerBound }) {
            guard let replacement = replacements[member.key] else {
                throw WorkspaceStoreError.invalidDocument("Cue could not encode metadata key \(member.key)")
            }
            updated.replaceSubrange(member.valueRange, with: replacement)
        }
        return updated
    }

    static func parseJSONObjectEnvelope(_ data: Data) throws -> CueJSONObjectEnvelope {
        guard String(data: data, encoding: .utf8) != nil else {
            throw WorkspaceStoreError.invalidDocument("cue JSON object is not UTF-8")
        }
        var cursor = data.startIndex
        skipJSONWhitespace(in: data, cursor: &cursor)
        let members = try scanJSONObject(in: data, cursor: &cursor, collectMembers: true)
        skipJSONWhitespace(in: data, cursor: &cursor)
        guard cursor == data.endIndex,
              (try JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            throw WorkspaceStoreError.invalidDocument("cue frontmatter value must be one JSON flow map")
        }
        return CueJSONObjectEnvelope(original: data, members: members)
    }

    private static func scanJSONValue(in data: Data, cursor: inout Int) throws {
        guard cursor < data.endIndex else {
            throw WorkspaceStoreError.invalidDocument("cue JSON member has no value")
        }
        switch data[cursor] {
        case 0x22:
            _ = try scanJSONString(in: data, cursor: &cursor)
        case 0x7B:
            _ = try scanJSONObject(in: data, cursor: &cursor, collectMembers: false)
        case 0x5B:
            try scanJSONArray(in: data, cursor: &cursor)
        default:
            let start = cursor
            while cursor < data.endIndex,
                  data[cursor] != 0x2C,
                  data[cursor] != 0x7D,
                  data[cursor] != 0x5D {
                cursor = data.index(after: cursor)
            }
            var end = cursor
            while end > start, isJSONWhitespace(data[data.index(before: end)]) {
                end = data.index(before: end)
            }
            guard end > start else {
                throw WorkspaceStoreError.invalidDocument("cue JSON member has an empty value")
            }
            cursor = end
        }
    }

    private static func scanJSONObject(
        in data: Data,
        cursor: inout Int,
        collectMembers: Bool
    ) throws -> [CueJSONObjectEnvelope.Member] {
        guard cursor < data.endIndex, data[cursor] == 0x7B else {
            throw WorkspaceStoreError.invalidDocument("cue frontmatter value must be one JSON flow map")
        }
        cursor = data.index(after: cursor)
        skipJSONWhitespace(in: data, cursor: &cursor)
        if cursor < data.endIndex, data[cursor] == 0x7D {
            cursor = data.index(after: cursor)
            return []
        }

        var members: [CueJSONObjectEnvelope.Member] = []
        var seen = Set<String>()
        while true {
            let memberStart = cursor
            let keyRange = try scanJSONString(in: data, cursor: &cursor)
            let key = try makeDecoder().decode(String.self, from: Data(data[keyRange]))
            guard seen.insert(key).inserted else {
                throw WorkspaceStoreError.invalidDocument("cue JSON object contains duplicate key \(key)")
            }
            skipJSONWhitespace(in: data, cursor: &cursor)
            guard cursor < data.endIndex, data[cursor] == 0x3A else {
                throw WorkspaceStoreError.invalidDocument("cue JSON member \(key) has no colon")
            }
            cursor = data.index(after: cursor)
            skipJSONWhitespace(in: data, cursor: &cursor)
            let valueStart = cursor
            try scanJSONValue(in: data, cursor: &cursor)
            let valueEnd = cursor
            if collectMembers {
                members.append(.init(key: key, memberRange: memberStart..<valueEnd, valueRange: valueStart..<valueEnd))
            }

            skipJSONWhitespace(in: data, cursor: &cursor)
            guard cursor < data.endIndex else {
                throw WorkspaceStoreError.invalidDocument("cue JSON object is not closed")
            }
            if data[cursor] == 0x7D {
                cursor = data.index(after: cursor)
                return members
            }
            guard data[cursor] == 0x2C else {
                throw WorkspaceStoreError.invalidDocument("cue JSON object has an invalid member separator")
            }
            cursor = data.index(after: cursor)
            skipJSONWhitespace(in: data, cursor: &cursor)
            guard cursor < data.endIndex, data[cursor] != 0x7D else {
                throw WorkspaceStoreError.invalidDocument("cue JSON object has a trailing comma")
            }
        }
    }

    private static func scanJSONArray(in data: Data, cursor: inout Int) throws {
        guard cursor < data.endIndex, data[cursor] == 0x5B else {
            throw WorkspaceStoreError.invalidDocument("cue JSON array is malformed")
        }
        cursor = data.index(after: cursor)
        skipJSONWhitespace(in: data, cursor: &cursor)
        if cursor < data.endIndex, data[cursor] == 0x5D {
            cursor = data.index(after: cursor)
            return
        }

        while true {
            try scanJSONValue(in: data, cursor: &cursor)
            skipJSONWhitespace(in: data, cursor: &cursor)
            guard cursor < data.endIndex else {
                throw WorkspaceStoreError.invalidDocument("cue JSON array is not closed")
            }
            if data[cursor] == 0x5D {
                cursor = data.index(after: cursor)
                return
            }
            guard data[cursor] == 0x2C else {
                throw WorkspaceStoreError.invalidDocument("cue JSON array has an invalid separator")
            }
            cursor = data.index(after: cursor)
            skipJSONWhitespace(in: data, cursor: &cursor)
            guard cursor < data.endIndex, data[cursor] != 0x5D else {
                throw WorkspaceStoreError.invalidDocument("cue JSON array has a trailing comma")
            }
        }
    }

    private static func scanJSONString(in data: Data, cursor: inout Int) throws -> Range<Int> {
        guard cursor < data.endIndex, data[cursor] == 0x22 else {
            throw WorkspaceStoreError.invalidDocument("cue JSON member key is not a string")
        }
        let start = cursor
        cursor = data.index(after: cursor)
        var escaped = false
        while cursor < data.endIndex {
            let byte = data[cursor]
            cursor = data.index(after: cursor)
            if escaped {
                escaped = false
            } else if byte == 0x5C {
                escaped = true
            } else if byte == 0x22 {
                return start..<cursor
            }
        }
        throw WorkspaceStoreError.invalidDocument("cue JSON contains an unclosed string")
    }

    private static func skipJSONWhitespace(in data: Data, cursor: inout Int) {
        while cursor < data.endIndex, isJSONWhitespace(data[cursor]) {
            cursor = data.index(after: cursor)
        }
    }

    private static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private static func lineRanges(in data: Data) -> [Line] {
        var lines: [Line] = []
        var start = data.startIndex
        while start < data.endIndex {
            if let newline = data[start...].firstIndex(of: 0x0A) {
                var contentEnd = newline
                if contentEnd > start, data[data.index(before: contentEnd)] == 0x0D {
                    contentEnd = data.index(before: contentEnd)
                }
                lines.append(Line(content: start..<contentEnd, full: start..<data.index(after: newline)))
                start = data.index(after: newline)
            } else {
                lines.append(Line(content: start..<data.endIndex, full: start..<data.endIndex))
                start = data.endIndex
            }
        }
        return lines
    }
}

private extension Data {
    func asciiWhitespaceTrimmedRange(in range: Range<Int>) -> Range<Int> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, self[lower] == 0x20 || self[lower] == 0x09 {
            lower = index(after: lower)
        }
        while upper > lower {
            let previous = index(before: upper)
            guard self[previous] == 0x20 || self[previous] == 0x09 else { break }
            upper = previous
        }
        return lower..<upper
    }
}
