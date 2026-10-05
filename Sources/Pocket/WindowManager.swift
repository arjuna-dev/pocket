import AppKit
import SwiftUI

final class WindowManager {
    static let shared = WindowManager()

    private weak var window: NSWindow?
    private var alwaysOnTop = false
    private var lastContentSize: CGSize?
    private var currentMode: PresentationMode?
    private var currentOrientation: DeviceOrientation?
    private var currentScreenCount = 1
    private var resizeObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?

    private init() {}

    func attach(window: NSWindow) {
        // SwiftUI resolves the bridge again for hover and other view updates.
        // Configure each window once so those updates cannot disrupt a drag.
        guard self.window !== window else { return }
        removeObservers()
        installObservers(for: window)
        lastContentSize = nil

        self.window = window
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
        screenCount: Int = 1,
        scale: CGFloat = 1.0,
        size: CGSize? = nil,
        animated: Bool = true,
        force: Bool = false
    ) {
        guard let window else { return }

        currentMode = mode
        currentOrientation = orientation
        currentScreenCount = max(1, min(screenCount, CompactLayout.slotCount))
        configureChrome(for: mode, orientation: orientation, screenCount: currentScreenCount, window: window)

        let proposed = size ?? mode.contentSize(
            for: orientation,
            screenCount: currentScreenCount,
            scale: scale
        )
        let contentSize = fittedToVisibleScreen(proposed, on: window)
        if !force, let lastContentSize,
           abs(lastContentSize.width - contentSize.width) < 1,
           abs(lastContentSize.height - contentSize.height) < 1 {
            return
        }

        let oldFrame = window.frame
        window.contentMinSize = CGSize(
            width: max(280, contentSize.width * 0.62),
            height: max(220, contentSize.height * 0.62)
        )
        window.setContentSize(contentSize)

        var newFrame = window.frame
        newFrame.origin.x = oldFrame.midX - newFrame.width / 2
        newFrame.origin.y = oldFrame.midY - newFrame.height / 2
        window.setFrame(newFrame, display: true, animate: animated)
        lastContentSize = contentSize
    }

    func ensureInitialSize(
        for mode: PresentationMode,
        orientation: DeviceOrientation,
        screenCount: Int
    ) {
        guard lastContentSize == nil else { return }
        restoreSize(
            for: mode,
            orientation: orientation,
            screenCount: screenCount,
            animated: false
        )
    }

    func restoreSize(
        for mode: PresentationMode,
        orientation: DeviceOrientation,
        screenCount: Int,
        animated: Bool = true
    ) {
        resize(
            for: mode,
            orientation: orientation,
            screenCount: screenCount,
            size: savedContentSize(for: mode, orientation: orientation, screenCount: screenCount),
            animated: animated,
            force: true
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
        guard contentSize.width > 0, contentSize.height > 0 else { return }

        let baseSize = currentMode.contentSize(
            for: currentOrientation,
            screenCount: currentScreenCount
        )
        guard baseSize.width > 0 else { return }
        UserDefaults.standard.set(
            contentSize.width / baseSize.width,
            forKey: scaleKey(for: currentMode)
        )
    }

    private func savedContentSize(
        for mode: PresentationMode,
        orientation: DeviceOrientation,
        screenCount: Int
    ) -> CGSize? {
        let scale = UserDefaults.standard.double(forKey: scaleKey(for: mode))
        guard scale > 0 else { return nil }
        return mode.contentSize(for: orientation, screenCount: screenCount, scale: scale)
    }

    private func fittedToVisibleScreen(_ size: CGSize, on window: NSWindow) -> CGSize {
        guard size.width > 1, size.height > 1 else { return size }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame.insetBy(dx: 20, dy: 20)
        guard let visible, visible.width > 1, visible.height > 1 else { return size }
        let fit = min(1, visible.width / size.width, visible.height / size.height)
        return CGSize(width: floor(size.width * fit), height: floor(size.height * fit))
    }

    private func scaleKey(for mode: PresentationMode) -> String {
        "Pocket.windowScale.\(mode.rawValue)"
    }

    private func configureChrome(
        for mode: PresentationMode,
        orientation: DeviceOrientation,
        screenCount: Int,
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
        window.contentAspectRatio = mode.contentSize(
            for: orientation,
            screenCount: screenCount
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
    private var mouseEventMonitor: Any?
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

    func makeNSView(context: Context) -> HoverTrackingNSView {
        let view = HoverTrackingNSView(frame: .zero)
        view.onHoverChanged = onHoverChanged
        view.onLocationChanged = onLocationChanged
        return view
    }

    func updateNSView(_ nsView: HoverTrackingNSView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
        nsView.onLocationChanged = onLocationChanged
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
