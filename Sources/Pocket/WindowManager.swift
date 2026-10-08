import AppKit
import SwiftUI

final class WindowManager: ObservableObject {
    static let shared = WindowManager()

    @Published private(set) var isChromeVisible = false

    private weak var window: NSWindow?
    private var alwaysOnTop = false
    private var lastContentSize: CGSize?
    private var currentMode: PresentationMode?
    private var currentOrientation: DeviceOrientation?
    private var currentFootprint = LayoutFootprint.single
    /// Set when a drag would have shrunk the window. Later edge drags keep this shape.
    private var preservedAspect: CGSize?
    private var resizeObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private let resizeDelegate = ChromeResizeDelegate()
    private var outerTop: CGFloat { CompactLayout.screenBarHeight }
    private var outerBottom: CGFloat { CompactLayout.controlsStripHeight }
    private var showsRightStrip: Bool {
        isChromeVisible && PocketModel.shared.paneLayout.root.gridSpan.columns == 1
    }

    private var rightStripIsRail: Bool {
        PocketModel.shared.paneLayout.leafCount == 1
    }
    private var showsBottomStrips: Bool {
        isChromeVisible && PocketModel.shared.paneLayout.root.gridSpan.rows == 1
    }
    private var outerRight: CGFloat {
        showsRightStrip ? CompactLayout.addStripThickness : 0
    }
    private var outerAddBottom: CGFloat {
        showsBottomStrips ? CompactLayout.addStripThickness : 0
    }

    private init() {}

    func attach(window: NSWindow) {
        // SwiftUI resolves the bridge again for hover and other view updates.
        // Configure each window once so those updates cannot disrupt a drag.
        guard self.window !== window else { return }
        removeObservers()
        installObservers(for: window)
        lastContentSize = nil

        self.window = window
        resizeDelegate.manager = self
        window.delegate = resizeDelegate
        window.title = "Pocket"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true
        window.backgroundColor = .clear
        window.isOpaque = false

    }

    func resize(
        for mode: PresentationMode,
        orientation: DeviceOrientation,
        footprint: LayoutFootprint = .single,
        scale: CGFloat = 1.0,
        size: CGSize? = nil,
        animated: Bool = true,
        force: Bool = false,
        allowShrink: Bool = true
    ) {
        guard let window else { return }

        currentMode = mode
        currentOrientation = orientation
        currentFootprint = LayoutFootprint(
            width: max(footprint.width, 1),
            height: max(footprint.height, 1)
        )
        configureChrome(for: mode, orientation: orientation, footprint: currentFootprint, window: window)

        var proposed = size ?? mode.contentSize(
            for: orientation,
            footprint: currentFootprint,
            scale: scale
        )
        if !allowShrink {
            let current = pageSize(from: window.contentRect(forFrameRect: window.frame).size)
            proposed = CGSize(
                width: max(proposed.width, current.width),
                height: max(proposed.height, current.height)
            )
        }
        let screenSize = fittedToVisibleScreen(proposed, on: window)
        if !force, let lastContentSize,
           abs(lastContentSize.width - screenSize.width) < 1,
           abs(lastContentSize.height - screenSize.height) < 1 {
            let expected = windowContentSize(for: screenSize)
            let actual = window.contentRect(forFrameRect: window.frame).size
            if abs(actual.width - expected.width) < 1, abs(actual.height - expected.height) < 1 {
                syncAddStripContainer(screen: screenSize)
                return
            }
        }

        let oldFrame = window.frame
        let contentSize = windowContentSize(for: screenSize)
        syncAddStripContainer(screen: screenSize)
        let minimum = minimumContentSize(for: mode, orientation: orientation, footprint: currentFootprint)
        // Keep the floor below the current window. When the floor matches the
        // window exactly, AppKit treats every edge drag as a no-op.
        window.contentMinSize = CGSize(
            width: min(minimum.width * 0.7, contentSize.width * 0.7),
            height: min(minimum.height * 0.7, contentSize.height * 0.7)
        )
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.setContentSize(contentSize)

        var newFrame = window.frame
        newFrame.origin.x = oldFrame.midX - newFrame.width / 2
        newFrame.origin.y = oldFrame.midY - newFrame.height / 2
        window.setFrame(newFrame, display: true, animate: animated)
        lastContentSize = screenSize
        if allowShrink {
            preservedAspect = nil
        } else if let currentMode, let currentOrientation {
            preservedAspect = screenSize
            window.contentAspectRatio = screenSize
            pinPageSize(screenSize, mode: currentMode, orientation: currentOrientation, footprint: currentFootprint)
        }
    }

    func setChromeVisible(_ visible: Bool) {
        guard isChromeVisible != visible else { return }
        isChromeVisible = visible
        guard let window, let screen = lastContentSize else {
            syncAddStripContainer(screen: lastContentSize ?? .zero)
            return
        }
        let oldContent = window.contentRect(forFrameRect: window.frame)
        let contentSize = windowContentSize(for: screen)
        var newContent = NSRect(origin: oldContent.origin, size: contentSize)
        // Keep the top-left of the screen fixed. The strips extend to the right and downward.
        newContent.origin.y = oldContent.maxY - contentSize.height
        if let currentMode, let currentOrientation {
            let page = currentMode.contentSize(for: currentOrientation, footprint: currentFootprint)
            window.contentAspectRatio = NSSize(
                width: page.width + outerRight,
                height: page.height + outerTop + outerBottom + outerAddBottom
            )
        }
        syncAddStripContainer(screen: screen)
        let newFrame = clampedToVisibleScreen(window.frameRect(forContentRect: newContent), window: window)
        window.setFrame(newFrame, display: true, animate: true)
    }

    private func windowContentSize(for screen: CGSize) -> CGSize {
        CGSize(
            width: screen.width + outerRight,
            height: screen.height + outerTop + outerBottom + outerAddBottom
        )
    }

    private func pageSize(from content: CGSize) -> CGSize {
        CGSize(
            width: max(1, content.width - outerRight),
            height: max(1, content.height - outerTop - outerBottom - outerAddBottom)
        )
    }

    private func syncAddStripContainer(screen: CGSize) {
        guard let container = window?.contentView as? PocketChromeContainer else { return }
        container.screenSize = screen
        container.showsRightStrip = showsRightStrip
        container.rightStripIsRail = rightStripIsRail
        container.showsBottomStrips = showsBottomStrips
    }

    func ensureInitialSize(
        for mode: PresentationMode,
        orientation: DeviceOrientation,
        footprint: LayoutFootprint
    ) {
        guard lastContentSize == nil else { return }
        restoreSize(
            for: mode,
            orientation: orientation,
            footprint: footprint,
            animated: false
        )
    }

    func restoreSize(
        for mode: PresentationMode,
        orientation: DeviceOrientation,
        footprint: LayoutFootprint,
        animated: Bool = true,
        allowShrink: Bool = true
    ) {
        resize(
            for: mode,
            orientation: orientation,
            footprint: footprint,
            size: savedContentSize(for: mode, orientation: orientation, footprint: footprint),
            animated: animated,
            force: true,
            allowShrink: allowShrink
        )
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        alwaysOnTop = enabled
        guard let window else { return }

        // Pinned panels must accept interaction in other apps' full-screen
        // Spaces without activating Pocket. Unpinned panels should behave like
        // ordinary app windows and come forward when Pocket is selected.
        if enabled {
            window.styleMask.insert(.nonactivatingPanel)
        } else {
            window.styleMask.remove(.nonactivatingPanel)
        }

        // Set an explicit policy for both states so unpinning also removes
        // the full-screen and all-desktop behavior, including after relaunch.
        var behavior = window.collectionBehavior
        behavior.subtract([
            .canJoinAllSpaces, .moveToActiveSpace,
            .fullScreenPrimary, .fullScreenAuxiliary, .fullScreenNone,
            .primary, .auxiliary, .canJoinAllApplications,
            .managed, .transient, .stationary
        ])
        if enabled {
            behavior.formUnion([
                .canJoinAllSpaces, .fullScreenAuxiliary,
                .canJoinAllApplications, .stationary
            ])
        } else {
            behavior.formUnion([.managed, .fullScreenNone])
        }
        if window.collectionBehavior != behavior {
            window.collectionBehavior = behavior
        }

        let level: NSWindow.Level = enabled ? .floating : .normal
        if window.level != level {
            window.level = level
        }
    }

    func closeWindow() {
        window?.performClose(nil)
    }

    func minimizeWindow() {
        window?.miniaturize(nil)
    }

    func zoomWindow() {
        window?.performZoom(nil)
    }

    private func installObservers(for window: NSWindow) {
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.rememberCurrentWindowSize()
        }

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.rememberCurrentWindowSize()
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rememberCurrentWindowSize()
        }
    }

    private func removeObservers() {
        for observer in [resizeObserver, closeObserver, terminationObserver] {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        resizeObserver = nil
        closeObserver = nil
        terminationObserver = nil

    }

    private func rememberCurrentWindowSize() {
        guard let window, let currentMode, let currentOrientation else { return }

        let contentSize = window.contentRect(forFrameRect: window.frame).size
        let screenSize = pageSize(from: contentSize)
        guard screenSize.width > 0, screenSize.height > 0 else { return }
        lastContentSize = screenSize

        let baseSize = currentMode.contentSize(
            for: currentOrientation,
            footprint: currentFootprint
        )
        guard baseSize.width > 0 else { return }
        clearPinnedPageSize(for: currentMode)
        UserDefaults.standard.set(
            screenSize.width / baseSize.width,
            forKey: scaleKey(for: currentMode)
        )
    }

    private func savedContentSize(
        for mode: PresentationMode,
        orientation: DeviceOrientation,
        footprint: LayoutFootprint
    ) -> CGSize? {
        let scale = UserDefaults.standard.double(forKey: scaleKey(for: mode))
        let scaled = scale > 0
            ? mode.contentSize(for: orientation, footprint: footprint, scale: scale)
            : nil
        guard let pinned = pinnedPageSize(for: mode, orientation: orientation, footprint: footprint) else {
            return scaled
        }
        guard let scaled else { return pinned }
        return CGSize(width: max(scaled.width, pinned.width), height: max(scaled.height, pinned.height))
    }

    private func pinPageSize(
        _ size: CGSize,
        mode: PresentationMode,
        orientation: DeviceOrientation,
        footprint: LayoutFootprint
    ) {
        let defaults = UserDefaults.standard
        let key = pinKey(for: mode)
        defaults.set(size.width, forKey: key + ".width")
        defaults.set(size.height, forKey: key + ".height")
        defaults.set(Double(footprint.width), forKey: key + ".footprintWidth")
        defaults.set(Double(footprint.height), forKey: key + ".footprintHeight")
        defaults.set(orientation.rawValue, forKey: key + ".orientation")
    }

    private func pinnedPageSize(
        for mode: PresentationMode,
        orientation: DeviceOrientation,
        footprint: LayoutFootprint
    ) -> CGSize? {
        let defaults = UserDefaults.standard
        let key = pinKey(for: mode)
        guard defaults.string(forKey: key + ".orientation") == orientation.rawValue else { return nil }
        let width = defaults.double(forKey: key + ".width")
        let height = defaults.double(forKey: key + ".height")
        let footprintWidth = defaults.double(forKey: key + ".footprintWidth")
        let footprintHeight = defaults.double(forKey: key + ".footprintHeight")
        guard width > 1, height > 1,
              abs(footprintWidth - footprint.width) < 0.1,
              abs(footprintHeight - footprint.height) < 0.1 else { return nil }
        return CGSize(width: width, height: height)
    }

    private func clearPinnedPageSize(for mode: PresentationMode) {
        let defaults = UserDefaults.standard
        let key = pinKey(for: mode)
        for suffix in ["width", "height", "footprintWidth", "footprintHeight", "orientation"] {
            defaults.removeObject(forKey: key + "." + suffix)
        }
    }

    private func pinKey(for mode: PresentationMode) -> String {
        "Pocket.windowPagePin.\(mode.rawValue)"
    }

    private func minimumContentSize(
        for mode: PresentationMode,
        orientation: DeviceOrientation,
        footprint: LayoutFootprint
    ) -> CGSize {
        let screen = mode.contentSize(
            for: orientation,
            footprint: footprint,
            scale: mode.minimumScale
        )
        return windowContentSize(for: screen)
    }

    private func fittedToVisibleScreen(_ size: CGSize, on window: NSWindow) -> CGSize {
        guard size.width > 1, size.height > 1 else { return size }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame.insetBy(dx: 20, dy: 20)
        guard let visible, visible.width > 1, visible.height > 1 else { return size }
        let availableWidth = max(visible.width - outerRight, 1)
        let availableHeight = max(visible.height - outerTop - outerBottom - outerAddBottom, 1)
        let fit = min(1, availableWidth / size.width, availableHeight / size.height)
        return CGSize(width: floor(size.width * fit), height: floor(size.height * fit))
    }

    private func scaleKey(for mode: PresentationMode) -> String {
        "Pocket.windowScale.\(mode.rawValue)"
    }

    private func configureChrome(
        for mode: PresentationMode,
        orientation: DeviceOrientation,
        footprint: LayoutFootprint,
        window: NSWindow
    ) {
        // Style changes can reset AppKit's Space behavior. Reapply the policy
        // after changing modes without touching the window's position.
        defer { setAlwaysOnTop(alwaysOnTop) }
        // Keep the titlebar transparent and above the content view. Native
        // close/minimize controls are revealed only while the window is hovered.
        window.styleMask.remove(.borderless)
        window.styleMask.insert(.titled)
        window.styleMask.insert(.resizable)
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.hasShadow = false
        window.backgroundColor = .clear
        window.isOpaque = false
        let page = mode.contentSize(for: orientation, footprint: footprint)
        window.contentAspectRatio = NSSize(
            width: page.width + outerRight,
            height: page.height + outerTop + outerBottom + outerAddBottom
        )
        setStandardWindowButtonsHidden(true, on: window)
    }

    private func setStandardWindowButtonsHidden(_ hidden: Bool, on window: NSWindow) {
        let buttonTypes: [NSWindow.ButtonType] = [
            .closeButton,
            .miniaturizeButton,
            .zoomButton
        ]

        for buttonType in buttonTypes {
            window.standardWindowButton(buttonType)?.isHidden = hidden
        }
    }

    private func clampedToVisibleScreen(_ frame: NSRect, window: NSWindow) -> NSRect {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return frame }
        var frame = frame
        if frame.width > visible.width {
            frame.size.width = visible.width
        }
        if frame.height > visible.height {
            frame.size.height = visible.height
        }
        if frame.maxX > visible.maxX {
            frame.origin.x -= frame.maxX - visible.maxX
        }
        if frame.minX < visible.minX {
            frame.origin.x = visible.minX
        }
        if frame.maxY > visible.maxY {
            frame.origin.y -= frame.maxY - visible.maxY
        }
        if frame.minY < visible.minY {
            frame.origin.y = visible.minY
        }
        return frame
    }

    func resizedFrame(start: NSRect, proposed: NSRect, edges: Set<NSRectEdge>, window: NSWindow) -> NSRect {
        guard let currentMode, let currentOrientation else { return proposed }
        let base = preservedAspect ?? currentMode.contentSize(
            for: currentOrientation,
            footprint: currentFootprint
        )
        guard base.width > 1, base.height > 1 else { return proposed }
        let aspect = base.width / base.height
        let minimum = currentMode.contentSize(
            for: currentOrientation,
            footprint: currentFootprint,
            scale: currentMode.minimumScale
        )

        let horizontal = edges.contains(.minX) || edges.contains(.maxX)
        let vertical = edges.contains(.minY) || edges.contains(.maxY)
        var screenWidth = max(proposed.width - outerRight, 1)
        var screenHeight = max(proposed.height - outerTop - outerBottom - outerAddBottom, 1)
        if horizontal && !vertical {
            screenHeight = screenWidth / aspect
        } else if vertical && !horizontal {
            screenWidth = screenHeight * aspect
        } else if abs(screenWidth / base.width - 1) >= abs(screenHeight / base.height - 1) {
            screenHeight = screenWidth / aspect
        } else {
            screenWidth = screenHeight * aspect
        }
        let floorWidth = minimum.width * 0.7
        if screenWidth < floorWidth {
            screenWidth = floorWidth
            screenHeight = screenWidth / aspect
        }

        let size = NSSize(
            width: screenWidth + outerRight,
            height: screenHeight + outerTop + outerBottom + outerAddBottom
        )
        (window.contentView as? PocketChromeContainer)?.screenSize = CGSize(width: screenWidth, height: screenHeight)
        var frame = NSRect(origin: start.origin, size: size)
        if edges.contains(.minX) {
            frame.origin.x = start.maxX - size.width
        }
        if edges.contains(.minY) {
            frame.origin.y = start.maxY - size.height
        }
        if !horizontal {
            frame.origin.x = start.midX - size.width / 2
        }
        if !vertical {
            frame.origin.y = start.midY - size.height / 2
        }
        return frame
    }

    @discardableResult
    func beginEdgeResize(with event: NSEvent, in window: NSWindow) -> Bool {
        guard event.type == .leftMouseDown, let contentView = window.contentView else { return false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        if (contentView as? PocketChromeContainer)?.addStripContains(point) == true {
            return false
        }
        let edges = resizeEdges(at: point, in: contentView.bounds)
        guard !edges.isEmpty else { return false }

        let startFrame = window.frame
        let startMouse = screenLocation(of: event, in: window)
        while true {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            let proposed = proposedFrame(
                start: startFrame,
                startMouse: startMouse,
                mouse: screenLocation(of: next, in: window),
                edges: edges
            )
            window.setFrame(
                resizedFrame(start: startFrame, proposed: proposed, edges: edges, window: window),
                display: true
            )
            if next.type == .leftMouseUp { break }
        }
        rememberCurrentWindowSize()
        return true
    }

    func updateResizeCursor(with event: NSEvent, in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        let point = contentView.convert(event.locationInWindow, from: nil)
        if (contentView as? PocketChromeContainer)?.addStripContains(point) == true {
            return
        }
        let edges = resizeEdges(at: point, in: contentView.bounds)
        guard !edges.isEmpty else { return }
        resizeCursor(for: edges).set()
        // Chrome and web content reset the cursor during the same move.
        // Put the resize cursor back once that has happened.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, let contentView = window.contentView else { return }
            let mouse = window.mouseLocationOutsideOfEventStream
            let point = contentView.convert(mouse, from: nil)
            if (contentView as? PocketChromeContainer)?.addStripContains(point) == true { return }
            let still = self.resizeEdges(at: point, in: contentView.bounds)
            guard !still.isEmpty else { return }
            self.resizeCursor(for: still).set()
        }
    }

    private func resizeCursor(for edges: Set<NSRectEdge>) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch (edges.contains(.minX), edges.contains(.maxX), edges.contains(.maxY), edges.contains(.minY)) {
            case (true, false, true, false):
                position = .topLeft
            case (false, true, true, false):
                position = .topRight
            case (true, false, false, true):
                position = .bottomLeft
            case (false, true, false, true):
                position = .bottomRight
            case (true, false, _, _):
                position = .left
            case (false, true, _, _):
                position = .right
            case (_, _, true, false):
                position = .top
            case (_, _, false, true):
                position = .bottom
            default:
                return .arrow
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        let horizontal = edges.contains(.minX) || edges.contains(.maxX)
        let vertical = edges.contains(.minY) || edges.contains(.maxY)
        if horizontal {
            return .resizeLeftRight
        }
        if vertical {
            return .resizeUpDown
        }
        return .arrow
    }

    private func resizeEdges(at point: NSPoint, in bounds: NSRect) -> Set<NSRectEdge> {
        let margin: CGFloat = 12
        guard bounds.width > margin * 2, bounds.height > margin * 2 else { return [] }
        var edges: Set<NSRectEdge> = []
        if point.x <= bounds.minX + margin { edges.insert(.minX) }
        if point.x >= bounds.maxX - margin { edges.insert(.maxX) }
        if point.y <= bounds.minY + margin { edges.insert(.minY) }
        if point.y >= bounds.maxY - margin { edges.insert(.maxY) }
        return edges
    }

    private func screenLocation(of event: NSEvent, in window: NSWindow) -> NSPoint {
        window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
    }

    private func proposedFrame(
        start: NSRect,
        startMouse: NSPoint,
        mouse: NSPoint,
        edges: Set<NSRectEdge>
    ) -> NSRect {
        var frame = start
        let dx = mouse.x - startMouse.x
        let dy = mouse.y - startMouse.y
        if edges.contains(.maxX) {
            frame.size.width = start.width + dx
        }
        if edges.contains(.minX) {
            frame.size.width = start.width - dx
            frame.origin.x = start.maxX - frame.size.width
        }
        if edges.contains(.maxY) {
            frame.size.height = start.height + dy
        }
        if edges.contains(.minY) {
            frame.size.height = start.height - dy
            frame.origin.y = start.maxY - frame.size.height
        }
        return frame
    }

    func standardFrame(for window: NSWindow, defaultFrame: NSRect) -> NSRect {
        guard let currentMode, let currentOrientation else { return defaultFrame }
        let base = preservedAspect ?? currentMode.contentSize(
            for: currentOrientation,
            footprint: currentFootprint
        )
        guard base.width > 1, base.height > 1 else { return defaultFrame }
        let aspect = base.width / base.height
        let availableHeight = max(defaultFrame.height - outerTop - outerBottom - outerAddBottom, 1)
        var screenWidth = max(defaultFrame.width - outerRight, 1)
        var screenHeight = screenWidth / aspect
        if screenHeight > availableHeight {
            screenHeight = availableHeight
            screenWidth = screenHeight * aspect
        }
        let content = windowContentSize(for: CGSize(width: screenWidth, height: screenHeight))
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        frame.origin.x = defaultFrame.midX - frame.width / 2
        frame.origin.y = defaultFrame.midY - frame.height / 2
        return clampedToVisibleScreen(frame, window: window)
    }
}

final class PocketChromeContainer: NSView {
    let screenHost: NSView
    let topHost: NSView
    let bottomHost: NSView
    let rightAddHost: NSView
    let bottomAddHost: NSView
    var screenSize: CGSize = .zero
    var showsRightStrip = false {
        didSet { needsLayout = true }
    }
    /// A single screen uses one rail along the whole window. Stacked screens
    /// use one strip beside each pane, aligned with that pane.
    var rightStripIsRail = true {
        didSet { needsLayout = true }
    }
    var showsBottomStrips = false {
        didSet { needsLayout = true }
    }
    private var topHeight: CGFloat = 0
    private var bottomHeight: CGFloat = 0

    init(
        screenHost: NSView,
        topHost: NSView,
        bottomHost: NSView,
        rightAddHost: NSView,
        bottomAddHost: NSView
    ) {
        self.screenHost = screenHost
        self.topHost = topHost
        self.bottomHost = bottomHost
        self.rightAddHost = rightAddHost
        self.bottomAddHost = bottomAddHost
        topHeight = CompactLayout.screenBarHeight
        bottomHeight = CompactLayout.controlsStripHeight
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        // Track the window with the autoresizing mask. The hosts are positioned
        // in layout(), so they must not translate an empty mask into fixed
        // width and height constraints. Those constraints were rejecting drags.
        autoresizingMask = [.width, .height]
        autoresizesSubviews = false

        for host in [screenHost, topHost, bottomHost, rightAddHost, bottomAddHost] {
            host.translatesAutoresizingMaskIntoConstraints = false
            host.wantsLayer = true
        }
        rightAddHost.layer?.backgroundColor = NSColor.clear.cgColor
        bottomAddHost.layer?.backgroundColor = NSColor.clear.cgColor
        screenHost.clipsToBounds = true
        addSubview(screenHost)
        addSubview(bottomHost)
        addSubview(bottomAddHost)
        addSubview(topHost)
        addSubview(rightAddHost)
    }

    required init?(coder: NSCoder) {
        fatalError("PocketChromeContainer is created in code")
    }

    func addStripContains(_ point: NSPoint) -> Bool {
        if !rightAddHost.isHidden, rightAddHost.frame.contains(point) {
            return true
        }
        if !bottomAddHost.isHidden, bottomAddHost.frame.contains(point) {
            return true
        }
        return false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        for subview in subviews.reversed() {
            guard !subview.isHidden, let hit = subview.hitTest(local) else { continue }
            return hit
        }
        return nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        autoresizingMask = [.width, .height]
    }

    override func layout() {
        super.layout()
        let bottomStrip = showsBottomStrips ? CompactLayout.addStripThickness : 0
        let rightStrip = showsRightStrip ? CompactLayout.addStripThickness : 0
        let screenWidth = screenSize.width > 1 ? screenSize.width : max(1, bounds.width - rightStrip)
        let screenHeight = screenSize.height > 1
            ? screenSize.height
            : max(1, bounds.height - topHeight - bottomHeight - bottomStrip)
        let top = bounds.height

        topHost.frame = NSRect(x: 0, y: top - topHeight, width: screenWidth, height: topHeight)
        screenHost.frame = NSRect(
            x: 0,
            y: top - topHeight - screenHeight,
            width: screenWidth,
            height: screenHeight
        )
        bottomAddHost.frame = NSRect(
            x: 0,
            y: top - topHeight - screenHeight - bottomStrip,
            width: screenWidth,
            height: bottomStrip
        )
        bottomHost.frame = NSRect(
            x: 0,
            y: top - topHeight - screenHeight - bottomStrip - bottomHeight,
            width: screenWidth,
            height: bottomHeight
        )

        rightAddHost.frame = NSRect(
            x: screenWidth,
            y: top - topHeight - screenHeight,
            width: rightStrip,
            height: screenHeight
        )
        rightAddHost.isHidden = rightStrip == 0
        bottomAddHost.isHidden = bottomStrip == 0
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutSubtreeIfNeeded()
    }
}

private final class ChromeResizeDelegate: NSObject, NSWindowDelegate {
    weak var manager: WindowManager?

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // Edge drags are handled by PocketChromeContainer so the fixed bars can
        // stay put. Returning the proposed size here lets AppKit finish a resize
        // instead of cancelling it when the other side would also have to move.
        frameSize
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        manager?.standardFrame(for: window, defaultFrame: newFrame) ?? newFrame
    }
}

final class WindowDragView: NSView {
    var showsIndicator = false {
        didSet {
            if showsIndicator != oldValue {
                needsDisplay = true
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.001).cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.001).cgColor
    }

    // This view explicitly starts a native drag; do not also start a background drag.
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(showsIndicator ? 0.48 : 0.001).setFill()
        dirtyRect.fill()

        guard showsIndicator else { return }

        let indicatorHeight = max(2, bounds.height * 0.22)
        let indicatorRect = NSRect(
            x: 12,
            y: (bounds.height - indicatorHeight) / 2,
            width: 34,
            height: indicatorHeight
        )

        NSColor.white.withAlphaComponent(0.62).setFill()
        NSBezierPath(
            roundedRect: indicatorRect,
            xRadius: indicatorHeight / 2,
            yRadius: indicatorHeight / 2
        ).fill()
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

struct WindowDragHandle: NSViewRepresentable {
    let showsIndicator: Bool

    func makeNSView(context: Context) -> WindowDragView {
        let view = WindowDragView(frame: .zero)
        view.showsIndicator = showsIndicator
        return view
    }

    func updateNSView(_ nsView: WindowDragView, context: Context) {
        nsView.showsIndicator = showsIndicator
    }
}

final class HoverTrackingNSView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    var onLocationChanged: ((CGPoint?) -> Void)?
    var onMouseDown: ((CGPoint) -> Void)?
    private var mouseEventMonitor: Any?
    private var mouseDownMonitor: Any?
    private var isHovering = false
    private var lastPoint: CGPoint?

    deinit {
        removeMouseEventMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMouseEventMonitor()

        guard window != nil else {
            publish(hovering: false, point: nil)
            return
        }

        mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.updateHoverState(for: event)
            return event
        }

        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let self, let window = self.window, event.window?.windowNumber == window.windowNumber,
               let point = self.swiftPoint(fromScreen: window.convertPoint(toScreen: event.locationInWindow)) {
                self.onMouseDown?(point)
            }
            return event
        }

        updateHoverState(atScreenLocation: NSEvent.mouseLocation)
    }

    override func layout() {
        super.layout()
        guard window != nil else { return }
        let location = NSEvent.mouseLocation
        DispatchQueue.main.async { [weak self] in
            self?.updateHoverState(atScreenLocation: location)
        }
    }

    override func updateTrackingAreas() {
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )

        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoverState(atScreenLocation: NSEvent.mouseLocation)
    }

    override func mouseExited(with event: NSEvent) {
        updateHoverState(atScreenLocation: NSEvent.mouseLocation)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func removeMouseEventMonitor() {
        if let mouseEventMonitor {
            NSEvent.removeMonitor(mouseEventMonitor)
        }
        mouseEventMonitor = nil

        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
        }
        mouseDownMonitor = nil
    }

    private func updateHoverState(for event: NSEvent) {
        guard let window,
              let eventWindow = event.window,
              eventWindow.windowNumber == window.windowNumber
        else {
            return
        }

        let screenLocation = window.convertPoint(toScreen: event.locationInWindow)
        updateHoverState(atScreenLocation: screenLocation)
    }

    private func updateHoverState(atScreenLocation location: NSPoint) {
        guard let window else {
            publish(hovering: false, point: nil)
            return
        }

        let hovering = window.frame.contains(location)
        publish(hovering: hovering, point: hovering ? swiftPoint(fromScreen: location) : nil)
    }

    private func swiftPoint(fromScreen location: NSPoint) -> CGPoint? {
        guard let window, bounds.width > 1, bounds.height > 1 else { return nil }
        let windowPoint = window.convertPoint(fromScreen: location)
        let local = convert(windowPoint, from: nil)
        guard bounds.contains(local) else { return nil }
        // AppKit view coordinates grow upward. The pane grid grows downward.
        let y = isFlipped ? local.y : bounds.height - local.y
        return CGPoint(x: local.x, y: y)
    }

    private func publish(hovering: Bool, point: CGPoint?) {
        if isHovering != hovering {
            isHovering = hovering
            onHoverChanged?(hovering)
        }

        let moved: Bool
        switch (lastPoint, point) {
        case (nil, nil):
            moved = false
        case let (previous?, next?):
            moved = abs(previous.x - next.x) > 0.5 || abs(previous.y - next.y) > 0.5
        default:
            moved = true
        }
        guard moved else { return }
        lastPoint = point
        onLocationChanged?(point)
    }
}

struct HoverTrackingView: NSViewRepresentable {
    let onHoverChanged: (Bool) -> Void
    var onLocationChanged: ((CGPoint?) -> Void)?
    var onMouseDown: ((CGPoint) -> Void)? = nil

    func makeNSView(context: Context) -> HoverTrackingNSView {
        let view = HoverTrackingNSView(frame: .zero)
        view.onHoverChanged = onHoverChanged
        view.onLocationChanged = onLocationChanged
        view.onMouseDown = onMouseDown
        return view
    }

    func updateNSView(_ nsView: HoverTrackingNSView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
        nsView.onLocationChanged = onLocationChanged
        nsView.onMouseDown = onMouseDown
    }
}

struct WindowBridge: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.alphaValue = 0
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            onResolve(window)
        }
    }
}
