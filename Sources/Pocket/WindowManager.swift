import AppKit
import SwiftUI

final class WindowManager {
    static let shared = WindowManager()

    private weak var window: NSWindow?
    private var alwaysOnTop = false
    private var lastContentSize: CGSize?
    private var currentMode: PresentationMode?
    private var currentOrientation: DeviceOrientation?
    private var currentLayout: ScreenLayout = .single
    private let defaults: UserDefaults
    private var resizeObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    deinit { removeObservers() }

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
        scale: CGFloat = 1.0,
        layout: ScreenLayout = .single,
        size: CGSize? = nil,
        animated: Bool = true,
        force: Bool = false
    ) {
        guard let window else { return }

        currentMode = mode
        currentOrientation = orientation
        currentLayout = mode == .screen ? layout : .single
        configureChrome(for: mode, orientation: orientation, window: window)

        let contentSize = size ?? (mode == .screen
            ? layout.contentSize(forPageSize: CGSize(width: orientation.screenSize.width * scale,
                                                     height: orientation.screenSize.height * scale))
            : mode.contentSize(for: orientation, scale: scale))
        if !force, let lastContentSize,
           abs(lastContentSize.width - contentSize.width) < 1,
           abs(lastContentSize.height - contentSize.height) < 1 {
            return
        }

        let oldFrame = window.frame
        window.contentMinSize = minimumContentSize(for: mode, orientation: orientation, layout: layout)
        window.setContentSize(contentSize)

        var newFrame = window.frame
        newFrame.origin.x = oldFrame.midX - newFrame.width / 2
        newFrame.origin.y = oldFrame.midY - newFrame.height / 2
        window.setFrame(newFrame, display: true, animate: animated)
        lastContentSize = contentSize
    }

    func ensureInitialSize(for mode: PresentationMode, orientation: DeviceOrientation, layout: ScreenLayout = .single) {
        guard lastContentSize == nil else { return }
        restoreSize(for: mode, orientation: orientation, layout: layout, animated: false)
    }

    func restoreSize(
        for mode: PresentationMode,
        orientation: DeviceOrientation,
        layout: ScreenLayout = .single,
        animated: Bool = true
    ) {
        resize(
            for: mode,
            orientation: orientation,
            layout: layout,
            size: savedContentSize(for: mode, orientation: orientation, layout: layout),
            animated: animated,
            force: true
        )
    }

    func changeScreenLayout(to layout: ScreenLayout) {
        guard let window, currentMode == .screen, currentLayout != layout else { return }
        // Read the actual window, not a stale cached size from before a drag.
        let oldFrame = window.frame
        let size = window.contentRect(forFrameRect: oldFrame).size
        let pageSize = currentLayout.pageSize(in: size)
        currentLayout = layout
        window.contentMinSize = layout.contentSize(forPageSize: ScreenLayout.minimumPageSize)
        window.setContentSize(layout.contentSize(forPageSize: pageSize))
        var frame = window.frame
        frame.origin = CGPoint(x: oldFrame.minX, y: oldFrame.maxY - frame.height)
        window.setFrame(frame, display: true)
        lastContentSize = window.contentRect(forFrameRect: window.frame).size
        rememberCurrentWindowSize()
    }

    private func minimumContentSize(for mode: PresentationMode, orientation: DeviceOrientation, layout: ScreenLayout) -> CGSize {
        mode == .screen ? layout.contentSize(forPageSize: ScreenLayout.minimumPageSize)
            : mode.contentSize(for: orientation, scale: mode.minimumScale)
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

        lastContentSize = contentSize
        if currentMode == .screen {
            let page = currentLayout.pageSize(in: contentSize)
            defaults.set(page.width, forKey: "Pocket.pageSize.\(currentOrientation.rawValue).width")
            defaults.set(page.height, forKey: "Pocket.pageSize.\(currentOrientation.rawValue).height")
            return
        }
        let baseSize = currentMode.contentSize(for: currentOrientation)
        guard baseSize.width > 0 else { return }
        defaults.set(
            contentSize.width / baseSize.width,
            forKey: scaleKey(for: currentMode)
        )
    }

    private func savedContentSize(
        for mode: PresentationMode,
        orientation: DeviceOrientation,
        layout: ScreenLayout
    ) -> CGSize? {
        if mode == .screen {
            let width = defaults.double(forKey: "Pocket.pageSize.\(orientation.rawValue).width")
            let height = defaults.double(forKey: "Pocket.pageSize.\(orientation.rawValue).height")
            if width > 0, height > 0 {
                return layout.contentSize(forPageSize: CGSize(width: max(width, ScreenLayout.minimumPageSize.width),
                    height: max(height, ScreenLayout.minimumPageSize.height)))
            }
            let storedScale = defaults.double(forKey: scaleKey(for: mode))
            let scale = storedScale > 0 ? max(storedScale, mode.minimumScale) : 1
            return layout.contentSize(forPageSize: CGSize(width: orientation.screenSize.width * scale,
                height: orientation.screenSize.height * scale))
        }
        let scale = defaults.double(forKey: scaleKey(for: mode))
        guard scale > 0 else { return nil }
        return mode.contentSize(for: orientation, scale: scale)
    }

    private func scaleKey(for mode: PresentationMode) -> String {
        "Pocket.windowScale.\(mode.rawValue)"
    }

    private func configureChrome(
        for mode: PresentationMode,
        orientation: DeviceOrientation,
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
        if mode == .screen {
            // Every screen is sized by one grid calculation. Allow free edge
            // resizing without AppKit applying a stale single-screen ratio.
            window.resizeIncrements = CGSize(width: 1, height: 1)
        } else {
            window.contentAspectRatio = mode.contentSize(for: orientation)
        }
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
