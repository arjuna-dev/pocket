import AppKit

enum ScreenLayout: String, CaseIterable, Identifiable {
    case single, sideBySide, stacked, grid

    var id: String { rawValue }
    var title: String {
        switch self {
        case .single: return "One screen"
        case .sideBySide: return "Two side by side"
        case .stacked: return "Two stacked"
        case .grid: return "Four screens"
        }
    }
    var symbolName: String {
        switch self {
        case .single: return "rectangle.fill"
        case .sideBySide: return "rectangle.split.2x1.fill"
        case .stacked: return "rectangle.split.1x2.fill"
        case .grid: return "rectangle.split.2x2.fill"
        }
    }
    var iconImage: NSImage { Self.icons[self]! }
    private static let icons: [ScreenLayout: NSImage] = Dictionary(uniqueKeysWithValues: allCases.map { layout in
        let image = NSImage(size: CGSize(width: 16, height: 16), flipped: false) { _ in
            for cell in 0..<4 {
                NSColor.white.withAlphaComponent(layout.filledIconCells.contains(cell) ? 1 : 0.22).setFill()
                NSBezierPath(rect: CGRect(x: (cell % 2) * 9, y: (1 - cell / 2) * 9, width: 7, height: 7)).fill()
            }
            return true
        }
        image.isTemplate = true
        return (layout, image)
    })

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

    var columns: Int { self == .sideBySide || self == .grid ? 2 : 1 }
    var rows: Int { self == .stacked || self == .grid ? 2 : 1 }
    var screenIDs: [Int] { Array(0..<(columns * rows)) }
    var filledIconCells: Set<Int> {
        switch self {
        case .single: return [0]
        case .sideBySide: return [0, 1]
        case .stacked: return [0, 2]
        case .grid: return [0, 1, 2, 3]
        }
    }

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
