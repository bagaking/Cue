import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkItemCard: View {
    var item: WorkItem
    var selected: Bool
    var focused: Bool
    var sections: [WorkSection]
    var onSelect: () -> Void
    var onToggle: () -> Void
    var onCopy: () -> Void
    var onEdit: () -> Void
    var onArchive: () -> Void
    var onRestore: () -> Void
    var onPin: () -> Void
    var onMove: (UUID) -> Void
    var onDropBefore: (UUID) -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: item.state == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16.5, weight: .light))
                    .foregroundStyle(item.state == .completed ? Color.accentColor : Color.secondary.opacity(0.7))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(item.state == .archived)
            .accessibilityLabel(item.state == .completed ? "Mark as queued" : "Mark as completed")
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(markdownText)
                    .font(.system(size: 13))
                    .lineSpacing(1)
                    .lineLimit(hovering || selected ? 7 : 3)
                    .strikethrough(item.state == .completed)
                    .foregroundStyle(item.state == .completed ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 5) {
                    Label(item.kind.label, systemImage: item.kind.symbol)
                    if let app = item.source.appName {
                        Text("·")
                        Label(app, systemImage: "app")
                    }
                    if item.pinned {
                        Text("·")
                        Label("Pinned", systemImage: "pin.fill")
                    }
                    Spacer()
                    Text(item.createdAt, style: .relative)
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.secondary.opacity(0.88))
                .lineLimit(1)
            }

            if hovering || focused {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.055)))
                }
                .buttonStyle(.plain)
                .help("Copy")
                .accessibilityLabel("Copy item")
                .accessibilityHidden(true)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected
                    ? Color.accentColor.opacity(0.065)
                    : Color(nsColor: .textBackgroundColor).opacity(item.state == .completed ? 0.48 : 0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : (focused ? Color.primary.opacity(0.34) : Color.primary.opacity(0.075)), lineWidth: selected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .simultaneousGesture(TapGesture(count: 1).onEnded(onSelect))
        .simultaneousGesture(TapGesture(count: 2).onEnded(onEdit))
        .contextMenu { contextMenu }
        .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
        .onDrop(of: [UTType.text], delegate: WorkItemDropDelegate(onDrop: onDropBefore))
        .animation(.easeOut(duration: 0.13), value: selected)
        .animation(.easeOut(duration: 0.13), value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityActions {
            Button("Copy", action: onCopy)
            Button("Edit", action: onEdit)
            if item.state == .archived {
                Button("Restore", action: onRestore)
            } else {
                Button(item.state == .completed ? "Mark as queued" : "Mark as completed", action: onToggle)
                Button(item.pinned ? "Unpin" : "Pin", action: onPin)
                Button("Archive", action: onArchive)
            }
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Copy", action: onCopy)
        Button("Edit", action: onEdit)
        if item.state != .archived {
            Button(item.state == .completed ? "Mark as queued" : "Mark as completed", action: onToggle)
            Button(item.pinned ? "Unpin" : "Pin", action: onPin)
            Menu("Move to section") {
                ForEach(sections) { section in
                    Button(section.title) { onMove(section.id) }
                        .disabled(section.id == item.sectionID)
                }
            }
            Divider()
            Button("Archive", action: onArchive)
        } else {
            Divider()
            Button("Restore", action: onRestore)
        }
    }

    private var markdownText: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: item.body, options: options)) ?? AttributedString(item.body)
    }

    private var accessibilityLabel: String {
        var parts = [item.state.rawValue, item.kind.label, item.body]
        if let app = item.source.appName { parts.append("from \(app)") }
        if item.pinned { parts.append("pinned") }
        return parts.joined(separator: ", ")
    }
}

private struct WorkItemDropDelegate: DropDelegate {
    var onDrop: (UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String, let id = UUID(uuidString: string) else { return }
            DispatchQueue.main.async { onDrop(id) }
        }
        return true
    }
}
