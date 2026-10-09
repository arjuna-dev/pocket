import AppKit
import SwiftUI
import WebKit

struct PocketRightAddStrips: View {
    @ObservedObject var model: PocketModel

    var body: some View {
        GeometryReader { proxy in
            let strips = stripFrames(in: proxy.size)
            ZStack(alignment: .topLeading) {
                ForEach(Array(strips.enumerated()), id: \.element.id) { index, strip in
                    PocketAddStripButton(
                        help: "Add a screen to the right",
                        corners: .verticalPair(index: index, count: strips.count)
                    ) {
                        guard let slot = model.slots.first(where: { $0.index == strip.id }) else { return }
                        model.split(slot, at: .trailing)
                    }
                    .frame(width: proxy.size.width, height: strip.rect.height)
                    .offset(y: strip.rect.minY)
                }
            }
        }
    }

    /// One rail beside the only screen, or one strip beside each screen when
    /// they are stacked and nothing sits to their right.
    private func stripFrames(in size: CGSize) -> [(id: Int, rect: CGRect)] {
        let layout = model.paneLayout
        guard layout.root.gridSpan.columns == 1, size.height > 1 else { return [] }
        if layout.leafCount == 1, let id = layout.leafIDs.first {
            return [(id: id, rect: CGRect(x: 0, y: 0, width: 1, height: size.height))]
        }
        guard layout.root.gridSpan.rows > 1 else { return [] }
        let frames = layout.frames(in: CGSize(width: 1000, height: size.height))
        let panes = frames
            .map { (id: $0.key, rect: $0.value) }
            .sorted { $0.rect.minY < $1.rect.minY }
        return panes.map { pane in
            (id: pane.id, rect: CGRect(x: 0, y: pane.rect.minY, width: 1, height: max(pane.rect.height, 1)))
        }
    }
}

struct PocketBottomAddStrips: View {
    @ObservedObject var model: PocketModel

    var body: some View {
        GeometryReader { proxy in
            let strips = stripFrames(in: proxy.size.width)
            ZStack(alignment: .topLeading) {
                Color.pocketChrome
                ForEach(strips, id: \.id) { strip in
                    PocketAddStripButton(
                        help: "Add a screen below",
                        corners: .square
                    ) {
                        guard let slot = model.slots.first(where: { $0.index == strip.id }) else { return }
                        model.split(slot, at: .bottom)
                    }
                    .frame(width: strip.rect.width, height: proxy.size.height)
                    .offset(x: strip.rect.minX)
                }
            }
        }
    }

    /// One strip under each screen when nothing is stacked below them.
    private func stripFrames(in width: CGFloat) -> [(id: Int, rect: CGRect)] {
        let layout = model.paneLayout
        guard layout.root.gridSpan.rows == 1, width > 1 else { return [] }
        let frames = layout.frames(in: CGSize(width: width, height: 1000))
        let panes = frames
            .map { (id: $0.key, rect: $0.value) }
            .sorted { $0.rect.minX < $1.rect.minX }
        return panes.map { pane in
            (id: pane.id, rect: CGRect(x: pane.rect.minX, y: 0, width: max(pane.rect.width, 1), height: 1))
        }
    }
}

struct StripCorners: Equatable {
    var topLeading: CGFloat
    var topTrailing: CGFloat
    var bottomLeading: CGFloat
    var bottomTrailing: CGFloat

    static let square = StripCorners(topLeading: 0, topTrailing: 0, bottomLeading: 0, bottomTrailing: 0)

    static func uniform(_ radius: CGFloat) -> StripCorners {
        StripCorners(
            topLeading: radius,
            topTrailing: radius,
            bottomLeading: radius,
            bottomTrailing: radius
        )
    }

    static func horizontalPair(index: Int, count: Int, radius: CGFloat = 8) -> StripCorners {
        guard count > 1 else { return .uniform(radius) }
        if index == 0 {
            return StripCorners(topLeading: radius, topTrailing: 0, bottomLeading: radius, bottomTrailing: 0)
        }
        if index == count - 1 {
            return StripCorners(topLeading: 0, topTrailing: radius, bottomLeading: 0, bottomTrailing: radius)
        }
        return .square
    }

    /// The side facing the screen stays square so the strip sits against that edge.
    static func verticalPair(index: Int, count: Int, radius: CGFloat = 10) -> StripCorners {
        if count <= 1 {
            return StripCorners(topLeading: 0, topTrailing: radius, bottomLeading: 0, bottomTrailing: radius)
        }
        if index == 0 {
            return StripCorners(topLeading: 0, topTrailing: radius, bottomLeading: 0, bottomTrailing: 0)
        }
        if index == count - 1 {
            return StripCorners(topLeading: 0, topTrailing: 0, bottomLeading: 0, bottomTrailing: radius)
        }
        return .square
    }

    fileprivate var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topLeading,
            bottomLeadingRadius: bottomLeading,
            bottomTrailingRadius: bottomTrailing,
            topTrailingRadius: topTrailing,
            style: .continuous
        )
    }
}

struct PocketAddStripButton: View {
    var help: String
    var corners: StripCorners = .uniform(8)
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                corners.shape
                    .fill(Color.pocketChrome)
                corners.shape
                    .strokeBorder(Color.white.opacity(hovering ? 0.28 : 0.16), lineWidth: 1)
                ZStack {
                    Circle()
                        .fill(hovering ? Color.white : Color.white.opacity(0.08))
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(hovering ? Color.black.opacity(0.88) : Color.white.opacity(0.92))
                }
                .frame(width: 20, height: 20)
                .scaleEffect(hovering ? 1.08 : 1)
            }
            .animation(PocketMotion.fade(reduceMotion, duration: 0.14), value: hovering)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background {
                StripHoverProbe(hovering: $hovering)
            }
        }
        .buttonStyle(.plain)
        .help(help)
        .chromeControl(label: help)
    }
}

private struct StripHoverProbe: NSViewRepresentable {
    @Binding var hovering: Bool

    func makeNSView(context: Context) -> StripHoverProbeView {
        let view = StripHoverProbeView()
        view.onChange = { hovering = $0 }
        return view
    }

    func updateNSView(_ nsView: StripHoverProbeView, context: Context) {
        nsView.onChange = { hovering = $0 }
    }
}

private final class StripHoverProbeView: NSView {
    var onChange: ((Bool) -> Void)?
    private var monitor: Any?
    private var hovering = false

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard window != nil else {
            setHovering(false)
            return
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.track(event)
            return event
        }
        track(nil)
    }

    private func track(_ event: NSEvent?) {
        guard let window else {
            setHovering(false)
            return
        }
        let location = event?.locationInWindow ?? window.mouseLocationOutsideOfEventStream
        guard event == nil || event?.window === window else {
            setHovering(false)
            return
        }
        let local = convert(location, from: nil)
        setHovering(bounds.contains(local))
    }

    private func setHovering(_ value: Bool) {
        guard hovering != value else { return }
        hovering = value
        onChange?(value)
    }
}

final class PocketStripHost<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}

