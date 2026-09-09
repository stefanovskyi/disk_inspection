import Foundation

struct SunburstSmallerItems: Identifiable, Equatable, Sendable {
    let id: String
    let chartRootID: String
    let parent: FileNode
    let children: [FileNode]
    let size: Int64
    let itemCount: Int

    var name: String { "Smaller items" }
}

enum SunburstSegmentTarget: Equatable, Sendable {
    case node(FileNode)
    case smallerItems(SunburstSmallerItems)
}

struct SunburstSegment: Identifiable, Equatable, Sendable {
    let id: String
    let target: SunburstSegmentTarget
    let depth: Int
    let startAngle: Double
    let endAngle: Double
    let hue: Double

    var angularSpan: Double { endAngle - startAngle }
    var node: FileNode? {
        guard case .node(let node) = target else { return nil }
        return node
    }
    var smallerItems: SunburstSmallerItems? {
        guard case .smallerItems(let group) = target else { return nil }
        return group
    }
    var name: String {
        switch target {
        case .node(let node): node.name
        case .smallerItems(let group): group.name
        }
    }
    var size: Int64 {
        switch target {
        case .node(let node): node.size
        case .smallerItems(let group): group.size
        }
    }
    var itemCount: Int {
        switch target {
        case .node(let node): node.itemCount
        case .smallerItems(let group): group.itemCount
        }
    }

    init(
        node: FileNode,
        depth: Int,
        startAngle: Double,
        endAngle: Double,
        hue: Double
    ) {
        id = "\(depth):\(node.id)"
        target = .node(node)
        self.depth = depth
        self.startAngle = startAngle
        self.endAngle = endAngle
        self.hue = hue
    }

    init(
        smallerItems: SunburstSmallerItems,
        depth: Int,
        startAngle: Double,
        endAngle: Double,
        hue: Double
    ) {
        id = "\(depth):\(smallerItems.id)"
        target = .smallerItems(smallerItems)
        self.depth = depth
        self.startAngle = startAngle
        self.endAngle = endAngle
        self.hue = hue
    }
}

struct SunburstScenePolicy: Equatable, Sendable {
    let minimumRootFraction: Double
    let minimumArcLength: Double
    let maximumSegmentCount: Int

    static let interactive = SunburstScenePolicy(
        minimumRootFraction: 0.01,
        minimumArcLength: 6,
        maximumSegmentCount: 200
    )

    func minimumAngularSpan(angularExtent: Double, interactionRadius: Double) -> Double {
        let fractionFloor = max(angularExtent, 0) * max(minimumRootFraction, 0)
        let pixelFloor = interactionRadius > 0
            ? max(minimumArcLength, 0) / interactionRadius
            : 0
        return max(fractionFloor, pixelFloor)
    }
}

/// Immutable render and interaction data for one displayed scan root.
/// Build once when the root changes; hover lookup never traverses the file tree.
final class SunburstScene: @unchecked Sendable {
    let segments: [SunburstSegment]
    let ringCount: Int

    private let segmentIndicesByDepth: [[Int]]

    init(
        root: FileNode,
        maxDepth: Int = 6,
        minimumAngularSpan: Double = 0.004,
        angularExtent: Double = .pi * 2,
        maximumSegmentCount: Int = .max
    ) {
        let laidOutSegments = SunburstLayout.segments(
            for: root,
            maxDepth: maxDepth,
            minimumAngularSpan: minimumAngularSpan,
            angularExtent: angularExtent,
            groupsSmallerItems: true
        )
        let segments = Self.segments(
            from: laidOutSegments,
            limitedTo: maximumSegmentCount
        )
        self.segments = segments
        ringCount = max(1, (segments.map(\.depth).max() ?? 0) + 1)

        var buckets = Array(repeating: [Int](), count: ringCount)
        for (index, segment) in segments.enumerated() where buckets.indices.contains(segment.depth) {
            buckets[segment.depth].append(index)
        }
        for depth in buckets.indices {
            buckets[depth].sort {
                segments[$0].startAngle < segments[$1].startAngle
            }
        }
        segmentIndicesByDepth = buckets
    }

    convenience init(
        root: FileNode,
        maxDepth: Int = 6,
        angularExtent: Double,
        interactionRadius: Double,
        policy: SunburstScenePolicy
    ) {
        self.init(
            root: root,
            maxDepth: maxDepth,
            minimumAngularSpan: policy.minimumAngularSpan(
                angularExtent: angularExtent,
                interactionRadius: interactionRadius
            ),
            angularExtent: angularExtent,
            maximumSegmentCount: policy.maximumSegmentCount
        )
    }

    func segmentIndex(atDepth depth: Int, angle: Double) -> Int? {
        guard segmentIndicesByDepth.indices.contains(depth),
              angle >= 0,
              angle <= .pi * 2 else { return nil }

        let candidates = segmentIndicesByDepth[depth]
        var lowerBound = 0
        var upperBound = candidates.count
        while lowerBound < upperBound {
            let candidateOffset = lowerBound + ((upperBound - lowerBound) / 2)
            let segmentIndex = candidates[candidateOffset]
            let candidate = segments[segmentIndex]
            if angle < candidate.startAngle {
                upperBound = candidateOffset
            } else if angle > candidate.endAngle {
                lowerBound = candidateOffset + 1
            } else {
                return segmentIndex
            }
        }
        return nil
    }

    func segment(atDepth depth: Int, angle: Double) -> SunburstSegment? {
        guard let index = segmentIndex(atDepth: depth, angle: angle) else { return nil }
        return segments[index]
    }

    private static func segments(
        from candidates: [SunburstSegment],
        limitedTo maximumSegmentCount: Int
    ) -> [SunburstSegment] {
        let limit = max(maximumSegmentCount, 0)
        guard candidates.count > limit else { return candidates }
        guard limit > 0 else { return [] }

        var retained: [SunburstSegment] = []
        let maximumDepth = candidates.map(\.depth).max() ?? -1
        for depth in 0...maximumDepth {
            let depthCandidates = candidates.filter { $0.depth == depth }
            let remaining = limit - retained.count
            guard remaining > 0 else { break }
            if depthCandidates.count <= remaining {
                retained.append(contentsOf: depthCandidates)
            } else {
                retained.append(
                    contentsOf: depthCandidates
                        .sorted {
                            if $0.angularSpan == $1.angularSpan {
                                return $0.startAngle < $1.startAngle
                            }
                            return $0.angularSpan > $1.angularSpan
                        }
                        .prefix(remaining)
                )
                break
            }
        }
        return retained
    }
}

enum SunburstLayout {
    private static let hues: [Double] = [0.46, 0.53, 0.60, 0.69, 0.78, 0.88, 0.96, 0.35]

    static func hue(for identifier: String) -> Double {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in identifier.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hues[Int(hash % UInt64(hues.count))]
    }

    static func segments(
        for root: FileNode,
        maxDepth: Int = 5,
        minimumAngularSpan: Double = 0.004,
        angularExtent: Double = .pi * 2,
        groupsSmallerItems: Bool = false
    ) -> [SunburstSegment] {
        let signposter = SpaceLensSignposts.chartLayout
        let signpostState = signposter.beginInterval(
            "SunburstLayout",
            "maxDepth=\(maxDepth)"
        )
        var output: [SunburstSegment] = []
        defer {
            signposter.endInterval(
                "SunburstLayout",
                signpostState,
                "segments=\(output.count)"
            )
        }

        guard maxDepth > 0 else { return [] }
        let fullCircle = Double.pi * 2
        let visibleExtent = min(max(angularExtent, 0), fullCircle)
        guard visibleExtent > 0 else { return [] }

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
            var omittedChildren: [FileNode] = []
            var omittedStartAngle: Double?
            for child in children {
                let fraction = Double(child.size) / Double(total)
                let childEnd = min(end, cursor + ((end - start) * fraction))
                let hue = inheritedHue ?? Self.hue(for: child.id)

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
                } else if groupsSmallerItems {
                    if omittedStartAngle == nil {
                        omittedStartAngle = cursor
                    }
                    omittedChildren.append(child)
                }
                cursor = childEnd
            }

            if groupsSmallerItems,
               let omittedStartAngle,
               !omittedChildren.isEmpty,
               end - omittedStartAngle >= minimumAngularSpan {
                let size = omittedChildren.reduce(Int64(0)) { partial, child in
                    let addition = partial.addingReportingOverflow(child.size)
                    return addition.overflow ? Int64.max : addition.partialValue
                }
                let itemCount = omittedChildren.reduce(0) { partial, child in
                    let addition = partial.addingReportingOverflow(child.itemCount)
                    return addition.overflow ? Int.max : addition.partialValue
                }
                let group = SunburstSmallerItems(
                    id: "\(parent.id)#spacelens-chart-smaller-items",
                    chartRootID: root.id,
                    parent: parent,
                    children: omittedChildren,
                    size: size,
                    itemCount: itemCount
                )
                output.append(
                    SunburstSegment(
                        smallerItems: group,
                        depth: depth,
                        startAngle: omittedStartAngle,
                        endAngle: end,
                        hue: inheritedHue ?? Self.hue(for: group.id)
                    )
                )
            }
        }

        appendChildren(of: root, depth: 0, start: 0, end: visibleExtent, inheritedHue: nil)
        return output
    }
}
