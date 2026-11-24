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
                Button {
                    document.tool = tool
                } label: {
                    Image(systemName: tool.symbolName)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .background(document.tool == tool ? Color.accentColor.opacity(0.25) : Color.clear, in: .rect(cornerRadius: 6))
                .help(tool.title)
                .accessibilityLabel(tool.title)
                .accessibilityIdentifier("annotation.tool.\(tool.rawValue)")
            }
            Divider().frame(height: 18)
            Button {
                document.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .disabled(!document.canUndo)
            .help("Undo")
            .accessibilityIdentifier("annotation.undo")
            Button {
                document.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward").frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .disabled(!document.canRedo)
            .help("Redo")
            .accessibilityIdentifier("annotation.redo")
            Button {
                document.deleteSelected()
            } label: {
                Image(systemName: "trash").frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .disabled(!document.hasSelection)
            .help("Delete selected mark")
            .accessibilityIdentifier("annotation.delete")
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

/// Hit-testing canvas that maps view points into normalized annotation space.
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
            .gesture(
                DragGesture(minimumDistance: document.tool.createsMark ? 1 : 0)
                    .onChanged { value in
                        guard document.tool.createsMark else { return }
                        let point = normalize(value.location, in: geo.size)
                        if document.draft == nil {
                            document.beginStroke(at: point)
                        } else {
                            document.updateStroke(to: point)
                        }
                    }
                    .onEnded { value in
                        if document.tool.createsMark {
                            document.endStroke()
                        } else if abs(value.translation.width) < 4, abs(value.translation.height) < 4 {
                            document.select(at: normalize(value.location, in: geo.size))
                        }
                    }
            )
        }
        .accessibilityIdentifier("annotation.canvas")
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
                case .rectangle:
                    Path { $0.addRect(bounds) }
                        .stroke(color, style: StrokeStyle(lineWidth: selected ? 2.5 : 2))
                case .highlight:
                    Rectangle()
                        .fill(Color.yellow.opacity(0.35))
                        .frame(width: bounds.width, height: bounds.height)
                        .position(x: bounds.midX, y: bounds.midY)
                    Path { $0.addRect(bounds) }
                        .stroke(color.opacity(0.8), lineWidth: selected ? 2 : 1)
                case .circle:
                    Path { path in
                        path.addEllipse(in: bounds)
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: selected ? 2.5 : 2))
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
