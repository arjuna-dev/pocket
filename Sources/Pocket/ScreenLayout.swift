import AppKit

struct ScreenLayout: RawRepresentable, Hashable, Identifiable, CaseIterable {
    let columns: Int
    let rows: Int

    init(columns: Int, rows: Int) {
        precondition((1...4).contains(columns) && (1...4).contains(rows))
        self.columns = columns
        self.rows = rows
    }

    init?(rawValue: String) {
        switch rawValue {
        case "single": self.init(columns: 1, rows: 1)
        case "sideBySide": self.init(columns: 2, rows: 1)
        case "stacked": self.init(columns: 1, rows: 2)
        case "grid": self.init(columns: 2, rows: 2)
        default:
            let values = rawValue.split(separator: "x").compactMap { Int($0) }
            guard values.count == 2, (1...4).contains(values[0]), (1...4).contains(values[1]) else { return nil }
            self.init(columns: values[0], rows: values[1])
        }
    }

    var rawValue: String { "\(columns)x\(rows)" }
    var id: String { rawValue }
    var title: String { "\(columns) columns by \(rows) rows" }
    var compactTitle: String { "\(columns) x \(rows)" }
    var screenCount: Int { columns * rows }
    var iconImage: NSImage {
        NSImage(size: CGSize(width: 16, height: 16), flipped: false) { _ in
            let edge: CGFloat = 15
            let gap: CGFloat = columns == 1 && rows == 1 ? 0 : 0.75
            let cellWidth = (edge - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let cellHeight = (edge - gap * CGFloat(rows - 1)) / CGFloat(rows)
            for row in 0..<rows {
                for column in 0..<columns {
                    NSColor.white.setFill()
                    NSBezierPath(rect: CGRect(x: 0.5 + CGFloat(column) * (cellWidth + gap),
                        y: 0.5 + CGFloat(row) * (cellHeight + gap), width: cellWidth, height: cellHeight)).fill()
                }
            }
            return true
        }
    }

    static let allCases: [ScreenLayout] = (1...4).flatMap { rows in
        (1...4).map { columns in ScreenLayout(columns: columns, rows: rows) }
    }
    static let defaultQuickLayouts: [ScreenLayout] = [single, sideBySide, stacked, grid]
    static let single = ScreenLayout(columns: 1, rows: 1)
    static let sideBySide = ScreenLayout(columns: 2, rows: 1)
    static let stacked = ScreenLayout(columns: 1, rows: 2)
    static let grid = ScreenLayout(columns: 2, rows: 2)

    static let topBarHeight: CGFloat = 40
    static let bottomBarHeight: CGFloat = 48
    static let minimumPageSize = CGSize(width: 220, height: 140)

    func contentSize(forPageSize page: CGSize) -> CGSize {
        CGSize(width: page.width * CGFloat(columns),
               height: page.height * CGFloat(rows) + Self.topBarHeight + Self.bottomBarHeight)
    }

    func pageSize(in size: CGSize) -> CGSize {
        CGSize(width: max(size.width, 1) / CGFloat(columns),
               height: max(size.height - Self.topBarHeight - Self.bottomBarHeight, 1) / CGFloat(rows))
    }

    var screenIDs: [Int] { Array(0..<screenCount) }

    func frames(in size: CGSize, topBarHeight: CGFloat = Self.topBarHeight, bottomBarHeight: CGFloat = Self.bottomBarHeight) -> [CGRect] {
        let width = max(size.width, 1) / CGFloat(columns)
        let height = max(size.height - topBarHeight - bottomBarHeight, 1) / CGFloat(rows)
        return screenIDs.map { index in
            CGRect(x: CGFloat(index % columns) * width,
                   y: topBarHeight + CGFloat(index / columns) * height,
                   width: width, height: height)
        }
    }
}

// Positioning and hover routing share the same geometry. The hover region
// includes the gap below both controls, and the gap between their capsules.
enum ScreenControlGeometry {
    static func navigation(above page: CGRect) -> CGRect {
        CGRect(x: page.maxX - 92, y: page.minY - 35, width: 84, height: 30)
    }

    static func website(above page: CGRect) -> CGRect {
        let navigation = navigation(above: page)
        // Leave room for the shared traffic lights above the first screen.
        let windowButtonsWidth: CGFloat = page.minX < 0.5 && page.minY <= ScreenLayout.topBarHeight + 0.5 ? 64 : 0
        let width = min(160, max(page.width - 106 - windowButtonsWidth, 1))
        return CGRect(x: navigation.minX - 6 - width, y: navigation.minY, width: width, height: navigation.height)
    }

    static func hoverRegion(above page: CGRect) -> CGRect {
        let controls = navigation(above: page).union(website(above: page))
        return CGRect(x: controls.minX - 3, y: controls.minY,
                      width: controls.width + 6, height: page.minY - controls.minY + 1)
    }

    static func screenID(at point: CGPoint, frames: [CGRect], activeScreenID: Int?, focusedScreenID: Int) -> Int {
        if let id = activeScreenID, frames.indices.contains(id), hoverRegion(above: frames[id]).contains(point) {
            return id
        }
        return frames.firstIndex(where: { $0.contains(point) }) ?? focusedScreenID
    }
}
