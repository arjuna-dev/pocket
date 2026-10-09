import AppKit
import SwiftUI

struct PaneSeamOverlay: NSViewRepresentable {
    var seams: [PaneDivider]
    var onChanged: (PaneDivider, CGPoint) -> Void
    var onEnded: (PaneDivider, CGPoint) -> Void

    func makeNSView(context: Context) -> PaneSeamOverlayView {
        let view = PaneSeamOverlayView()
        view.seams = seams
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ nsView: PaneSeamOverlayView, context: Context) {
        if !nsView.isDragging, nsView.seams != seams {
            nsView.seams = seams
            nsView.refreshTracking()
        }
        nsView.onChanged = onChanged
        nsView.onEnded = onEnded
    }
}

final class PaneSeamOverlayView: NSView {
    var seams: [PaneDivider] = []
    var onChanged: ((PaneDivider, CGPoint) -> Void)?
    var onEnded: ((PaneDivider, CGPoint) -> Void)?
    var isDragging = false
    private var activeSeam: PaneDivider?
    private var isRefreshingTracking = false
    private var trackedBounds: CGRect = .zero

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("PaneSeamOverlayView is created in code")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local), seam(at: stagePoint(fromLocal: local)) != nil else { return nil }
        return self
    }

    override func layout() {
        super.layout()
        guard bounds != trackedBounds else { return }
        trackedBounds = bounds
        refreshTracking()
    }

    override func resetCursorRects() {
        for seam in seams {
            addCursorRect(viewRect(for: seam.hitRect), cursor: resizeCursor(for: seam))
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTracking()
    }

    func refreshTracking() {
        guard !isRefreshingTracking else { return }
        isRefreshingTracking = true
        defer { isRefreshingTracking = false }
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        for seam in seams {
            let area = NSTrackingArea(
                rect: viewRect(for: seam.hitRect),
                options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways],
                owner: self,
                userInfo: ["seam": seam.id]
            )
            addTrackingArea(area)
        }
        window?.invalidateCursorRects(for: self)
    }

    override func cursorUpdate(with event: NSEvent) {
        showResizeCursor(for: event)
    }

    override func mouseEntered(with event: NSEvent) {
        showResizeCursor(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        showResizeCursor(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        guard !isDragging else { return }
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        let point = stagePoint(from: event)
        guard let seam = seam(at: point) else { return }
        isDragging = true
        activeSeam = seam
        resizeCursor(for: seam).set()
        onChanged?(seam, point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let seam = activeSeam else { return }
        resizeCursor(for: seam).set()
        onChanged?(seam, stagePoint(from: event))
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging, let seam = activeSeam else { return }
        isDragging = false
        activeSeam = nil
        onEnded?(seam, stagePoint(from: event))
    }

    private func showResizeCursor(for event: NSEvent) {
        guard let seam = seam(at: stagePoint(from: event)) else { return }
        let cursor = resizeCursor(for: seam)
        cursor.set()
        // Web content sets its own cursor during the same mouse move. Reapply
        // after that so the resize arrow wins while the pointer stays on the seam.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            let local = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            guard let seam = self.seam(at: self.stagePoint(fromLocal: local)) else { return }
            self.resizeCursor(for: seam).set()
        }
    }

    private func resizeCursor(for seam: PaneDivider) -> NSCursor {
        seam.axis == .horizontal ? .resizeUpDown : .resizeLeftRight
    }

    private func seam(at point: CGPoint) -> PaneDivider? {
        seams.first { $0.hitRect.contains(point) }
    }

    private func stagePoint(from event: NSEvent) -> CGPoint {
        stagePoint(fromLocal: convert(event.locationInWindow, from: nil))
    }

    private func stagePoint(fromLocal local: NSPoint) -> CGPoint {
        if isFlipped {
            return CGPoint(x: local.x, y: local.y)
        }
        return CGPoint(x: local.x, y: bounds.height - local.y)
    }

    private func viewRect(for stage: CGRect) -> NSRect {
        if isFlipped {
            return NSRect(x: stage.minX, y: stage.minY, width: stage.width, height: stage.height)
        }
        return NSRect(
            x: stage.minX,
            y: bounds.height - stage.maxY,
            width: stage.width,
            height: stage.height
        )
    }
}

