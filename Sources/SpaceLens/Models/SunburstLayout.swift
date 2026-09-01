import Foundation

struct SunburstSegment: Identifiable, Equatable {
    let node: FileNode
    let depth: Int
    let startAngle: Double
    let endAngle: Double
    let hue: Double

    var id: String { "\(depth):\(node.id)" }
    var angularSpan: Double { endAngle - startAngle }
}

enum SunburstLayout {
    private static let hues: [Double] = [0.43, 0.50, 0.58, 0.72, 0.88, 0.98, 0.08, 0.18]

    static func segments(
        for root: FileNode,
        maxDepth: Int = 5,
        minimumAngularSpan: Double = 0.004
    ) -> [SunburstSegment] {
        guard maxDepth > 0 else { return [] }
        var output: [SunburstSegment] = []
        let fullCircle = Double.pi * 2

        func appendChildren(
            of parent: FileNode,
            depth: Int,
            start: Double,
            end: Double,
            inheritedHue: Double?
        ) {
            guard depth < maxDepth else { return }
            let children = parent.sortedChildren.filter { $0.size > 0 }
            let total = children.reduce(Int64(0)) { partial, child in
                let addition = partial.addingReportingOverflow(child.size)
                return addition.overflow ? Int64.max : addition.partialValue
            }
            guard total > 0 else { return }

            var cursor = start
            for (index, child) in children.enumerated() {
                let fraction = Double(child.size) / Double(total)
                let childEnd = min(end, cursor + ((end - start) * fraction))
                let hue = inheritedHue ?? hues[index % hues.count]

                if childEnd - cursor >= minimumAngularSpan {
                    output.append(
                        SunburstSegment(
                            node: child,
                            depth: depth,
                            startAngle: cursor,
                            endAngle: childEnd,
                            hue: hue
                        )
                    )
                    appendChildren(
                        of: child,
                        depth: depth + 1,
                        start: cursor,
                        end: childEnd,
                        inheritedHue: hue
                    )
                }
                cursor = childEnd
            }
        }

        appendChildren(of: root, depth: 0, start: 0, end: fullCircle, inheritedHue: nil)
        return output
    }
}
