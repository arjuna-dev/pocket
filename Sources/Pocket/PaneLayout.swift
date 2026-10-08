import CoreGraphics
import Foundation

struct LayoutFootprint: Equatable {
    var width: CGFloat
    var height: CGFloat

    static let single = LayoutFootprint(width: 1, height: 1)
}

enum SplitAxis: String, Codable, Equatable {
    case horizontal
    case vertical
}

enum PaneEdge: String, Codable, Equatable {
    case top
    case bottom
    case leading
    case trailing
}

struct GridSpan: Equatable {
    var rows: Int
    var columns: Int

    static let single = GridSpan(rows: 1, columns: 1)
}

enum PaneNode: Equatable, Codable {
    case empty
    case leaf(Int)
    indirect case split(axis: SplitAxis, ratio: Double, first: PaneNode, second: PaneNode)

    private enum CodingKeys: String, CodingKey {
        case empty
        case leaf
        case axis
        case ratio
        case first
        case second
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.empty) {
            self = .empty
            return
        }
        if let id = try container.decodeIfPresent(Int.self, forKey: .leaf) {
            self = .leaf(id)
            return
        }
        self = .split(
            axis: try container.decode(SplitAxis.self, forKey: .axis),
            ratio: try container.decode(Double.self, forKey: .ratio),
            first: try container.decode(PaneNode.self, forKey: .first),
            second: try container.decode(PaneNode.self, forKey: .second)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .empty:
            try container.encode(true, forKey: .empty)
        case .leaf(let id):
            try container.encode(id, forKey: .leaf)
        case .split(let axis, let ratio, let first, let second):
            try container.encode(axis, forKey: .axis)
            try container.encode(ratio, forKey: .ratio)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        }
    }

    var leafIDs: [Int] {
        switch self {
        case .empty:
            return []
        case .leaf(let id):
            return [id]
        case .split(_, _, let first, let second):
            return first.leafIDs + second.leafIDs
        }
    }

    var hasEmpty: Bool {
        switch self {
        case .empty:
            return true
        case .leaf:
            return false
        case .split(_, _, let first, let second):
            return first.hasEmpty || second.hasEmpty
        }
    }

    var isCell: Bool {
        switch self {
        case .leaf, .empty:
            return true
        case .split:
            return false
        }
    }

    /// An empty cell, or a split made only of empty cells.
    var isVacant: Bool {
        switch self {
        case .empty:
            return true
        case .leaf:
            return false
        case .split(_, _, let first, let second):
            return first.isVacant && second.isVacant
        }
    }

    func contains(_ id: Int) -> Bool {
        leafIDs.contains(id)
    }

    func removing(_ id: Int) -> PaneNode? {
        switch self {
        case .empty:
            return self
        case .leaf(let leaf):
            return leaf == id ? nil : self
        case .split(let axis, let ratio, let first, let second):
            if first.contains(id) {
                guard let next = first.removing(id) else { return second.isVacant ? nil : second }
                return .split(axis: axis, ratio: ratio, first: next, second: second)
            }
            if second.contains(id) {
                guard let next = second.removing(id) else { return first.isVacant ? nil : first }
                return .split(axis: axis, ratio: ratio, first: first, second: next)
            }
            return self
        }
    }

    func replacing(_ id: Int, with replacement: PaneNode) -> PaneNode {
        switch self {
        case .empty:
            return self
        case .leaf(let leaf):
            return leaf == id ? replacement : self
        case .split(let axis, let ratio, let first, let second):
            return .split(
                axis: axis,
                ratio: ratio,
                first: first.replacing(id, with: replacement),
                second: second.replacing(id, with: replacement)
            )
        }
    }

    func replacingEmpty(with replacement: PaneNode) -> PaneNode {
        switch self {
        case .empty:
            return replacement
        case .leaf:
            return self
        case .split(let axis, let ratio, let first, let second):
            if first.hasEmpty {
                return .split(
                    axis: axis,
                    ratio: ratio,
                    first: first.replacingEmpty(with: replacement),
                    second: second
                )
            }
            return .split(
                axis: axis,
                ratio: ratio,
                first: first,
                second: second.replacingEmpty(with: replacement)
            )
        }
    }

    func settingRatio(_ ratio: Double, at path: [Bool]) -> PaneNode {
        guard case .split(let axis, let current, let first, let second) = self else { return self }
        if path.isEmpty {
            return .split(axis: axis, ratio: ratio, first: first, second: second)
        }
        if path[0] {
            return .split(
                axis: axis,
                ratio: current,
                first: first,
                second: second.settingRatio(ratio, at: Array(path.dropFirst()))
            )
        }
        return .split(
            axis: axis,
            ratio: current,
            first: first.settingRatio(ratio, at: Array(path.dropFirst())),
            second: second
        )
    }

    func node(at path: [Bool]) -> PaneNode? {
        guard let step = path.first else { return self }
        guard case .split(_, _, let first, let second) = self else { return nil }
        return (step ? second : first).node(at: Array(path.dropFirst()))
    }

    func replacingNode(at path: [Bool], with replacement: PaneNode) -> PaneNode {
        guard let step = path.first else { return replacement }
        guard case .split(let axis, let ratio, let first, let second) = self else { return self }
        if step {
            return .split(
                axis: axis,
                ratio: ratio,
                first: first,
                second: second.replacingNode(at: Array(path.dropFirst()), with: replacement)
            )
        }
        return .split(
            axis: axis,
            ratio: ratio,
            first: first.replacingNode(at: Array(path.dropFirst()), with: replacement),
            second: second
        )
    }

    /// A straight seam across two rows or two columns becomes a seam that
    /// belongs only to the row or column under the pointer.
    func isolatingSeam(ratio newRatio: Double, cross: CGFloat, bounds: CGRect) -> PaneNode? {
        guard case .split(let axis, let through, let first, let second) = self else { return nil }
        switch axis {
        case .vertical:
            guard case .split(axis: .horizontal, ratio: let leftRatio, first: let topLeft, second: let bottomLeft) = first,
                  case .split(axis: .horizontal, ratio: let rightRatio, first: let topRight, second: let bottomRight) = second,
                  topLeft.isCell, bottomLeft.isCell, topRight.isCell, bottomRight.isCell,
                  abs(leftRatio - rightRatio) < 0.02
            else { return nil }
            let boundary = bounds.minY + bounds.height * CGFloat(leftRatio)
            let grabbingTop = cross < boundary
            let top = PaneNode.split(
                axis: .vertical,
                ratio: grabbingTop ? newRatio : through,
                first: topLeft,
                second: topRight
            )
            let bottom = PaneNode.split(
                axis: .vertical,
                ratio: grabbingTop ? through : newRatio,
                first: bottomLeft,
                second: bottomRight
            )
            return .split(axis: .horizontal, ratio: leftRatio, first: top, second: bottom)
        case .horizontal:
            guard case .split(axis: .vertical, ratio: let topRatio, first: let topLeft, second: let topRight) = first,
                  case .split(axis: .vertical, ratio: let bottomRatio, first: let bottomLeft, second: let bottomRight) = second,
                  topLeft.isCell, bottomLeft.isCell, topRight.isCell, bottomRight.isCell,
                  abs(topRatio - bottomRatio) < 0.02
            else { return nil }
            let boundary = bounds.minX + bounds.width * CGFloat(topRatio)
            let grabbingLeading = cross < boundary
            let leading = PaneNode.split(
                axis: .horizontal,
                ratio: grabbingLeading ? newRatio : through,
                first: topLeft,
                second: bottomLeft
            )
            let trailing = PaneNode.split(
                axis: .horizontal,
                ratio: grabbingLeading ? through : newRatio,
                first: topRight,
                second: bottomRight
            )
            return .split(axis: .vertical, ratio: topRatio, first: leading, second: trailing)
        }
    }

    /// Drops an empty cell on the far side of this seam so the pane beside it
    /// can take that whole edge.
    func absorbingEmpty(toward edge: PaneEdge) -> PaneNode? {
        guard case .split(let axis, _, let first, let second) = self else { return nil }
        switch (axis, edge) {
        case (.horizontal, .bottom) where second == .empty && first.isCell:
            return first
        case (.horizontal, .top) where first == .empty && second.isCell:
            return second
        case (.vertical, .trailing) where second == .empty && first.isCell:
            return first
        case (.vertical, .leading) where first == .empty && second.isCell:
            return second
        default:
            return nil
        }
    }

    /// After a seam is pushed to the end of its track, drop the empty cell
    /// that was pinched shut.
    func absorbingPinchedEmpty() -> PaneNode? {
        switch self {
        case .leaf, .empty:
            return nil
        case .split(let axis, let ratio, let first, let second):
            if ratio >= 0.999, second == .empty, first.isCell {
                return first
            }
            if ratio <= 0.001, first == .empty, second.isCell {
                return second
            }
            if let leading = first.absorbingPinchedEmpty() {
                return .split(axis: axis, ratio: ratio, first: leading, second: second)
            }
            if let trailing = second.absorbingPinchedEmpty() {
                return .split(axis: axis, ratio: ratio, first: first, second: trailing)
            }
            return nil
        }
    }

    /// Partition uses negative ids for empty cells. Turn those back into gaps.
    func replacingPlaceholderLeaves() -> PaneNode {
        switch self {
        case .leaf(let id) where id < 0:
            return .empty
        case .split(let axis, let ratio, let first, let second):
            return .split(
                axis: axis,
                ratio: ratio,
                first: first.replacingPlaceholderLeaves(),
                second: second.replacingPlaceholderLeaves()
            )
        default:
            return self
        }
    }

    var footprint: LayoutFootprint {
        switch self {
        case .leaf, .empty:
            return .single
        case .split(let axis, _, let first, let second):
            let leading = first.footprint
            let trailing = second.footprint
            switch axis {
            case .vertical:
                return LayoutFootprint(
                    width: leading.width + trailing.width,
                    height: max(leading.height, trailing.height)
                )
            case .horizontal:
                return LayoutFootprint(
                    width: max(leading.width, trailing.width),
                    height: leading.height + trailing.height
                )
            }
        }
    }

    /// Rows stack on horizontal splits. Columns stack on vertical splits.
    var gridSpan: GridSpan {
        switch self {
        case .leaf, .empty:
            return .single
        case .split(let axis, _, let first, let second):
            let leading = first.gridSpan
            let trailing = second.gridSpan
            switch axis {
            case .horizontal:
                return GridSpan(
                    rows: leading.rows + trailing.rows,
                    columns: max(leading.columns, trailing.columns)
                )
            case .vertical:
                return GridSpan(
                    rows: max(leading.rows, trailing.rows),
                    columns: leading.columns + trailing.columns
                )
            }
        }
    }

    func clamped(maxRows: Int, maxColumns: Int) -> PaneNode {
        switch self {
        case .leaf, .empty:
            return self
        case .split(let axis, let ratio, let first, let second):
            let leading = first.clamped(maxRows: maxRows, maxColumns: maxColumns)
            let trailing = second.clamped(maxRows: maxRows, maxColumns: maxColumns)
            let combined = PaneNode.split(axis: axis, ratio: ratio, first: leading, second: trailing)
            let span = combined.gridSpan
            guard span.rows <= maxRows, span.columns <= maxColumns else {
                return leading.leafIDs.count >= trailing.leafIDs.count ? leading : trailing
            }
            return combined
        }
    }
}

struct PaneDivider: Equatable, Identifiable {
    var path: [Bool]
    var axis: SplitAxis
    var bounds: CGRect
    var ratio: Double

    var id: String {
        let route = path.map { $0 ? "1" : "0" }.joined(separator: ".")
        return "\(route)|\(axis.rawValue)"
    }

    var splitPosition: CGFloat {
        switch axis {
        case .horizontal:
            return bounds.minY + bounds.height * CGFloat(ratio)
        case .vertical:
            return bounds.minX + bounds.width * CGFloat(ratio)
        }
    }

    var hitRect: CGRect {
        let thickness: CGFloat = 18
        switch axis {
        case .horizontal:
            return CGRect(
                x: bounds.minX,
                y: splitPosition - thickness / 2,
                width: bounds.width,
                height: thickness
            )
        case .vertical:
            return CGRect(
                x: splitPosition - thickness / 2,
                y: bounds.minY,
                width: thickness,
                height: bounds.height
            )
        }
    }

    var lineRect: CGRect {
        switch axis {
        case .horizontal:
            return CGRect(x: bounds.minX, y: splitPosition - 0.5, width: bounds.width, height: 1)
        case .vertical:
            return CGRect(x: splitPosition - 0.5, y: bounds.minY, width: 1, height: bounds.height)
        }
    }
}

struct GapStrip: Equatable, Identifiable {
    var rect: CGRect
    var edge: PaneEdge

    var id: String {
        "\(edge.rawValue)|\(Int(rect.minX.rounded()))|\(Int(rect.minY.rounded()))|\(Int(rect.width.rounded()))|\(Int(rect.height.rounded()))"
    }

    var help: String {
        switch edge {
        case .bottom: return "Add a screen below"
        case .top: return "Add a screen above"
        case .trailing: return "Add a screen to the right"
        case .leading: return "Add a screen to the left"
        }
    }

    static func strips(around gap: CGRect, frames: [Int: CGRect]) -> [GapStrip] {
        let thickness = min(CGFloat(22), min(gap.width, gap.height))
        guard thickness > 8 else { return [] }

        func overlapsX(_ frame: CGRect) -> Bool {
            frame.maxX > gap.minX + 1 && frame.minX < gap.maxX - 1
        }
        func overlapsY(_ frame: CGRect) -> Bool {
            frame.maxY > gap.minY + 1 && frame.minY < gap.maxY - 1
        }

        let above = frames.values.contains { abs($0.maxY - gap.minY) < 1.5 && overlapsX($0) }
        let below = frames.values.contains { abs($0.minY - gap.maxY) < 1.5 && overlapsX($0) }
        let leading = frames.values.contains { abs($0.maxX - gap.minX) < 1.5 && overlapsY($0) }
        let trailing = frames.values.contains { abs($0.minX - gap.maxX) < 1.5 && overlapsY($0) }
        var strips: [GapStrip] = []

        let topBand = above ? thickness : 0
        let bottomBand = below ? thickness : 0
        if above {
            strips.append(GapStrip(
                rect: CGRect(x: gap.minX, y: gap.minY, width: gap.width, height: thickness),
                edge: .bottom
            ))
        }
        if below {
            strips.append(GapStrip(
                rect: CGRect(x: gap.minX, y: gap.maxY - thickness, width: gap.width, height: thickness),
                edge: .top
            ))
        }
        if leading, gap.height - topBand - bottomBand > 8 {
            strips.append(GapStrip(
                rect: CGRect(
                    x: gap.minX,
                    y: gap.minY + topBand,
                    width: thickness,
                    height: gap.height - topBand - bottomBand
                ),
                edge: .trailing
            ))
        }
        if trailing, gap.height - topBand - bottomBand > 8 {
            strips.append(GapStrip(
                rect: CGRect(
                    x: gap.maxX - thickness,
                    y: gap.minY + topBand,
                    width: thickness,
                    height: gap.height - topBand - bottomBand
                ),
                edge: .leading
            ))
        }
        return strips
    }
}

struct PaneLayout: Equatable, Codable {
    static let maxLeaves = 4
    static let maxRows = 2
    static let maxColumns = 2

    var root: PaneNode

    init(root: PaneNode) {
        self.root = root
    }

    static let single = PaneLayout(root: .leaf(0))

    var leafIDs: [Int] { root.leafIDs }
    var leafCount: Int { leafIDs.count }
    var footprint: LayoutFootprint { root.footprint }

    static func migrated(fromScreenCount count: Int) -> PaneLayout {
        switch count {
        case 2:
            return PaneLayout(root: .split(axis: .horizontal, ratio: 0.5, first: .leaf(0), second: .leaf(1)))
        case 3:
            return PaneLayout(root: .split(
                axis: .horizontal,
                ratio: 0.5,
                first: .leaf(0),
                second: .split(axis: .vertical, ratio: 0.5, first: .leaf(1), second: .leaf(2))
            ))
        case 4:
            return PaneLayout(root: .split(
                axis: .horizontal,
                ratio: 0.5,
                first: .split(axis: .vertical, ratio: 0.5, first: .leaf(0), second: .leaf(2)),
                second: .split(axis: .vertical, ratio: 0.5, first: .leaf(1), second: .leaf(3))
            ))
        default:
            return .single
        }
    }

    func sanitized(maxLeaves: Int = PaneLayout.maxLeaves) -> PaneLayout {
        var seen = Set<Int>()
        guard let root = root.sanitized(maxLeaves: maxLeaves, seen: &seen), !seen.isEmpty else {
            return .single
        }
        return PaneLayout(root: root.clamped(maxRows: PaneLayout.maxRows, maxColumns: PaneLayout.maxColumns))
    }

    func frames(in size: CGSize) -> [Int: CGRect] {
        guard size.width > 1, size.height > 1 else { return [:] }
        var frames: [Int: CGRect] = [:]
        root.collectFrames(in: CGRect(origin: .zero, size: size), into: &frames)
        return frames
    }

    func dividers(in size: CGSize) -> [PaneDivider] {
        guard size.width > 1, size.height > 1 else { return [] }
        var dividers: [PaneDivider] = []
        root.collectDividers(in: CGRect(origin: .zero, size: size), path: [], into: &dividers)
        return dividers
    }

    func leafID(at point: CGPoint, in size: CGSize) -> Int? {
        frames(in: size).first { $0.value.contains(point) }?.key
    }

    func splitting(_ id: Int, at edge: PaneEdge, newLeaf: Int) -> PaneLayout? {
        guard leafCount < PaneLayout.maxLeaves, root.contains(id), !root.contains(newLeaf) else { return nil }
        if let opened = openedBeside(id, edge: edge, newLeaf: newLeaf) {
            return opened
        }
        let replacement: PaneNode
        switch edge {
        case .top:
            replacement = .split(axis: .horizontal, ratio: 0.5, first: .leaf(newLeaf), second: .leaf(id))
        case .bottom:
            replacement = .split(axis: .horizontal, ratio: 0.5, first: .leaf(id), second: .leaf(newLeaf))
        case .leading:
            replacement = .split(axis: .vertical, ratio: 0.5, first: .leaf(newLeaf), second: .leaf(id))
        case .trailing:
            replacement = .split(axis: .vertical, ratio: 0.5, first: .leaf(id), second: .leaf(newLeaf))
        }
        let next = PaneLayout(root: root.replacing(id, with: replacement))
        let span = next.root.gridSpan
        guard span.rows <= PaneLayout.maxRows, span.columns <= PaneLayout.maxColumns else { return nil }
        return next
    }

    /// Adds the missing cell when one screen in a full row or column gains a
    /// neighbor. The other screen stays as it is, and the opposite cell stays
    /// empty so it can be filled later.
    private func openedBeside(_ id: Int, edge: PaneEdge, newLeaf: Int) -> PaneLayout? {
        let root: PaneNode?
        switch edge {
        case .top, .bottom:
            root = openedRow(beside: id, edge: edge, newLeaf: newLeaf)
        case .leading, .trailing:
            root = openedColumn(beside: id, edge: edge, newLeaf: newLeaf)
        }
        guard let root else { return nil }
        let layout = PaneLayout(root: root)
        let span = layout.root.gridSpan
        guard span.rows <= PaneLayout.maxRows, span.columns <= PaneLayout.maxColumns else { return nil }
        return layout
    }

    private func openedRow(beside id: Int, edge: PaneEdge, newLeaf: Int) -> PaneNode? {
        guard root.gridSpan.rows == 1,
              root.gridSpan.columns == 2,
              case .split(axis: .vertical, ratio: let ratio, first: .leaf(let leading), second: .leaf(let trailing)) = root,
              id == leading || id == trailing
        else { return nil }

        let row = PaneNode.split(axis: .vertical, ratio: ratio, first: .leaf(leading), second: .leaf(trailing))
        let addedLeading: PaneNode = id == leading ? .leaf(newLeaf) : .empty
        let addedTrailing: PaneNode = id == trailing ? .leaf(newLeaf) : .empty
        let added = PaneNode.split(axis: .vertical, ratio: ratio, first: addedLeading, second: addedTrailing)
        return edge == .bottom
            ? .split(axis: .horizontal, ratio: 0.5, first: row, second: added)
            : .split(axis: .horizontal, ratio: 0.5, first: added, second: row)
    }

    private func openedColumn(beside id: Int, edge: PaneEdge, newLeaf: Int) -> PaneNode? {
        guard root.gridSpan.columns == 1,
              root.gridSpan.rows == 2,
              case .split(axis: .horizontal, ratio: let ratio, first: .leaf(let top), second: .leaf(let bottom)) = root,
              id == top || id == bottom
        else { return nil }

        let column = PaneNode.split(axis: .horizontal, ratio: ratio, first: .leaf(top), second: .leaf(bottom))
        let addedTop: PaneNode = id == top ? .leaf(newLeaf) : .empty
        let addedBottom: PaneNode = id == bottom ? .leaf(newLeaf) : .empty
        let added = PaneNode.split(axis: .horizontal, ratio: ratio, first: addedTop, second: addedBottom)
        return edge == .trailing
            ? .split(axis: .vertical, ratio: 0.5, first: column, second: added)
            : .split(axis: .vertical, ratio: 0.5, first: added, second: column)
    }

    func fillingEmpty(with newLeaf: Int) -> PaneLayout? {
        guard root.hasEmpty, leafCount < PaneLayout.maxLeaves, !root.contains(newLeaf) else { return nil }
        return PaneLayout(root: root.replacingEmpty(with: .leaf(newLeaf)))
    }

    func gaps(in size: CGSize) -> [CGRect] {
        guard size.width > 1, size.height > 1 else { return [] }
        var gaps: [CGRect] = []
        root.collectGaps(in: CGRect(origin: .zero, size: size), into: &gaps)
        return gaps
    }

    func gapStrips(in size: CGSize) -> [GapStrip] {
        let frames = frames(in: size)
        return gaps(in: size).flatMap { gap in
            GapStrip.strips(around: gap, frames: frames)
        }
    }

    func closing(_ id: Int) -> PaneLayout? {
        guard leafCount > 1, let next = root.removing(id) else { return nil }
        return PaneLayout(root: next)
    }

    func settingRatio(_ ratio: Double, at path: [Bool]) -> PaneLayout {
        PaneLayout(root: root.settingRatio(ratio, at: path))
    }

    /// Moves one shared edge. A seam that runs across two neighbors only
    /// resizes the neighbor under the pointer; the other side stays put.
    func resizing(_ divider: PaneDivider, to ratio: Double, cross: CGFloat) -> PaneLayout {
        guard let node = root.node(at: divider.path),
              let isolated = node.isolatingSeam(ratio: ratio, cross: cross, bounds: divider.bounds)
        else {
            return settingRatio(ratio, at: divider.path)
        }
        return PaneLayout(root: root.replacingNode(at: divider.path, with: isolated))
    }

    func absorbingEmpty(_ divider: PaneDivider, toward edge: PaneEdge, cross: CGFloat) -> PaneLayout? {
        guard let node = root.node(at: divider.path) else { return nil }
        if let collapsed = node.absorbingEmpty(toward: edge) {
            return PaneLayout(root: root.replacingNode(at: divider.path, with: collapsed))
        }
        let pinched: Double = edge == .bottom || edge == .trailing ? 1 : 0
        guard let isolated = node.isolatingSeam(ratio: pinched, cross: cross, bounds: divider.bounds),
              let collapsed = isolated.absorbingPinchedEmpty()
        else { return nil }
        return PaneLayout(root: root.replacingNode(at: divider.path, with: collapsed))
    }

    /// Dragging a screen to the far side of its neighbor either removes that
    /// neighbor, or — when the neighbor is wider than the screen being dragged —
    /// gives this screen the neighbor's full length and stacks the neighbor
    /// with whatever sat beside it.
    func covering(_ id: Int, toward edge: PaneEdge, canvas: CGSize = CGSize(width: 1000, height: 1000)) -> PaneLayout? {
        let frames = frames(in: canvas)
        guard let source = frames[id] else { return nil }
        let neighbors = adjacent(to: source, id: id, edge: edge, frames: frames)
        guard !neighbors.isEmpty else { return nil }

        let sourceCross = crossRange(of: source, edge: edge)
        let contained = neighbors.allSatisfy { rangeContains(sourceCross, crossRange(of: $0.frame, edge: edge)) }
        let unionCross = neighbors.reduce(crossRange(of: neighbors[0].frame, edge: edge)) { unionRange($0, crossRange(of: $1.frame, edge: edge)) }

        if contained && rangesEqual(unionCross, sourceCross) {
            let rects = [source] + neighbors.map(\.frame)
            guard let absorbed = unionIfRectangular(rects) else { return nil }
            var next = frames
            next[id] = absorbed
            for neighbor in neighbors {
                next.removeValue(forKey: neighbor.id)
            }
            return PaneLayout(rects: next, empties: gaps(in: canvas).notCovered(by: next))
        }

        guard neighbors.count == 1 else { return nil }
        let neighbor = neighbors[0]
        let neighborCross = crossRange(of: neighbor.frame, edge: edge)
        guard rangeContains(neighborCross, sourceCross), !rangesEqual(neighborCross, sourceCross) else { return nil }
        let overhangs = subtract(neighborCross, removing: sourceCross)
        guard overhangs.count == 1 else { return nil }

        let main = unionRange(mainRange(of: source, edge: edge), mainRange(of: neighbor.frame, edge: edge))
        var next = frames
        next[id] = makeRect(cross: sourceCross, main: main, edge: edge)
        next[neighbor.id] = makeRect(cross: overhangs[0], main: mainRange(of: neighbor.frame, edge: edge), edge: edge)
        return PaneLayout(rects: next, empties: gaps(in: canvas).notCovered(by: next))
    }

    func leafTouching(_ divider: PaneDivider, side: DividerSide, cross: CGFloat, canvas: CGSize) -> Int? {
        let line = divider.splitPosition
        var best: (id: Int, distance: CGFloat)?
        for (id, frame) in frames(in: canvas) {
            let onSide: Bool
            let start: CGFloat
            let end: CGFloat
            switch divider.axis {
            case .horizontal:
                onSide = side == .first ? abs(frame.maxY - line) < 1.5 : abs(frame.minY - line) < 1.5
                start = frame.minX
                end = frame.maxX
            case .vertical:
                onSide = side == .first ? abs(frame.maxX - line) < 1.5 : abs(frame.minX - line) < 1.5
                start = frame.minY
                end = frame.maxY
            }
            guard onSide, end - start > 1, cross >= start - 0.5, cross <= end + 0.5 else { continue }
            let distance = abs((start + end) / 2 - cross)
            if best == nil || distance < best!.distance {
                best = (id, distance)
            }
        }
        return best?.id
    }

    private init?(rects: [Int: CGRect], empties: [CGRect] = []) {
        var items = rects.map { PaneRect(id: $0.key, frame: $0.value) }
        for (offset, frame) in empties.enumerated() where frame.width > 1 && frame.height > 1 {
            items.append(PaneRect(id: -(offset + 1), frame: frame))
        }
        guard !items.isEmpty,
              items.allSatisfy({ $0.frame.width > 1 && $0.frame.height > 1 }),
              let root = PaneNode.partition(items)?.replacingPlaceholderLeaves() else { return nil }
        self.init(root: root)
    }
}

enum DividerSide {
    case first
    case second
}

struct DividerDragSession: Equatable {
    var divider: PaneDivider
    var start: PaneLayout
    var cross: CGFloat
    var canvas: CGSize

    func preview(at point: CGPoint) -> PaneLayout {
        let bounds = divider.bounds
        let length = divider.axis == .horizontal ? bounds.height : bounds.width
        guard length > 1 else { return start }
        let origin = divider.axis == .horizontal ? bounds.minY : bounds.minX
        let position = divider.axis == .horizontal ? point.y : point.x
        let zone = min(36, length * 0.22)

        let leadingEdge: PaneEdge = divider.axis == .horizontal ? .top : .leading
        let trailingEdge: PaneEdge = divider.axis == .horizontal ? .bottom : .trailing

        if position <= origin + zone {
            if let leaf = start.leafTouching(divider, side: .second, cross: cross, canvas: canvas),
               let covered = start.covering(leaf, toward: leadingEdge, canvas: canvas) {
                return covered
            }
            if let absorbed = start.absorbingEmpty(divider, toward: leadingEdge, cross: cross) {
                return absorbed
            }
        }

        if position >= origin + length - zone {
            if let leaf = start.leafTouching(divider, side: .first, cross: cross, canvas: canvas),
               let covered = start.covering(leaf, toward: trailingEdge, canvas: canvas) {
                return covered
            }
            if let absorbed = start.absorbingEmpty(divider, toward: trailingEdge, cross: cross) {
                return absorbed
            }
        }

        let raw = (position - origin) / length
        let ratio = min(max(Double(raw), 0), 1)
        let line = divider.splitPosition
        if abs(position - line) < 8 {
            return start
        }
        return start.resizing(divider, to: ratio, cross: cross)
    }
}

private struct PaneRect {
    var id: Int
    var frame: CGRect
}

private struct AxisRange {
    var start: CGFloat
    var end: CGFloat

    var length: CGFloat { end - start }
}

private extension PaneNode {
    func collectFrames(in rect: CGRect, into frames: inout [Int: CGRect]) {
        switch self {
        case .empty:
            break
        case .leaf(let id):
            frames[id] = rect
        case .split(let axis, let ratio, let first, let second):
            let clamped = min(max(ratio, 0.02), 0.98)
            switch axis {
            case .horizontal:
                let split = rect.minY + rect.height * CGFloat(clamped)
                first.collectFrames(
                    in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: split - rect.minY),
                    into: &frames
                )
                second.collectFrames(
                    in: CGRect(x: rect.minX, y: split, width: rect.width, height: rect.maxY - split),
                    into: &frames
                )
            case .vertical:
                let split = rect.minX + rect.width * CGFloat(clamped)
                first.collectFrames(
                    in: CGRect(x: rect.minX, y: rect.minY, width: split - rect.minX, height: rect.height),
                    into: &frames
                )
                second.collectFrames(
                    in: CGRect(x: split, y: rect.minY, width: rect.maxX - split, height: rect.height),
                    into: &frames
                )
            }
        }
    }

    func collectGaps(in rect: CGRect, into gaps: inout [CGRect]) {
        switch self {
        case .empty:
            gaps.append(rect)
        case .leaf:
            break
        case .split(let axis, let ratio, let first, let second):
            let clamped = min(max(ratio, 0.02), 0.98)
            switch axis {
            case .horizontal:
                let split = rect.minY + rect.height * CGFloat(clamped)
                first.collectGaps(
                    in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: split - rect.minY),
                    into: &gaps
                )
                second.collectGaps(
                    in: CGRect(x: rect.minX, y: split, width: rect.width, height: rect.maxY - split),
                    into: &gaps
                )
            case .vertical:
                let split = rect.minX + rect.width * CGFloat(clamped)
                first.collectGaps(
                    in: CGRect(x: rect.minX, y: rect.minY, width: split - rect.minX, height: rect.height),
                    into: &gaps
                )
                second.collectGaps(
                    in: CGRect(x: split, y: rect.minY, width: rect.maxX - split, height: rect.height),
                    into: &gaps
                )
            }
        }
    }

    func collectDividers(in rect: CGRect, path: [Bool], into dividers: inout [PaneDivider]) {
        guard case .split(let axis, let ratio, let first, let second) = self else { return }
        let clamped = min(max(ratio, 0.02), 0.98)
        dividers.append(PaneDivider(path: path, axis: axis, bounds: rect, ratio: clamped))
        switch axis {
        case .horizontal:
            let split = rect.minY + rect.height * CGFloat(clamped)
            first.collectDividers(
                in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: split - rect.minY),
                path: path + [false],
                into: &dividers
            )
            second.collectDividers(
                in: CGRect(x: rect.minX, y: split, width: rect.width, height: rect.maxY - split),
                path: path + [true],
                into: &dividers
            )
        case .vertical:
            let split = rect.minX + rect.width * CGFloat(clamped)
            first.collectDividers(
                in: CGRect(x: rect.minX, y: rect.minY, width: split - rect.minX, height: rect.height),
                path: path + [false],
                into: &dividers
            )
            second.collectDividers(
                in: CGRect(x: split, y: rect.minY, width: rect.maxX - split, height: rect.height),
                path: path + [true],
                into: &dividers
            )
        }
    }

    func sanitized(maxLeaves: Int, seen: inout Set<Int>) -> PaneNode? {
        switch self {
        case .empty:
            return .empty
        case .leaf(let id):
            guard (0..<maxLeaves).contains(id), seen.insert(id).inserted else { return nil }
            return self
        case .split(let axis, let ratio, let first, let second):
            guard ratio.isFinite else { return nil }
            let clamped = min(max(ratio, 0.05), 0.95)
            guard let leading = first.sanitized(maxLeaves: maxLeaves, seen: &seen),
                  let trailing = second.sanitized(maxLeaves: maxLeaves, seen: &seen) else { return nil }
            return .split(axis: axis, ratio: clamped, first: leading, second: trailing)
        }
    }

    static func partition(_ items: [PaneRect]) -> PaneNode? {
        if items.count == 1 {
            return .leaf(items[0].id)
        }
        guard items.count > 1 else { return nil }
        let minX = items.map(\.frame.minX).min() ?? 0
        let minY = items.map(\.frame.minY).min() ?? 0
        let maxX = items.map(\.frame.maxX).max() ?? 0
        let maxY = items.map(\.frame.maxY).max() ?? 0
        guard maxX - minX > 1, maxY - minY > 1 else { return nil }

        let ys = Set(items.flatMap { [$0.frame.minY, $0.frame.maxY] })
            .filter { $0 > minY + 0.75 && $0 < maxY - 0.75 }
            .sorted()
        for y in ys {
            let above = items.filter { $0.frame.maxY <= y + 0.75 }
            let below = items.filter { $0.frame.minY >= y - 0.75 }
            guard above.count + below.count == items.count, !above.isEmpty, !below.isEmpty else { continue }
            guard let first = partition(above), let second = partition(below) else { return nil }
            return .split(axis: .horizontal, ratio: Double((y - minY) / (maxY - minY)), first: first, second: second)
        }

        let xs = Set(items.flatMap { [$0.frame.minX, $0.frame.maxX] })
            .filter { $0 > minX + 0.75 && $0 < maxX - 0.75 }
            .sorted()
        for x in xs {
            let leading = items.filter { $0.frame.maxX <= x + 0.75 }
            let trailing = items.filter { $0.frame.minX >= x - 0.75 }
            guard leading.count + trailing.count == items.count, !leading.isEmpty, !trailing.isEmpty else { continue }
            guard let first = partition(leading), let second = partition(trailing) else { return nil }
            return .split(axis: .vertical, ratio: Double((x - minX) / (maxX - minX)), first: first, second: second)
        }
        return nil
    }
}

private func adjacent(
    to source: CGRect,
    id: Int,
    edge: PaneEdge,
    frames: [Int: CGRect]
) -> [(id: Int, frame: CGRect)] {
    frames.compactMap { other, frame in
        guard other != id else { return nil }
        let touches: Bool
        let overlaps: Bool
        switch edge {
        case .top:
            touches = abs(frame.maxY - source.minY) < 1.5
            overlaps = frame.maxX > source.minX + 1 && frame.minX < source.maxX - 1
        case .bottom:
            touches = abs(frame.minY - source.maxY) < 1.5
            overlaps = frame.maxX > source.minX + 1 && frame.minX < source.maxX - 1
        case .leading:
            touches = abs(frame.maxX - source.minX) < 1.5
            overlaps = frame.maxY > source.minY + 1 && frame.minY < source.maxY - 1
        case .trailing:
            touches = abs(frame.minX - source.maxX) < 1.5
            overlaps = frame.maxY > source.minY + 1 && frame.minY < source.maxY - 1
        }
        return touches && overlaps ? (other, frame) : nil
    }
}

private func crossRange(of rect: CGRect, edge: PaneEdge) -> AxisRange {
    switch edge {
    case .top, .bottom:
        return AxisRange(start: rect.minX, end: rect.maxX)
    case .leading, .trailing:
        return AxisRange(start: rect.minY, end: rect.maxY)
    }
}

private func mainRange(of rect: CGRect, edge: PaneEdge) -> AxisRange {
    switch edge {
    case .top, .bottom:
        return AxisRange(start: rect.minY, end: rect.maxY)
    case .leading, .trailing:
        return AxisRange(start: rect.minX, end: rect.maxX)
    }
}

private func makeRect(cross: AxisRange, main: AxisRange, edge: PaneEdge) -> CGRect {
    switch edge {
    case .top, .bottom:
        return CGRect(x: cross.start, y: main.start, width: cross.length, height: main.length)
    case .leading, .trailing:
        return CGRect(x: main.start, y: cross.start, width: main.length, height: cross.length)
    }
}

private func rangeContains(_ outer: AxisRange, _ inner: AxisRange, slop: CGFloat = 1.5) -> Bool {
    inner.start >= outer.start - slop && inner.end <= outer.end + slop
}

private func rangesEqual(_ lhs: AxisRange, _ rhs: AxisRange, slop: CGFloat = 1.5) -> Bool {
    abs(lhs.start - rhs.start) < slop && abs(lhs.end - rhs.end) < slop
}

private func unionRange(_ lhs: AxisRange, _ rhs: AxisRange) -> AxisRange {
    AxisRange(start: min(lhs.start, rhs.start), end: max(lhs.end, rhs.end))
}

private func subtract(_ outer: AxisRange, removing inner: AxisRange) -> [AxisRange] {
    var pieces: [AxisRange] = []
    if inner.start > outer.start + 0.5 {
        pieces.append(AxisRange(start: outer.start, end: inner.start))
    }
    if inner.end < outer.end - 0.5 {
        pieces.append(AxisRange(start: inner.end, end: outer.end))
    }
    return pieces.filter { $0.length > 1 }
}

private extension Array where Element == CGRect {
    func notCovered(by leaves: [Int: CGRect]) -> [CGRect] {
        filter { gap in
            let center = CGPoint(x: gap.midX, y: gap.midY)
            return !leaves.values.contains { $0.insetBy(dx: -1, dy: -1).contains(center) }
        }
    }
}

private func unionIfRectangular(_ rects: [CGRect]) -> CGRect? {
    guard let first = rects.first else { return nil }
    let union = rects.dropFirst().reduce(first) { $0.union($1) }
    let area = rects.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
    let expected = union.width * union.height
    let slop = max(8, expected * 0.001)
    guard union.width > 1, union.height > 1, abs(expected - area) <= slop else { return nil }
    return union
}
