import AppKit
import SwiftUI

final class WindowManager {
    static let shared = WindowManager()

    private weak var window: NSWindow?
    private var lastContentSize: CGSize?
    private var currentMode: PresentationMode?
    private var currentOrientation: DeviceOrientation?
    private var resizeObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var dragEventMonitor: Any?
    private var manualDragStartLocation: NSPoint?
    private var manualDragWindowOrigin: NSPoint?

    private init() {}

    func attach(window: NSWindow) {
        if self.window?.windowNumber != window.windowNumber {
            removeObservers()
            installObservers(for: window)
            lastContentSize = nil
        }

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
        scale: CGFloat = 1.0,
        size: CGSize? = nil,
        animated: Bool = true,
        force: Bool = false
    ) {
        guard let window else { return }

        currentMode = mode
        currentOrientation = orientation
        configureChrome(for: mode, orientation: orientation, window: window)

        let contentSize = size ?? mode.contentSize(for: orientation, scale: scale)
        if !force, let lastContentSize,
           abs(lastContentSize.width - contentSize.width) < 1,
           abs(lastContentSize.height - contentSize.height) < 1 {
            return
        }

        let oldFrame = window.frame
        window.contentMinSize = mode.contentSize(
            for: orientation,
            scale: mode.minimumScale
        )
        window.setContentSize(contentSize)

        var newFrame = window.frame
        newFrame.origin.x = oldFrame.midX - newFrame.width / 2
        newFrame.origin.y = oldFrame.midY - newFrame.height / 2
        window.setFrame(newFrame, display: true, animate: animated)
        lastContentSize = contentSize
    }

    func ensureInitialSize(for mode: PresentationMode, orientation: DeviceOrientation) {
        guard lastContentSize == nil else { return }
        restoreSize(for: mode, orientation: orientation, animated: false)
    }

    func restoreSize(
        for mode: PresentationMode,
        orientation: DeviceOrientation,
        animated: Bool = true
    ) {
        resize(
            for: mode,
            orientation: orientation,
            size: savedContentSize(for: mode, orientation: orientation),
            animated: animated,
            force: true
        )
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        window?.level = enabled ? .floating : .normal
    }

    private func installDragEventMonitor() {
        dragEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handleDragEvent(event) ? nil : event
        }
    }

    private func handleDragEvent(_ event: NSEvent) -> Bool {
        guard let window,
              currentMode == .screen,
              window.styleMask.contains(.borderless)
        else {
            return false
        }

        switch event.type {
        case .leftMouseDown:
            guard isInScreenDragBand(event, window: window) else { return false }

            manualDragStartLocation = window.convertPoint(toScreen: event.locationInWindow)
            manualDragWindowOrigin = window.frame.origin
            NSCursor.closedHand.push()
            return true

        case .leftMouseDragged:
            guard let manualDragStartLocation,
                  let manualDragWindowOrigin
            else {
                return false
            }

            let currentLocation = window.convertPoint(toScreen: event.locationInWindow)
            window.setFrameOrigin(
                NSPoint(
                    x: manualDragWindowOrigin.x + currentLocation.x - manualDragStartLocation.x,
                    y: manualDragWindowOrigin.y + currentLocation.y - manualDragStartLocation.y
                )
            )
            return true

        case .leftMouseUp:
            guard manualDragStartLocation != nil else { return false }

            manualDragStartLocation = nil
            manualDragWindowOrigin = nil
            NSCursor.pop()
            return true

        default:
            return false
        }
    }

    private func isInScreenDragBand(_ event: NSEvent, window: NSWindow) -> Bool {
        guard let orientation = currentOrientation else { return false }

        let contentWidth = max(window.contentView?.bounds.width ?? window.frame.width, 1)
        let scale = max(contentWidth / orientation.screenSize.width, 0.1)
        let visibleBarHeight = PresentationMode.screen.screenDragBarHeight * scale
        let hitHeight = max(visibleBarHeight, 12)
        let contentHeight = window.contentView?.bounds.height ?? window.frame.height

        return event.locationInWindow.y >= contentHeight - hitHeight
    }

    private func installObservers(for window: NSWindow) {
        installDragEventMonitor()

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

        if let dragEventMonitor {
            NSEvent.removeMonitor(dragEventMonitor)
        }
        dragEventMonitor = nil
        manualDragStartLocation = nil
        manualDragWindowOrigin = nil
    }

    private func rememberCurrentWindowSize() {
        guard let window, let currentMode, let currentOrientation else { return }

        let contentSize = window.contentRect(forFrameRect: window.frame).size
        guard contentSize.width > 0, contentSize.height > 0 else { return }

        let defaults = UserDefaults.standard
        if currentMode == .workspace {
            defaults.set(contentSize.width, forKey: workspaceWidthKey)
            defaults.set(contentSize.height, forKey: workspaceHeightKey)
        } else {
            let baseSize = currentMode.contentSize(for: currentOrientation)
            guard baseSize.width > 0 else { return }
            defaults.set(contentSize.width / baseSize.width, forKey: scaleKey(for: currentMode))
        }
    }

    private func savedContentSize(
        for mode: PresentationMode,
        orientation: DeviceOrientation
    ) -> CGSize? {
        let defaults = UserDefaults.standard

        if mode == .workspace {
            let width = defaults.double(forKey: workspaceWidthKey)
            let height = defaults.double(forKey: workspaceHeightKey)
            guard width > 0, height > 0 else { return nil }
            return CGSize(width: width, height: height)
        }

        let scale = defaults.double(forKey: scaleKey(for: mode))
        guard scale > 0 else { return nil }
        return mode.contentSize(for: orientation, scale: scale)
    }

    private func scaleKey(for mode: PresentationMode) -> String {
        "Pocket.windowScale.\(mode.rawValue)"
    }

    private var workspaceWidthKey: String { "Pocket.workspaceWidth" }
    private var workspaceHeightKey: String { "Pocket.workspaceHeight" }

    private func configureChrome(
        for mode: PresentationMode,
        orientation: DeviceOrientation,
        window: NSWindow
    ) {
        let isWorkspace = mode == .workspace

        if isWorkspace {
            window.styleMask.remove(.borderless)
            window.styleMask.insert(.titled)
            window.styleMask.insert(.resizable)
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.hasShadow = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.contentAspectRatio = .zero
            window.contentView?.additionalSafeAreaInsets = NSEdgeInsets(
                top: 0,
                left: 0,
                bottom: 0,
                right: 0
            )
            setStandardWindowButtonsHidden(false, on: window)
        } else {
            // Keep a hidden titlebar in compact modes so AppKit can make the
            // window key and forward keyboard events to WKWebView controls.
            // The titlebar is transparent and the content fills the whole
            // window, so this remains visually frameless.
            window.styleMask.remove(.borderless)
            window.styleMask.insert(.titled)
            window.styleMask.insert(.resizable)
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.hasShadow = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.contentAspectRatio = mode.contentSize(for: orientation)
            removeSafeAreaInsets(from: window)
            setStandardWindowButtonsHidden(true, on: window)
        }
    }

    private func removeSafeAreaInsets(from window: NSWindow) {
        guard let contentView = window.contentView else { return }
        let insets = contentView.safeAreaInsets
        contentView.additionalSafeAreaInsets = NSEdgeInsets(
            top: -insets.top,
            left: -insets.left,
            bottom: -insets.bottom,
            right: -insets.right
        )
        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()
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
    private var dragStartLocation: NSPoint?
    private var windowStartOrigin: NSPoint?
    var showsIndicator = false {
        didSet {
            needsDisplay = true
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

    override var mouseDownCanMoveWindow: Bool { true }

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
        guard let window else { return }

        dragStartLocation = window.convertPoint(toScreen: event.locationInWindow)
        windowStartOrigin = window.frame.origin
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartLocation, let windowStartOrigin, let window else { return }

        let currentLocation = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(
            NSPoint(
                x: windowStartOrigin.x + currentLocation.x - dragStartLocation.x,
                y: windowStartOrigin.y + currentLocation.y - dragStartLocation.y
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        windowStartOrigin = nil
        NSCursor.pop()
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
    private var mouseEventMonitor: Any?
    private var isHovering = false

    deinit {
        removeMouseEventMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMouseEventMonitor()

        guard window != nil else {
            updateHoverState(false)
            return
        }

        mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.updateHoverState(for: event)
            return event
        }

        updateHoverState(atScreenLocation: NSEvent.mouseLocation)
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
        updateHoverState(true)
    }

    override func mouseExited(with event: NSEvent) {
        updateHoverState(false)
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

        let point = convert(event.locationInWindow, from: nil)
        updateHoverState(bounds.contains(point))
    }

    private func updateHoverState(atScreenLocation location: NSPoint) {
        guard let window else {
            updateHoverState(false)
            return
        }

        let windowPoint = window.convertPoint(fromScreen: location)
        let point = convert(windowPoint, from: nil)
        updateHoverState(bounds.contains(point))
    }

    private func updateHoverState(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        onHoverChanged?(hovering)
    }
}

struct HoverTrackingView: NSViewRepresentable {
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> HoverTrackingNSView {
        let view = HoverTrackingNSView(frame: .zero)
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: HoverTrackingNSView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
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
