import Foundation

/// Adapted from Pewter's MIT-licensed ordered selection model.
struct ItemSelectionModel: Equatable, Sendable {
    private(set) var selected: Set<UUID> = []
    private(set) var anchor: UUID?
    private(set) var lead: UUID?

    var isEmpty: Bool { selected.isEmpty }
    var count: Int { selected.count }
    var single: UUID? { selected.count == 1 ? selected.first : nil }
    var isMultiple: Bool { selected.count > 1 }

    func isSelected(_ id: UUID) -> Bool { selected.contains(id) }

    mutating func select(_ id: UUID) {
        selected = [id]
        anchor = id
        lead = id
    }

    mutating func toggle(_ id: UUID) {
        if selected.contains(id) {
            selected.remove(id)
            if anchor == id { anchor = selected.contains(lead ?? id) ? lead : selected.first }
            if lead == id { lead = anchor }
            if selected.isEmpty { anchor = nil; lead = nil }
        } else {
            selected.insert(id)
            anchor = id
            lead = id
        }
    }

    mutating func extend(to id: UUID, order: [UUID]) {
        guard let targetIndex = order.firstIndex(of: id) else { return }
        guard let anchor, let anchorIndex = order.firstIndex(of: anchor) else {
            select(id)
            return
        }
        selected = Set(order[min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)])
        lead = id
    }

    @discardableResult
    mutating func step(_ delta: Int, order: [UUID], extending: Bool) -> UUID? {
        guard !order.isEmpty else { return nil }
        let target: UUID
        if let lead, let index = order.firstIndex(of: lead) {
            target = order[min(max(index + delta, 0), order.count - 1)]
        } else {
            target = delta > 0 ? order[0] : order[order.count - 1]
        }
        if extending { extend(to: target, order: order) } else { select(target) }
        return target
    }

    mutating func replace(with ids: Set<UUID>, order: [UUID]) {
        selected = ids.intersection(order)
        anchor = order.first { selected.contains($0) }
        lead = order.last { selected.contains($0) }
    }

    mutating func selectAll(order: [UUID]) {
        guard !order.isEmpty else { return }
        selected = Set(order)
        anchor = order.first
        lead = order.last
    }

    mutating func clear() {
        selected.removeAll()
        anchor = nil
        lead = nil
    }

    mutating func prune(order: [UUID]) {
        selected.formIntersection(order)
        if let anchor, !selected.contains(anchor) { self.anchor = nil }
        if let lead, !selected.contains(lead) { self.lead = nil }
        if anchor == nil { anchor = lead ?? order.first(where: { selected.contains($0) }) }
        if lead == nil { lead = anchor }
    }
}
