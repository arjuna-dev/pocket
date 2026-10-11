import AppKit
import SwiftUI

// Only visibility changes publish. Pointer motion extends a deadline without
// rebuilding the SwiftUI tree or scheduling a timer for every mouse event.
final class ScreenChromeActivity: ObservableObject {
    @Published private(set) var screenID: Int?
    private var lastActivity = ProcessInfo.processInfo.systemUptime
    private var hideWork: DispatchWorkItem?
    private var held = false
    private var menuTracking = false
    private var observers: [NSObjectProtocol] = []
    let timeout: TimeInterval

    init(timeout: TimeInterval = 3) {
        self.timeout = timeout
        observers.append(NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.menuTracking = true })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.menuTracking = false
            if let id = self.screenID { self.activate(id) }
        })
    }

    deinit {
        hideWork?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func activate(_ id: Int) {
        lastActivity = ProcessInfo.processInfo.systemUptime
        if screenID != id { screenID = id }
        if hideWork == nil { scheduleHide(after: timeout) }
    }

    func hold(_ value: Bool) {
        held = value
        if !value, let id = screenID { activate(id) }
    }

    func leave() {
        guard !held, !menuTracking else { return }
        hideWork?.cancel()
        hideWork = nil
        screenID = nil
    }

    private func scheduleHide(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hideWork = nil
            let remaining = self.timeout - (ProcessInfo.processInfo.systemUptime - self.lastActivity)
            if self.held || self.menuTracking {
                self.scheduleHide(after: self.timeout)
            } else if remaining > 0 {
                self.scheduleHide(after: remaining)
            } else {
                self.screenID = nil
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

struct ScreenActivityTrackingView: NSViewRepresentable {
    let onActivity: (CGPoint) -> Void
    let onExit: () -> Void

    func makeNSView(context: Context) -> ScreenActivityNSView {
        let view = ScreenActivityNSView()
        view.onActivity = onActivity
        view.onExit = onExit
        return view
    }

    func updateNSView(_ view: ScreenActivityNSView, context: Context) {
        view.onActivity = onActivity
        view.onExit = onExit
    }
}

final class ScreenActivityNSView: NSView {
    var onActivity: ((CGPoint) -> Void)?
    var onExit: (() -> Void)?
    private var monitor: Any?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit { removeMonitor() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
        ]) { [weak self] event in
            self?.handlePointerMovement(event)
            return event
        }
    }

    func handlePointerMovement(_ event: NSEvent) {
        guard [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(event.type),
              let window, event.window?.windowNumber == window.windowNumber else { return }
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) { onActivity?(point) } else { onExit?() }
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onActivity?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) { onExit?() }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
