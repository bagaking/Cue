import AppKit
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
    private let tongueWidth: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ZStack {
                    VisualEffectBackground(material: .popover)
                    Color(nsColor: .windowBackgroundColor).opacity(opaque ? 1 : 0.78)
                }

                VStack(spacing: 8) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .renderingMode(.original)
                        .interpolation(.high)
                        .frame(width: 15, height: 15)
                        .accessibilityHidden(true)

                    if queuedCount > 0 {
                        Text(countText)
                            .font(.system(size: queuedCount > 99 ? 6 : 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(Color.accentColor))
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(width: tongueWidth, height: geometry.size.height)
            .clipShape(EdgeTabShape(edge: edge, radius: 8))
            .position(
                x: edge == .left ? tongueWidth / 2 : geometry.size.width - tongueWidth / 2,
                y: geometry.size.height / 2
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

private struct EdgeTabShape: Shape {
    var edge: PanelEdge
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, rect.width, rect.height / 2)
        let control = radius * 0.552_284_75
        var path = Path()

        switch edge {
        case .left:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control1: CGPoint(x: rect.maxX - radius + control, y: rect.minY),
                control2: CGPoint(x: rect.maxX, y: rect.minY + radius - control)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control1: CGPoint(x: rect.maxX, y: rect.maxY - radius + control),
                control2: CGPoint(x: rect.maxX - radius + control, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .right:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.minY + radius),
                control1: CGPoint(x: rect.minX + radius - control, y: rect.minY),
                control2: CGPoint(x: rect.minX, y: rect.minY + radius - control)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
            path.addCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.maxY),
                control1: CGPoint(x: rect.minX, y: rect.maxY - radius + control),
                control2: CGPoint(x: rect.minX + radius - control, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
