import CoreGraphics
import Foundation
import Observation

/// Drawing tool for the frozen-capture toolbar.
    enum AnnotationTool: String, CaseIterable, Equatable, Sendable {
    case select
    case highlight
    case arrow

    var title: String {
        switch self {
        case .select: "Select"
        case .highlight: "Highlight"
        case .arrow: "Arrow"
        }
    }

    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .highlight: "highlighter"
        case .arrow: "arrow.up.right"
        }
    }

    var createsMark: Bool { self != .select }
}

/// Non-destructive annotation state for one workspace. Undo/redo snapshots the mark list; the PNG on disk is
/// never rewritten (plan M5).
@MainActor
@Observable
final class AnnotationDocument {
    private(set) var annotations: [CaptureAnnotation] = []
    private(set) var selectedID: UUID?
    var tool: AnnotationTool = .select

    private var undoStack: [[CaptureAnnotation]] = []
    private var redoStack: [[CaptureAnnotation]] = []
    /// In-progress drag mark (not yet committed to undo).
    private(set) var draft: CaptureAnnotation?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasSelection: Bool { selectedID != nil }
    var selected: CaptureAnnotation? {
        guard let selectedID else { return nil }
        return annotations.first { $0.id == selectedID }
    }

    // MARK: Drawing

    func beginStroke(at point: CGPoint) {
        guard tool.createsMark else {
            select(at: point)
            return
        }
        let kind: CaptureAnnotation.Kind = switch tool {
        case .highlight: .highlight
        case .arrow: .arrow
        case .select: .highlight
        }
        draft = CaptureAnnotation(kind: kind, start: point, end: point)
        selectedID = draft?.id
    }

    func updateStroke(to point: CGPoint) {
        guard var draft else { return }
        draft.end = point.clamped01
        self.draft = draft
    }

    func endStroke() {
        guard let draft else { return }
        pushUndo()
        annotations.append(draft)
        selectedID = draft.id
        self.draft = nil
        redoStack.removeAll()
    }

    func cancelStroke() {
        draft = nil
    }

    // MARK: Selection / edit

    func select(at point: CGPoint) {
        // Topmost mark whose bounds contain the point (with a little hit padding).
        let pad: CGFloat = 0.02
        selectedID = annotations.reversed().first { mark in
            mark.normalizedBounds.insetBy(dx: -pad, dy: -pad).contains(point)
        }?.id
    }

    func deleteSelected() {
        guard let selectedID, annotations.contains(where: { $0.id == selectedID }) else { return }
        pushUndo()
        annotations.removeAll { $0.id == selectedID }
        self.selectedID = nil
        redoStack.removeAll()
    }

    func clearSelection() {
        selectedID = nil
    }

    // MARK: Undo / redo

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        if let selectedID, !annotations.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    private func pushUndo() {
        undoStack.append(annotations)
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    // MARK: Context for chat

    /// Marks currently visible, including an in-progress draft.
    var visibleMarks: [CaptureAnnotation] {
        if let draft { annotations + [draft] } else { annotations }
    }

    /// Union of selected mark bounds, or all marks if none selected.
    var focusBounds: CGRect? {
        let marks: [CaptureAnnotation]
        if let selected { marks = [selected] }
        else { marks = annotations }
        guard let first = marks.first else { return nil }
        return marks.dropFirst().reduce(first.normalizedBounds) { $0.union($1.normalizedBounds) }.clamped01
    }

    /// Text appended to a follow-up so providers see which regions the user marked.
    func promptAppendix() -> String {
        let marks = annotations
        guard !marks.isEmpty else { return "" }
        let lines = marks.enumerated().map { index, mark in
            let b = mark.normalizedBounds
            let selected = mark.id == selectedID ? " (selected)" : ""
            return "\(index + 1). \(mark.kind.rawValue)\(selected): x=\(fmt(b.minX)) y=\(fmt(b.minY)) w=\(fmt(b.width)) h=\(fmt(b.height))"
        }
        return "The user marked these regions on the screenshot (normalized 0…1, top-left origin):\n" + lines.joined(separator: "\n")
    }

    private func fmt(_ value: CGFloat) -> String {
        String(format: "%.3f", Double(value))
    }
}
