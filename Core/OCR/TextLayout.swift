import CoreGraphics

/// One piece of recognized text. `normalizedBox` is in 0...1 with a bottom-left origin, which is what Vision
/// reports, so it does not depend on the image's pixel size.
struct TextObservation: Equatable, Sendable {
    let text: String
    let normalizedBox: CGRect
    let confidence: Float

    /// The box in image pixels with a top-left origin, for drawing or for comparing with the capture.
    func pixelBox(in imageSize: CGSize) -> CGRect {
        CGRect(
            x: normalizedBox.minX * imageSize.width,
            y: (1 - normalizedBox.maxY) * imageSize.height,
            width: normalizedBox.width * imageSize.width,
            height: normalizedBox.height * imageSize.height
        )
    }
}

/// Turns recognized fragments into plain text in reading order: top to bottom, left to right, with line
/// breaks kept and indentation approximated from horizontal position.
///
/// Works in image pixels, so the spacing thresholds mean the same thing on wide and tall images. Pure and
/// deterministic, so the layout rules can be tested without Vision.
enum ReadingOrder {
    /// Two fragments belong to the same line when their vertical extents overlap by at least this share of the
    /// shorter one.
    static let sameLineOverlap: CGFloat = 0.5
    /// A horizontal gap wider than this many line heights is shown as a tab, so columns stay apart.
    static let tabGapFactor: CGFloat = 1.5
    /// Approximate width of one indentation step, as a share of a line's height.
    static let indentStepFactor: CGFloat = 0.5
    static let maxIndentSpaces = 40

    /// A fragment in image pixels with a top-left origin.
    struct Fragment: Equatable {
        let text: String
        let box: CGRect
    }

    static func text(from observations: [TextObservation], imageSize: CGSize) -> String {
        let fragments = observations.map { Fragment(text: $0.text, box: $0.pixelBox(in: imageSize)) }
        return text(from: fragments)
    }

    static func text(from fragments: [Fragment]) -> String {
        let kept = removeDuplicates(fragments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        guard !kept.isEmpty else { return "" }

        // Group into lines. Each line keeps the union of its fragments' boxes.
        var lines: [(fragments: [Fragment], box: CGRect)] = []
        for item in kept.sorted(by: topDownThenLeft) {
            if let index = lines.firstIndex(where: { sameLine($0.box, item.box) }) {
                lines[index].fragments.append(item)
                lines[index].box = lines[index].box.union(item.box)
            } else {
                lines.append((fragments: [item], box: item.box))
            }
        }
        // Top of the image first. In top-left pixel coordinates a smaller minY is higher.
        lines.sort { $0.box.minY < $1.box.minY }

        let leftEdge = lines.map(\.box.minX).min() ?? 0
        return lines.map { line in
            let ordered = line.fragments.sorted { $0.box.minX < $1.box.minX }
            let indent = indentation(for: line.box, leftEdge: leftEdge)
            return String(repeating: " ", count: indent) + join(ordered)
        }.joined(separator: "\n")
    }

    /// Drops a fragment when an earlier one has the same text and nearly the same box. Vision sometimes reports
    /// one line twice; the same text in a different place is kept.
    private static func removeDuplicates(_ fragments: [Fragment]) -> [Fragment] {
        var kept: [Fragment] = []
        for item in fragments {
            let duplicate = kept.contains { other in
                other.text == item.text && overlapRatio(other.box, item.box) > 0.9
            }
            if !duplicate { kept.append(item) }
        }
        return kept
    }

    private static func topDownThenLeft(_ a: Fragment, _ b: Fragment) -> Bool {
        if a.box.midY != b.box.midY { return a.box.midY < b.box.midY }
        return a.box.minX < b.box.minX
    }

    private static func sameLine(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        guard overlap > 0 else { return false }
        return overlap >= sameLineOverlap * min(a.height, b.height)
    }

    /// Intersection over union, in 0...1.
    private static func overlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let inter = intersection.width * intersection.height
        let union = a.width * a.height + b.width * b.height - inter
        return union > 0 ? inter / union : 0
    }

    private static func join(_ fragments: [Fragment]) -> String {
        var result = ""
        var previous: CGRect?
        for fragment in fragments {
            let text = fragment.text.trimmingCharacters(in: .whitespaces)
            if let previous {
                let gap = fragment.box.minX - previous.maxX
                let height = max(previous.height, fragment.box.height)
                result += gap > tabGapFactor * height ? "\t" : " "
            }
            result += text
            previous = fragment.box
        }
        return result
    }

    private static func indentation(for line: CGRect, leftEdge: CGFloat) -> Int {
        let step = max(line.height, 1) * indentStepFactor
        let spaces = Int(((line.minX - leftEdge) / step).rounded())
        return min(max(spaces, 0), maxIndentSpaces)
    }
}
