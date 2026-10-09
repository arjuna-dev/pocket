import AppKit
import SwiftUI
import WebKit

struct PocketStageView: View {
    @ObservedObject var model: PocketModel
    @ObservedObject private var windowManager = WindowManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var topBarVisible = false
    @State private var bottomBarVisible = false
    @State private var topShowWork: DispatchWorkItem?
    @State private var topHideWork: DispatchWorkItem?
    @State private var bottomShowWork: DispatchWorkItem?
    @State private var bottomHideWork: DispatchWorkItem?
    @State private var drag = DividerDragBox()
    @State private var liveLayout: PaneLayout?

    var body: some View {
        GeometryReader { proxy in
            let canvas = CGSize(width: max(proxy.size.width, 1), height: max(proxy.size.height, 1))
            let display = liveLayout ?? model.paneLayout
            let interaction = drag.session?.start ?? display
            let frames = display.frames(in: canvas)

            ZStack(alignment: .topLeading) {
                Color.clear
                    .allowsHitTesting(false)

                ForEach(model.slots) { slot in
                    if let frame = frames[slot.index] {
                        ScreenPane(
                            model: model,
                            slot: slot,
                            controller: slot.controller,
                            isFocused: slot.index == model.activeSlot?.index,
                            showsFocusBorder: display.leafCount > 1 && chromeShown,
                            chromeShown: chromeShown
                        )
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                    }
                }

                ForEach(display.dividers(in: canvas)) { divider in
                    Rectangle()
                        .fill(Color.white.opacity(0.22))
                        .frame(
                            width: divider.axis == .horizontal ? divider.bounds.width : 1,
                            height: divider.axis == .horizontal ? 1 : divider.bounds.height
                        )
                        .offset(
                            x: divider.axis == .horizontal ? divider.bounds.minX : divider.splitPosition - 0.5,
                            y: divider.axis == .horizontal ? divider.splitPosition - 0.5 : divider.bounds.minY
                        )
                        .allowsHitTesting(false)
                }

                PaneSeamOverlay(seams: interaction.dividers(in: canvas)) { seam, point in
                    let session: DividerDragSession
                    if let existing = drag.session {
                        session = existing
                    } else {
                        let cross = seam.axis == .horizontal ? point.x : point.y
                        session = DividerDragSession(
                            divider: seam,
                            start: model.paneLayout,
                            cross: cross,
                            canvas: canvas
                        )
                        drag.session = session
                    }
                    liveLayout = session.preview(at: point)
                } onEnded: { _, point in
                    if let session = drag.session {
                        model.updatePaneLayout(session.preview(at: point))
                    }
                    drag.session = nil
                    liveLayout = nil
                }
                .frame(width: canvas.width, height: canvas.height)

                if drag.session == nil {
                    ForEach(Array(display.gaps(in: canvas).enumerated()), id: \.offset) { _, gap in
                        Color.black
                            .frame(width: gap.width, height: gap.height)
                            .offset(x: gap.minX, y: gap.minY)
                            .allowsHitTesting(false)
                    }
                    let gapStrips = display.gapStrips(in: canvas)
                    ForEach(gapStrips) { strip in
                        PocketAddStripButton(help: strip.help, corners: .square) {
                            model.fillGap()
                        }
                        .pocketFade(chromeShown)
                        .animation(PocketMotion.fade(reduceMotion), value: chromeShown)
                        .frame(width: strip.rect.width, height: strip.rect.height)
                        .offset(x: strip.rect.minX, y: strip.rect.minY)
                    }
                }
            }
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
            .clipped()
            .background(model.presentationMode == .screen ? Color.black : Color.clear)
            .overlay {
                HoverTrackingView(
                    onHoverChanged: { hovering in
                        if hovering {
                            scheduleShow(top: true)
                            scheduleShow(top: false)
                        } else {
                            scheduleHide(top: true)
                            scheduleHide(top: false)
                        }
                    },
                    onLocationChanged: { point in
                        guard point != nil else { return }
                        scheduleShow(top: true)
                        scheduleShow(top: false)
                    },
                    onMouseDown: { point in
                        focusPane(at: point, in: canvas)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            }
        }
        .onPreferenceChange(ChromeControlFocusedKey.self) { focused in
            WindowManager.shared.setChromeFocused(focused, source: "stage")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(model.presentationMode == .screen ? Color.black : Color.clear)
        .onAppear {
            WindowManager.shared.setChromeVisible(chromeShown)
        }
        .onChange(of: chromeShown) { _, shown in
            WindowManager.shared.setChromeVisible(shown)
        }
    }

    private var chromeShown: Bool {
        topBarVisible || bottomBarVisible || model.isSiteMenuPresented || model.isScreenRemovalPresented
            || windowManager.accessibilityFocusKeepsChrome
    }

    private func focusPane(at point: CGPoint, in canvas: CGSize) {
        let layout = liveLayout ?? model.paneLayout
        guard let index = layout.leafID(at: point, in: canvas) else { return }
        guard model.focusedSlotIndex != index else { return }
        model.focusedSlotIndex = index
    }

    private func scheduleShow(top: Bool) {
        cancelHide(top: top)
        if top ? topBarVisible : bottomBarVisible {
            return
        }
        let pending = top ? topShowWork : bottomShowWork
        guard pending == nil else { return }

        let work = DispatchWorkItem {
            withAnimation(PocketMotion.fade(reduceMotion, duration: 0.22)) {
                if top {
                    topBarVisible = true
                } else {
                    bottomBarVisible = true
                }
            }
            if top {
                topShowWork = nil
            } else {
                bottomShowWork = nil
            }
        }
        if top {
            topShowWork = work
        } else {
            bottomShowWork = work
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + CompactLayout.revealDelay, execute: work)
    }

    private func scheduleHide(top: Bool) {
        cancelShow(top: top)
        if top ? !topBarVisible : !bottomBarVisible {
            return
        }
        if top, model.isSiteMenuPresented { return }

        let pending = top ? topHideWork : bottomHideWork
        guard pending == nil else { return }

        let work = DispatchWorkItem {
            withAnimation(PocketMotion.fade(reduceMotion, duration: 0.22)) {
                if top {
                    topBarVisible = false
                } else {
                    bottomBarVisible = false
                }
            }
            if top {
                topHideWork = nil
            } else {
                bottomHideWork = nil
            }
        }
        if top {
            topHideWork = work
        } else {
            bottomHideWork = work
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + CompactLayout.hideDelay, execute: work)
    }

    private func cancelShow(top: Bool) {
        if top {
            topShowWork?.cancel()
            topShowWork = nil
        } else {
            bottomShowWork?.cancel()
            bottomShowWork = nil
        }
    }

    private func cancelHide(top: Bool) {
        if top {
            topHideWork?.cancel()
            topHideWork = nil
        } else {
            bottomHideWork?.cancel()
            bottomHideWork = nil
        }
    }

}

private final class DividerDragBox {
    var session: DividerDragSession?
}


private struct ScreenPane: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var slot: ScreenSlot
    @ObservedObject var controller: WebViewController
    var isFocused: Bool
    var showsFocusBorder: Bool
    var chromeShown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var focusBorderColor: Color {
        controller.pageUsesDarkBackground ? Color.white.opacity(0.82) : Color.black.opacity(0.5)
    }

    private var canAddTrailing: Bool {
        model.paneLayout.root.gridSpan.columns == 1
    }

    private var canAddBelow: Bool {
        model.paneLayout.root.gridSpan.rows == 1
    }

    var body: some View {
        ZStack {
            if model.presentationMode == .device {
                deviceContent
            } else {
                WebContent(controller: slot.controller, cornerRadius: 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay {
            Rectangle()
                .strokeBorder(focusBorderColor, lineWidth: CompactLayout.focusBorderWidth)
                .opacity(showsFocusBorder && isFocused ? 1 : 0)
                .animation(PocketMotion.fade(reduceMotion), value: isFocused)
                .animation(PocketMotion.fade(reduceMotion), value: showsFocusBorder)
                .animation(PocketMotion.fade(reduceMotion), value: controller.pageUsesDarkBackground)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .focusedScreenAccessibility(
            title: slot.app.title,
            isFocused: isFocused,
            announceFocus: model.slots.count > 1
        )
        .accessibilityActionIf(!chromeShown && canAddTrailing, "Add a screen to the right") {
            model.split(slot, at: .trailing)
        }
        .accessibilityActionIf(!chromeShown && canAddBelow, "Add a screen below") {
            model.split(slot, at: .bottom)
        }
    }

    private var deviceContent: some View {
        GeometryReader { proxy in
            let deviceSize = model.orientation.deviceSize
            let scale = max(
                min(
                    proxy.size.width / deviceSize.width,
                    proxy.size.height / deviceSize.height
                ),
                0.1
            )

            DeviceFrame(
                app: slot.app,
                controller: slot.controller,
                orientation: model.orientation
            )
            .frame(width: deviceSize.width * scale, height: deviceSize.height * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

