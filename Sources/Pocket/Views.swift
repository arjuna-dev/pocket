import AppKit
import SwiftUI
import WebKit

private extension Color {
    static let pocketBackground = Color(red: 0.055, green: 0.063, blue: 0.082)
    static let pocketChrome = Color(red: 0.145, green: 0.155, blue: 0.175)
    static let pocketMuted = Color(red: 0.48, green: 0.50, blue: 0.57)
}

struct AppRootView: View {
    @ObservedObject var model: PocketModel

    var body: some View {
        PocketStageView(model: model)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(Color.clear)
        .background(
            WindowBridge { window in
                WindowManager.shared.attach(window: window)
                WindowManager.shared.setAlwaysOnTop(model.alwaysOnTop)
                WindowManager.shared.ensureInitialSize(
                    for: model.presentationMode,
                    orientation: model.orientation,
                    screenCount: model.screenLayoutCount
                )
            }
            .frame(width: 1, height: 1)
        )
        .onAppear {
            model.applyPresentationMode()
            WindowManager.shared.restoreSize(
                for: model.presentationMode,
                orientation: model.orientation,
                screenCount: model.screenLayoutCount,
                animated: false
            )
        }
        .onChange(of: model.presentationMode) { _, newMode in
            model.applyPresentationMode()
            WindowManager.shared.restoreSize(
                for: newMode,
                orientation: model.orientation,
                screenCount: model.screenLayoutCount,
                animated: true
            )
        }
        .onChange(of: model.orientation) { _, newOrientation in
            WindowManager.shared.restoreSize(
                for: model.presentationMode,
                orientation: newOrientation,
                screenCount: model.screenLayoutCount,
                animated: true
            )
        }
        .onChange(of: model.screenLayoutCount) { _, newCount in
            WindowManager.shared.restoreSize(
                for: model.presentationMode,
                orientation: model.orientation,
                screenCount: newCount,
                animated: true
            )
        }
        .onChange(of: model.alwaysOnTop) { _, newValue in
            WindowManager.shared.setAlwaysOnTop(newValue)
        }
        .sheet(item: rootSheet) { sheet in
            switch sheet {
            case .websites:
                WebsiteManagerSheet(model: model)
            case .browserImport:
                BrowserImportSheet(model: model)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var rootSheet: Binding<PocketRootSheet?> {
        Binding(
            get: {
                if model.isBrowserImportPresented { return .browserImport }
                if model.isWebsiteManagerPresented { return .websites }
                return nil
            },
            set: { sheet in
                model.isWebsiteManagerPresented = sheet == .websites
                model.isBrowserImportPresented = sheet == .browserImport
            }
        )
    }
}

private enum PocketRootSheet: Identifiable {
    case websites
    case browserImport

    var id: String {
        switch self {
        case .websites: return "websites"
        case .browserImport: return "browserImport"
        }
    }
}

struct PocketStageView: View {
    @ObservedObject var model: PocketModel
    @State private var topBarVisible = false
    @State private var bottomBarVisible = false
    @State private var siteMenuOpen = false
    @State private var layoutMenuOpen = false
    @State private var topShowWork: DispatchWorkItem?
    @State private var topHideWork: DispatchWorkItem?
    @State private var bottomShowWork: DispatchWorkItem?
    @State private var bottomHideWork: DispatchWorkItem?

    var body: some View {
        GeometryReader { proxy in
            let count = max(model.visibleSlots.count, 1)
            let availableWidth = max(proxy.size.width, 1)
            let showsTop = topBarVisible || siteMenuOpen
            let showsBottom = bottomBarVisible || layoutMenuOpen
            let topHeight = showsTop ? CompactLayout.screenBarHeight : 0
            let bottomHeight = showsBottom ? CompactLayout.controlsStripHeight : 0
            let totalHeight = max(proxy.size.height, 1)
            let contentHeight = max(totalHeight - topHeight - bottomHeight, 1)
            let grid = gridMetrics(count: count)
            let gapX: CGFloat = grid.columns > 1 ? CompactLayout.paneGap : 0
            let gapY: CGFloat = grid.rows > 1 ? CompactLayout.paneGap : 0

            VStack(spacing: 0) {
                if showsTop, let active = model.activeSlot {
                    sharedTopBar(for: active)
                        .transition(.move(edge: .top))
                }

                paneGrid(
                    count: count,
                    width: availableWidth,
                    height: contentHeight,
                    columns: grid.columns,
                    rows: grid.rows,
                    gapX: gapX,
                    gapY: gapY
                )

                if showsBottom {
                    bottomChrome
                        .transition(.move(edge: .bottom))
                }
            }
            .frame(width: availableWidth, height: totalHeight, alignment: .top)
            .background(model.presentationMode == .screen ? Color.black : Color.clear)
            .animation(.easeOut(duration: 0.22), value: showsTop)
            .animation(.easeOut(duration: 0.22), value: showsBottom)
            .overlay {
                HoverTrackingView(
                    onHoverChanged: { hovering in
                        if !hovering {
                            scheduleHide(top: true)
                            scheduleHide(top: false)
                        }
                    },
                    onLocationChanged: { point in
                        guard let point else { return }
                        let inTop = point.y < (showsTop ? topHeight : CompactLayout.topRevealHeight)
                        if inTop {
                            scheduleShow(top: true)
                        } else {
                            scheduleHide(top: true)
                        }

                        let inBottom = point.y > totalHeight - (showsBottom ? bottomHeight : CompactLayout.bottomRevealHeight)
                        if inBottom {
                            scheduleShow(top: false)
                        } else {
                            scheduleHide(top: false)
                        }
                    },
                    onMouseDown: { point in
                        guard point.y >= topHeight, point.y <= totalHeight - bottomHeight else { return }
                        let contentPoint = CGPoint(x: point.x, y: point.y - topHeight)
                        let contentSize = CGSize(width: availableWidth, height: contentHeight)
                        if let index = slotIndex(at: contentPoint, size: contentSize, count: count) {
                            model.focusedSlotIndex = index
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(model.presentationMode == .screen ? Color.black : Color.clear)
    }

    private func sharedTopBar(for active: ScreenSlot) -> some View {
        ScreenControlsBar(
            model: model,
            slot: active,
            showsWindowButtons: true,
            isSiteMenuPresented: $siteMenuOpen
        )
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: CompactLayout.screenBarHeight)
        .background(Color.pocketChrome)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
        .id(active.index)
    }

    private var bottomChrome: some View {
        Color.pocketChrome
            .frame(height: CompactLayout.controlsStripHeight)
            .frame(maxWidth: .infinity)
            .overlay {
                CompactControls(
                    model: model,
                    isLayoutMenuPresented: $layoutMenuOpen
                )
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }
    }

    private func scheduleShow(top: Bool) {
        cancelHide(top: top)
        if top ? topBarVisible : bottomBarVisible {
            return
        }
        let pending = top ? topShowWork : bottomShowWork
        guard pending == nil else { return }

        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.22)) {
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
        if top, siteMenuOpen { return }
        if !top, layoutMenuOpen { return }

        let pending = top ? topHideWork : bottomHideWork
        guard pending == nil else { return }

        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.22)) {
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

    @ViewBuilder
    private func paneGrid(
        count: Int,
        width: CGFloat,
        height: CGFloat,
        columns: Int,
        rows: Int,
        gapX: CGFloat,
        gapY: CGFloat
    ) -> some View {
        VStack(spacing: gapY) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: gapX) {
                    ForEach(0..<columns, id: \.self) { column in
                        let paneWidth = paneLength(
                            index: column,
                            count: columns,
                            total: width,
                            gap: gapX
                        )
                        let paneHeight = paneLength(
                            index: row,
                            count: rows,
                            total: height,
                            gap: gapY
                        )
                        if let slot = slot(row: row, column: column, count: count) {
                            ScreenPane(
                                model: model,
                                slot: slot,
                                isFocused: slot.index == model.activeSlot?.index,
                                showsFocusLine: count > 1
                            )
                            .frame(width: paneWidth, height: paneHeight)
                        } else {
                            Color.clear
                                .frame(width: paneWidth, height: paneHeight)
                        }
                    }
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func gridMetrics(count: Int) -> (columns: Int, rows: Int) {
        let columns = count <= 2 ? 1 : 2
        let rows = count == 1 ? 1 : 2
        return (columns, rows)
    }

    private func paneLength(index: Int, count: Int, total: CGFloat, gap: CGFloat) -> CGFloat {
        let available = max(total - gap * CGFloat(max(count - 1, 0)), 1)
        let base = floor(available / CGFloat(count))
        if index == count - 1 {
            return available - base * CGFloat(count - 1)
        }
        return base
    }

    private func slot(row: Int, column: Int, count: Int) -> ScreenSlot? {
        let index = column == 0 ? row : 2 + row
        guard index < count else { return nil }
        return model.slots.first { $0.index == index }
    }

    private func slotIndex(at point: CGPoint, size: CGSize, count: Int) -> Int? {
        let grid = gridMetrics(count: count)
        let gapX: CGFloat = grid.columns > 1 ? CompactLayout.paneGap : 0
        let gapY: CGFloat = grid.rows > 1 ? CompactLayout.paneGap : 0
        guard let column = paneIndex(at: point.x, count: grid.columns, total: size.width, gap: gapX),
              let row = paneIndex(at: point.y, count: grid.rows, total: size.height, gap: gapY)
        else {
            return nil
        }

        let index = column == 0 ? row : 2 + row
        guard index < count else { return nil }
        return index
    }

    private func paneIndex(at position: CGFloat, count: Int, total: CGFloat, gap: CGFloat) -> Int? {
        var origin: CGFloat = 0
        for index in 0..<count {
            let length = paneLength(index: index, count: count, total: total, gap: gap)
            if position >= origin && position < origin + length {
                return index
            }
            origin += length + gap
        }
        return nil
    }
}

private struct ScreenPane: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var slot: ScreenSlot
    var isFocused: Bool
    var showsFocusLine: Bool

    var body: some View {
        Group {
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
        .overlay(alignment: .top) {
            Rectangle()
                .fill(slot.app.tint)
                .frame(height: CompactLayout.focusLineHeight)
                .opacity(showsFocusLine && isFocused ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .allowsHitTesting(false)
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

private struct WindowTrafficLights: View {
    @State private var areButtonIconsVisible = false

    var body: some View {
        HStack(spacing: 4) {
            WindowActionButton(
                symbol: "xmark",
                color: Color(red: 1.0, green: 0.36, blue: 0.34),
                help: "Close Pocket",
                showsIcon: areButtonIconsVisible,
                action: WindowManager.shared.closeWindow
            )

            WindowActionButton(
                symbol: "minus",
                color: Color(red: 1.0, green: 0.75, blue: 0.25),
                help: "Minimize Pocket",
                showsIcon: areButtonIconsVisible,
                action: WindowManager.shared.minimizeWindow
            )

            WindowActionButton(
                symbol: "arrow.up.left.and.arrow.down.right",
                color: Color(red: 0.34, green: 0.82, blue: 0.45),
                help: "Zoom Pocket",
                showsIcon: areButtonIconsVisible,
                action: WindowManager.shared.zoomWindow
            )
        }
        .onHover { areButtonIconsVisible = $0 }
    }
}

struct CompactControls: View {
    @ObservedObject var model: PocketModel
    @Binding var isLayoutMenuPresented: Bool
    @State private var isOrientationHovering = false

    private static let orientationHoverText = "Cmd + 1 - Portrait, Cmd + 2 - Landscape"

    var body: some View {
        ViewThatFits(in: .horizontal) {
            controlsBar(showsTitles: true)
            controlsBar(showsTitles: false)
        }
    }

    private func controlsBar(showsTitles: Bool) -> some View {
        HStack(spacing: showsTitles ? 10 : 6) {
            CompactChromeButton(
                symbol: model.orientation == .portrait ? "iphone" : "iphone.landscape",
                title: model.orientation.title,
                showsTitle: showsTitles,
                showsHoverTitle: false
            ) {
                model.orientation = model.orientation == .portrait ? .landscape : .portrait
            }
            .onHover { isOrientationHovering = $0 }

            CompactLayoutMenu(
                model: model,
                showsTitle: showsTitles,
                isPresented: $isLayoutMenuPresented
            )

            CompactChromeButton(
                symbol: model.alwaysOnTop ? "pin.fill" : "pin",
                title: "Pin",
                showsTitle: showsTitles
            ) {
                model.alwaysOnTop.toggle()
            }

            CompactChromeButton(
                symbol: "slider.horizontal.3",
                title: "Manage sites",
                showsTitle: showsTitles
            ) {
                model.isWebsiteManagerPresented = true
            }
        }
        .padding(.horizontal, showsTitles ? 12 : 10)
        .overlay(alignment: .top) {
            if isOrientationHovering {
                Text(Self.orientationHoverText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(Color(white: 0.22))
                    }
                    .fixedSize()
                    .offset(y: -32)
                    .allowsHitTesting(false)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct CompactSiteSwitcher: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var slot: ScreenSlot
    @Binding var isPresented: Bool

    var body: some View {
        HStack(spacing: 8) {
            ServiceIcon(app: slot.app, size: 16)
                .layoutPriority(1)

            Text(slot.app.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)

            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.72))
                .layoutPriority(1)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.06))
        }
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
        .contentShape(Capsule())
        .onTapGesture {
            isPresented = true
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Switch app")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            CompactSiteMenu(model: model, slot: slot, isPresented: $isPresented)
                .presentationBackground {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.145, green: 0.155, blue: 0.175))
                }
        }
        .help("Switch app")
    }
}

private struct ScreenControlsBar: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var slot: ScreenSlot
    var showsWindowButtons: Bool
    @Binding var isSiteMenuPresented: Bool

    var body: some View {
        ScreenNavigationControls(
            model: model,
            slot: slot,
            controller: slot.controller,
            showsWindowButtons: showsWindowButtons,
            isSiteMenuPresented: $isSiteMenuPresented
        )
    }
}

private struct ScreenNavigationControls: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var slot: ScreenSlot
    @ObservedObject var controller: WebViewController
    var showsWindowButtons: Bool
    @Binding var isSiteMenuPresented: Bool

    var body: some View {
        HStack(spacing: 10) {
            if showsWindowButtons {
                WindowTrafficLights()
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }

            HStack(spacing: 8) {
                CompactControlButton(
                    symbol: "chevron.left",
                    help: "Back",
                    disabled: !controller.canGoBack
                ) {
                    model.focusedSlotIndex = slot.index
                    controller.goBack()
                }

                CompactControlButton(
                    symbol: "chevron.right",
                    help: "Forward",
                    disabled: !controller.canGoForward
                ) {
                    model.focusedSlotIndex = slot.index
                    controller.goForward()
                }

                CompactControlButton(symbol: "arrow.clockwise", help: "Reload") {
                    model.focusedSlotIndex = slot.index
                    controller.reloadPage()
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)

            Spacer(minLength: 8)

            CompactSiteSwitcher(model: model, slot: slot, isPresented: $isSiteMenuPresented)
                .layoutPriority(1)
                .frame(minWidth: 0, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CompactLayout.windowControlsBayHeight)
        .clipped()
    }
}

private struct WindowActionButton: View {
    let symbol: String
    let color: Color
    let help: String
    let showsIcon: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                .frame(width: 14, height: 14)

                Image(systemName: symbol)
                    .font(.system(size: 6, weight: .heavy))
                    .foregroundStyle(Color.black.opacity(0.78))
                    .opacity(showsIcon ? 1 : 0)
                    .animation(.easeOut(duration: 0.1), value: showsIcon)
            }
            .frame(width: 18, height: 18)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct CompactControlButton: View {
    let symbol: String
    let help: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(disabled ? Color.white.opacity(0.78) : Color.white)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!disabled)
        .help(help)
    }
}

private struct CompactChromeButton: View {
    let symbol: String
    let title: String
    var showsTitle: Bool
    var showsHoverTitle = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CompactChromeLabel(symbol: symbol, title: title, showsTitle: showsTitle)
        }
        .buttonStyle(.plain)
        .modifier(
            CompactHoverTitleModifier(
                title: title,
                showsTitle: showsTitle,
                showsHoverTitle: showsHoverTitle
            )
        )
        .accessibilityLabel(title)
    }
}

private struct CompactChromeLabel: View {
    let symbol: String
    let title: String
    var showsTitle: Bool
    var showsChevron = false
    var chevronPointsUp = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 16, height: 16)

            if showsTitle {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if showsChevron {
                    Image(systemName: chevronPointsUp ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
        }
        .foregroundStyle(Color.white.opacity(0.88))
        .padding(.horizontal, showsTitle ? 2 : 4)
        .frame(height: 24)
        .contentShape(Rectangle())
    }
}

private struct CompactHoverTitleModifier: ViewModifier {
    let title: String
    let showsTitle: Bool
    var showsHoverTitle = true
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .overlay(alignment: .top) {
                if isHovering && showsHoverTitle && !showsTitle {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(Color(white: 0.22))
                        }
                        .fixedSize()
                        .offset(y: -30)
                        .allowsHitTesting(false)
                }
            }
            .zIndex(isHovering && showsHoverTitle && !showsTitle ? 1 : 0)
            .modifier(CompactHelpModifier(title: showsHoverTitle ? title : nil))
    }
}

private struct CompactHelpModifier: ViewModifier {
    let title: String?

    func body(content: Content) -> some View {
        if let title {
            content.help(title)
        } else {
            content
        }
    }
}

private struct CompactLayoutMenu: View {
    @ObservedObject var model: PocketModel
    var showsTitle: Bool
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            CompactChromeLabel(
                symbol: "square.grid.2x2",
                title: "Layout",
                showsTitle: showsTitle,
                showsChevron: true,
                chevronPointsUp: isPresented
            )
            .padding(.horizontal, isPresented ? 8 : 0)
            .padding(.vertical, isPresented ? 3 : 0)
            .background {
                if isPresented {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .modifier(CompactHoverTitleModifier(title: "Layout", showsTitle: showsTitle))
        .accessibilityLabel("Layout")
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            CompactScreenLayoutMenu(model: model, isPresented: $isPresented)
                .presentationBackground {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.145, green: 0.155, blue: 0.175))
                }
        }
    }
}

private struct CompactScreenLayoutMenu: View {
    @ObservedObject var model: PocketModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SCREENS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.white.opacity(0.42))
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 8)

            ForEach(1...4, id: \.self) { count in
                CompactScreenLayoutRow(
                    count: count,
                    isSelected: model.screenLayoutCount == count
                ) {
                    model.screenLayoutCount = count
                    isPresented = false
                }
            }
        }
        .padding(.vertical, 8)
        .frame(width: 210)
    }
}

private struct ScreenLayoutIcon: View {
    let count: Int

    var body: some View {
        VStack(spacing: 1.5) {
            HStack(spacing: 1.5) {
                cell(count >= 1)
                cell(count >= 3)
            }
            HStack(spacing: 1.5) {
                cell(count >= 2)
                cell(count >= 4)
            }
        }
    }

    private func cell(_ highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1.2, style: .continuous)
            .fill(Color.white.opacity(highlighted ? 0.92 : 0.22))
            .frame(width: 6, height: 6)
    }
}

private struct CompactScreenLayoutRow: View {
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    private var title: String {
        count == 1 ? "1 screen" : "\(count) screens"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ScreenLayoutIcon(count: count)
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(.system(size: 14, weight: .medium))

                Spacer(minLength: 12)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.45, green: 0.84, blue: 0.52))
                }
            }
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? Color.white.opacity(0.06) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
    }
}

private struct CompactSiteMenu: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var slot: ScreenSlot
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.enabledApps) { app in
                Button {
                    model.select(app, in: slot)
                    isPresented = false
                } label: {
                    HStack(spacing: 10) {
                        ServiceIcon(app: app, size: 16)

                        Text(app.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)

                        Spacer(minLength: 12)

                        if app.id == slot.app.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(red: 0.45, green: 0.84, blue: 0.52))
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 180)
    }
}

private enum WebsiteEditorTarget: Identifiable {
    case new
    case edit(SimulatedApp)

    var id: String {
        switch self {
        case .new:
            return "new"
        case .edit(let website):
            return website.id
        }
    }

    var website: SimulatedApp? {
        if case .edit(let website) = self {
            return website
        }
        return nil
    }
}

struct WebsiteManagerSheet: View {
    @ObservedObject var model: PocketModel
    @Environment(\.dismiss) private var dismiss
    @State private var editorTarget: WebsiteEditorTarget?
    @State private var websitePendingRemoval: SimulatedApp?
    @State private var isBrowserImportPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Websites")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Choose what appears in Pocket's app switcher.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.pocketMuted)
                }

                Spacer()

                Button {
                    editorTarget = .new
                } label: {
                    Label("Add Website", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.78, green: 0.31, blue: 0.20))
            }
            .padding(.bottom, 12)

            Button {
                isBrowserImportPresented = true
            } label: {
                Label(BrowserSessionImporter.buttonTitle(), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 18)
            .sheet(isPresented: $isBrowserImportPresented) {
                BrowserImportSheet(model: model)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.websites) { website in
                        WebsiteManagerRow(
                            website: website,
                            isOpen: model.openAppIDs.contains(website.id),
                            onToggle: { model.setEnabled($0, for: website) },
                            onEdit: { editorTarget = .edit(website) },
                            onRemove: { websitePendingRemoval = website }
                        )
                    }
                }
            }
            .scrollIndicators(.visible)

            HStack {
                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 18)
        }
        .padding(24)
        .frame(width: 600, height: 570)
        .background(Color.pocketBackground)
        .preferredColorScheme(.dark)
        .sheet(item: $editorTarget) { target in
            WebsiteEditorSheet(model: model, website: target.website)
        }
        .alert(
            removeAlertTitle,
            isPresented: removeAlertPresented
        ) {
            if model.websites.count > 1 {
                Button("Delete", role: .destructive) {
                    if let websitePendingRemoval {
                        model.removeWebsite(websitePendingRemoval)
                    }
                    websitePendingRemoval = nil
                }
                Button("Cancel", role: .cancel) {
                    websitePendingRemoval = nil
                }
            } else {
                Button("OK", role: .cancel) {
                    websitePendingRemoval = nil
                }
            }
        } message: {
            Text(removeAlertMessage)
        }
    }

    private var removeAlertPresented: Binding<Bool> {
        Binding(
            get: { websitePendingRemoval != nil },
            set: { if !$0 { websitePendingRemoval = nil } }
        )
    }

    private var removeAlertTitle: String {
        guard let websitePendingRemoval else { return "Remove website?" }
        if model.websites.count == 1 {
            return "Can’t remove \(websitePendingRemoval.title)"
        }
        return "Remove \(websitePendingRemoval.title)?"
    }

    private var removeAlertMessage: String {
        guard let websitePendingRemoval else { return "" }
        if model.websites.count == 1 {
            return "Pocket needs at least one website."
        }
        return "\(websitePendingRemoval.title) will be removed from Pocket."
    }
}

struct WebsiteManagerRow: View {
    let website: SimulatedApp
    let isOpen: Bool
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    private var locationLabel: String {
        website.url.host ?? website.urlString
    }

    var body: some View {
        HStack(spacing: 12) {
            ServiceIcon(app: website, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(website.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(website.isEnabled ? .white : Color.white.opacity(0.48))

                    if isOpen {
                        Text("OPEN")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(website.tint)
                    }
                }

                Text(locationLabel)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(website.isEnabled ? Color.pocketMuted : Color.pocketMuted.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: Binding(
                get: { website.isEnabled },
                set: onToggle
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .help(website.isEnabled ? "Disable website" : "Enable website")

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Edit website")

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Remove website")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(website.isEnabled ? Color.white.opacity(0.055) : Color.white.opacity(0.025))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(website.isEnabled ? 0.08 : 0.04), lineWidth: 1)
        }
        .opacity(website.isEnabled ? 1 : 0.72)
    }
}

struct WebsiteEditorSheet: View {
    @ObservedObject var model: PocketModel
    let website: SimulatedApp?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var urlString: String
    @State private var validationMessage: String?

    init(model: PocketModel, website: SimulatedApp?) {
        self.model = model
        self.website = website
        _title = State(initialValue: website?.title ?? "")
        _urlString = State(initialValue: website?.urlString ?? "https://")
        _validationMessage = State(initialValue: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            websiteFields
            validationNotice
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: 480, height: 280)
        .background(Color.pocketBackground)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(website == nil ? "Add Website" : "Edit Website")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Give the site a name and URL for Pocket.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.pocketMuted)
        }
    }

    private var websiteFields: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Name")
                .formLabelStyle()
            TextField("e.g. Notion", text: $title)
                .textFieldStyle(.roundedBorder)

            Text("Website URL")
                .formLabelStyle()
            TextField("https://example.com", text: $urlString)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var validationNotice: some View {
        if let validationMessage {
            Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.orange)
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            if let website, website.isBuiltIn {
                Text("Built-in website")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.pocketMuted)
            }

            Spacer()

            Button("Save") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.78, green: 0.31, blue: 0.20))
            .keyboardShortcut(.defaultAction)
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            validationMessage = "Add a name for this website."
            return
        }

        let cleanURL = normalizedURL()
        guard let cleanURL else {
            validationMessage = "Enter a valid http or https website URL."
            return
        }

        if let website {
            model.updateWebsite(
                website,
                title: cleanTitle,
                subtitle: website.subtitle,
                urlString: cleanURL,
                symbolName: website.symbolName
            )
        } else {
            model.addWebsite(
                title: cleanTitle,
                subtitle: "Website",
                urlString: cleanURL,
                symbolName: "globe"
            )
        }
        dismiss()
    }

    private func normalizedURL() -> String? {
        var value = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if !value.contains("://") {
            value = "https://" + value
        }

        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }

        return url.absoluteString
    }
}

private extension View {
    func formLabelStyle() -> some View {
        font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.72))
    }
}

struct DeviceFrame: View {
    let app: SimulatedApp
    @ObservedObject var controller: WebViewController
    let orientation: DeviceOrientation

    var body: some View {
        Group {
            if orientation == .portrait {
                portraitBody
            } else {
                landscapeBody
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(app.title) in \(orientation.title.lowercased()) device mode")
    }

    private var portraitBody: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 47, style: .continuous)
                .fill(Color.black)
                .shadow(color: Color.black.opacity(0.42), radius: 32, y: 16)

            VStack(spacing: 0) {
                DeviceStatusBar()

                WebContent(controller: controller, cornerRadius: 25)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HomeIndicator()
            }
            .padding(7)
            .clipShape(RoundedRectangle(cornerRadius: 41, style: .continuous))

            Capsule()
                .fill(Color.black)
                .frame(width: 92, height: 25)
                .padding(.top, 13)
        }
    }

    private var landscapeBody: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 47, style: .continuous)
                .fill(Color.black)
                .shadow(color: Color.black.opacity(0.42), radius: 32, y: 16)

            HStack(spacing: 0) {
                LandscapeStatusBar()

                WebContent(controller: controller, cornerRadius: 25)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                LandscapeHomeIndicator()
            }
            .padding(7)
            .clipShape(RoundedRectangle(cornerRadius: 41, style: .continuous))

            Capsule()
                .fill(Color.black)
                .frame(width: 25, height: 92)
                .padding(.leading, 13)
        }
    }
}

struct DeviceStatusBar: View {
    var body: some View {
        HStack {
            Text(Date(), style: .time)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 17)
        .frame(height: 42)
        .background(Color.black)
    }
}

struct HomeIndicator: View {
    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.86))
            .frame(width: 93, height: 4)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .background(Color.black)
    }
}

struct LandscapeStatusBar: View {
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "cellularbars")
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 42)
        .background(Color.black)
    }
}

struct LandscapeHomeIndicator: View {
    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.86))
            .frame(width: 4, height: 93)
            .padding(.horizontal, 12)
            .frame(width: 42)
            .background(Color.black)
    }
}

struct ScreenStage: View {
    @ObservedObject var controller: WebViewController

    var body: some View {
        WebContent(controller: controller, cornerRadius: 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }
}

struct WebContent: View {
    @ObservedObject var controller: WebViewController
    let cornerRadius: CGFloat

    var body: some View {
        if cornerRadius > 0 {
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
        }
    }

    private var content: some View {
        ZStack(alignment: .top) {
            WebViewRepresentable(controller: controller)
                .id(ObjectIdentifier(controller))

            if controller.isLoading {
                VStack(spacing: 0) {
                    ProgressView(value: controller.loadingProgress)
                        .tint(controller.app.tint)
                        .progressViewStyle(.linear)
                        .frame(height: 2)

                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)

                        Text("Connecting to \(controller.app.title)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.78))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 14)
                }
            }

            if let errorMessage = controller.errorMessage, !errorMessage.isEmpty {
                ErrorOverlay(message: errorMessage, tint: controller.app.tint) {
                    controller.load()
                }
            }
        }
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    @ObservedObject var controller: WebViewController

    func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct ErrorOverlay: View {
    let message: String
    let tint: Color
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: 50, height: 50)

                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(tint)
            }

            Text("Could not connect")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: retry) {
                Text("Try again")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(tint)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(26)
        .frame(maxWidth: 310)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.20))
    }
}

struct BrowserImportSheet: View {
    @ObservedObject var model: PocketModel
    @Environment(\.dismiss) private var dismiss

    @State private var offer: BrowserImportOffer
    @State private var selectedProfileID: String
    @State private var isImporting = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    init(model: PocketModel) {
        self.model = model
        let offer = BrowserSessionImporter.loadOffer()
        _offer = State(initialValue: offer)
        let selected = offer.profiles.first(where: \.isDefault)?.id ?? offer.profiles.first?.id ?? ""
        _selectedProfileID = State(initialValue: selected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(offer.buttonTitle)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(offer.explanation)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.pocketMuted)
                .fixedSize(horizontal: false, vertical: true)

            if offer.profiles.count > 1 {
                Picker("Profile", selection: $selectedProfileID) {
                    ForEach(offer.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isImporting)
            } else if let profile = offer.profiles.first {
                Text("Profile: \(profile.name)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }

            if let resultMessage {
                Text(resultMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isImporting ? "Importing…" : "Import") {
                    Task { await runImport() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.78, green: 0.31, blue: 0.20))
                .disabled(isImporting || !offer.canImport || selectedProfile == nil)
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
        .background(Color.pocketBackground)
        .preferredColorScheme(.dark)
    }

    private var selectedProfile: BrowserProfile? {
        offer.profiles.first { $0.id == selectedProfileID }
    }

    private func runImport() async {
        guard let profile = selectedProfile else { return }
        isImporting = true
        errorMessage = nil
        resultMessage = nil
        defer { isImporting = false }

        let sites = model.websites.map {
            BrowserImportSite(id: $0.id, title: $0.title, dataStoreKey: $0.dataStoreKey, url: $0.url)
        }
        do {
            let report = try await BrowserSessionImporter.importCookies(from: profile, into: sites)
            let imported = Set(report.sites.filter { $0.cookieCount > 0 }.map(\.appID))
            model.reloadSessions(forAppIDs: imported)
            resultMessage = report.summary
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct ServiceIcon: View {
    let app: SimulatedApp
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(app.tint)

                Image(systemName: app.symbolName)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(app.id == SimulatedApp.x.id ? Color.black.opacity(0.82) : .white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .task(id: app.urlString) {
            let data = await FaviconStore.shared.imageData(for: app.url)
            image = data.flatMap(NSImage.init(data:))
        }
    }
}
