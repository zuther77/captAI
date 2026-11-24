import AppKit
import SwiftUI

/// Draws and edits vector marks over the frozen capture. Coordinates are normalized to the view bounds.
struct AnnotationCanvasView: View {
    @Bindable var document: AnnotationDocument
    var onAskAboutSelection: () -> Void

    var body: some View {
        // Full-bleed canvas so normalized marks stay locked to the PNG pixels under the layer;
        // toolbar floats on top and must not shrink the hit/draw surface.
        ZStack(alignment: .bottom) {
            CanvasHost(document: document)
            toolbar
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                HoverNamedIconButton(
                    title: tool.title,
                    symbolName: tool.symbolName,
                    isActive: document.tool == tool,
                    accessibilityID: "annotation.tool.\(tool.rawValue)"
                ) {
                    document.tool = tool
                }
            }
            Divider().frame(height: 18)
            HoverNamedIconButton(
                title: "Undo",
                symbolName: "arrow.uturn.backward",
                isEnabled: document.canUndo,
                accessibilityID: "annotation.undo"
            ) {
                document.undo()
            }
            HoverNamedIconButton(
                title: "Redo",
                symbolName: "arrow.uturn.forward",
                isEnabled: document.canRedo,
                accessibilityID: "annotation.redo"
            ) {
                document.redo()
            }
            HoverNamedIconButton(
                title: "Delete",
                symbolName: "trash",
                isEnabled: document.hasSelection,
                accessibilityID: "annotation.delete"
            ) {
                document.deleteSelected()
            }
            Spacer(minLength: 4)
            Button("Ask about selection") {
                onAskAboutSelection()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(document.focusBounds == nil)
            .help("Send a follow-up about the selected mark (or all marks).")
            .accessibilityIdentifier("annotation.ask")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("annotation.toolbar")
    }
}

/// Icon control that reveals its name beside the glyph on hover (system `.help` is unreliable in the capture panel).
private struct HoverNamedIconButton: View {
    let title: String
    let symbolName: String
    var isActive = false
    var isEnabled = true
    let accessibilityID: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbolName)
                if isHovered {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 26, minHeight: 26)
            .padding(.horizontal, isHovered ? 4 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .background(isActive ? Color.accentColor.opacity(0.25) : Color.clear, in: .rect(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityID)
    }
}

/// Hit-testing canvas that maps view points into normalized annotation space.
/// Drawing tools own the drag; Select leaves empty space to AppKit so the capture window can move.
private struct CanvasHost: View {
    @Bindable var document: AnnotationDocument

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear
                ForEach(document.visibleMarks) { mark in
                    AnnotationShapeView(mark: mark, selected: mark.id == document.selectedID || mark.id == document.draft?.id)
                }
            }
            .contentShape(Rectangle())
            .gesture(document.tool.createsMark ? drawGesture(size: geo.size) : nil)
            .onTapGesture { location in
                guard document.tool == .select else { return }
                document.select(at: normalize(location, in: geo.size))
            }
        }
        .accessibilityIdentifier("annotation.canvas")
    }

    private func drawGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let point = normalize(value.location, in: size)
                if document.draft == nil {
                    document.beginStroke(at: point)
                } else {
                    document.updateStroke(to: point)
                }
            }
            .onEnded { _ in
                document.endStroke()
            }
    }

    private func normalize(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(x: point.x / size.width, y: point.y / size.height).clamped01
    }
}

private struct AnnotationShapeView: View {
    let mark: CaptureAnnotation
    let selected: Bool

    var body: some View {
        GeometryReader { geo in
            let start = denormalize(mark.start, in: geo.size)
            let end = denormalize(mark.end, in: geo.size)
            let bounds = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: max(abs(end.x - start.x), 1),
                height: max(abs(end.y - start.y), 1)
            )
            ZStack {
                switch mark.kind {
                case .highlight:
                    Rectangle()
                        .fill(Color.yellow.opacity(0.35))
                        .frame(width: bounds.width, height: bounds.height)
                        .position(x: bounds.midX, y: bounds.midY)
                    Path { $0.addRect(bounds) }
                        .stroke(color.opacity(0.8), lineWidth: selected ? 2 : 1)
                case .arrow:
                    Path { path in
                        path.move(to: start)
                        path.addLine(to: end)
                        let angle = atan2(end.y - start.y, end.x - start.x)
                        let head: CGFloat = 10
                        path.move(to: end)
                        path.addLine(to: CGPoint(
                            x: end.x - head * cos(angle - .pi / 6),
                            y: end.y - head * sin(angle - .pi / 6)
                        ))
                        path.move(to: end)
                        path.addLine(to: CGPoint(
                            x: end.x - head * cos(angle + .pi / 6),
                            y: end.y - head * sin(angle + .pi / 6)
                        ))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: selected ? 2.5 : 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var color: Color { selected ? .orange : .red }

    private func denormalize(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}
