import SwiftUI

@MainActor
final class PanelChromeModel: ObservableObject {
    @Published var state: PanelPresentationState = .hidden
    var onExplicitReveal: (() -> Void)?

    var isRetracted: Bool {
        if case .retracted = state { return true }
        return false
    }

    var edge: PanelEdge {
        if case let .retracted(edge) = state { return edge }
        return .right
    }
}

/// Both children stay mounted so retract/reveal preserves Sidecar @State,
/// selection, scrolling and composer draft. The compact panel clips the hidden
/// Sidecar and removes it from hit testing and Accessibility while retracted.
struct PanelRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var chrome: PanelChromeModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SidecarView(model: model)
                    .frame(
                        width: max(PanelGeometryPolicy.minimumExpandedSize.width, geometry.size.width),
                        height: max(PanelGeometryPolicy.minimumExpandedSize.height, geometry.size.height)
                    )
                    .opacity(chrome.isRetracted ? 0 : 1)
                    .allowsHitTesting(!chrome.isRetracted)
                    .accessibilityHidden(chrome.isRetracted)

                Button(action: { chrome.onExplicitReveal?() }) {
                    EdgeRailView(
                        edge: chrome.edge,
                        queuedCount: model.queuedCount,
                        opaque: reduceTransparency || model.settings.reduceTranslucency
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .buttonStyle(.plain)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .opacity(chrome.isRetracted ? 1 : 0)
                .allowsHitTesting(chrome.isRetracted)
                .accessibilityHidden(!chrome.isRetracted)
                .accessibilityLabel("Reveal Cue")
                .accessibilityValue(model.queuedCount == 0 ? "No queued items" : (model.queuedCount == 1 ? "1 queued item" : "\(model.queuedCount) queued items"))
                .accessibilityHint("Shows the Cue panel without changing the queue")
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct EdgeRailView: View {
    var edge: PanelEdge
    var queuedCount: Int
    var opaque: Bool

    private var countText: String { queuedCount > 99 ? "99+" : "\(queuedCount)" }

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: edge == .left ? "chevron.right" : "chevron.left")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.secondary)

            if queuedCount > 0 {
                Text(countText)
                    .font(.system(size: queuedCount > 99 ? 7 : 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(Color.green))
                    .accessibilityLabel(queuedCount == 1 ? "1 queued item" : "\(queuedCount) queued items")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                VisualEffectBackground(material: .popover)
                Color(nsColor: .windowBackgroundColor).opacity(opaque ? 0.98 : 0.78)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
