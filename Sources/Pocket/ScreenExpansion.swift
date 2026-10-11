import AppKit
import SwiftUI

final class ScreenExpansionController: NSObject, ObservableObject, NSWindowDelegate {
    private let model: PocketModel
    private weak var parent: NSWindow?
    private(set) var window: NSPanel?
    private var presentedScreenID: Int?
    private var escapeMonitor: Any?
    private var parentCloseObserver: NSObjectProtocol?

    init(model: PocketModel) { self.model = model }

    deinit {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let parentCloseObserver { NotificationCenter.default.removeObserver(parentCloseObserver) }
        window?.delegate = nil
        window?.close()
    }

    static func expandedFrame(in availableFrame: CGRect) -> CGRect {
        let size = CGSize(width: availableFrame.width * 0.75, height: availableFrame.height * 0.75)
        return CGRect(x: availableFrame.midX - size.width / 2, y: availableFrame.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    func attach(to parent: NSWindow) {
        guard self.parent !== parent else { return }
        dismiss(focusParent: false)
        if let parentCloseObserver { NotificationCenter.default.removeObserver(parentCloseObserver) }
        self.parent = parent
        parentCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: parent, queue: .main
        ) { [weak self] _ in
            self?.model.collapseScreen()
            self?.dismiss(focusParent: false)
        }
        synchronize()
    }

    func synchronize() {
        guard let id = model.expandedScreenID, model.presentationMode == .screen,
              model.screenLayout.screenIDs.contains(id), let parent else {
            dismiss()
            return
        }
        guard presentedScreenID != id || window == nil else { return }
        dismiss(focusParent: false)
        guard let screen = parent.screen ?? NSScreen.main else {
            model.collapseScreen()
            return
        }
        let frame = Self.expandedFrame(in: screen.visibleFrame)
        let panel = ExpandedScreenPanel(contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.title = "Screen \(id + 1) - Pocket"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = NSColor(white: 0.045, alpha: 1)
        panel.contentMinSize = CGSize(width: 300, height: 200)
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.level = parent.level
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(type)?.isHidden = true
        }
        window = panel
        presentedScreenID = id
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ExpandedScreenView(model: model, screen: model.screens[id]))
        panel.setFrame(frame, display: false)
        parent.addChildWindow(panel, ordered: .above)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.handleEscape(event) == true else { return event }
            return nil
        }
        panel.makeKeyAndOrderFront(nil)
    }

    // Kept separate from the monitor so the native keyboard path is testable
    // without generating input in another application.
    @discardableResult func handleEscape(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.keyCode == 53, let window, event.window === window else { return false }
        model.collapseScreen()
        synchronize()
        return true
    }

    func updateWindowLevel() { if let parent { window?.level = parent.level } }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow === window else { return }
        model.collapseScreen()
        dismiss(closeWindow: false)
    }

    private func dismiss(focusParent: Bool = true, closeWindow: Bool = true) {
        guard let panel = window else { return }
        window = nil
        presentedScreenID = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
        panel.delegate = nil
        parent?.removeChildWindow(panel)
        // Drop the floating host before SwiftUI remounts the same WKWebView
        // in its original tile. Never reload or create a replacement browser.
        panel.contentView = nil
        if closeWindow { panel.close() }
        if focusParent, parent?.isVisible == true { parent?.makeKeyAndOrderFront(nil) }
    }
}

private final class ExpandedScreenPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct ExpandedScreenView: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var screen: PocketScreen
    @ObservedObject private var chat: PocketChatController
    @StateObject private var activity: ScreenChromeActivity
    @State private var isPointerInside = false

    init(model: PocketModel, screen: PocketScreen, activity: ScreenChromeActivity? = nil) {
        self.model = model
        self.screen = screen
        self.chat = model.chat
        self._activity = StateObject(wrappedValue: activity ?? ScreenChromeActivity())
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                CompactWebsiteChooser(model: model, screen: screen, height: 30)
                    .frame(width: 160, height: 30)
                CompactNavigationControls(controller: screen.selectedController, isExpanded: true,
                    toggleExpansion: { model.collapseScreen() })
                    .frame(width: ScreenControlGeometry.navigationWidth, height: 30)
            }
            .padding(.horizontal, 8)
            .frame(height: ScreenLayout.topBarHeight)
            .background(Color(white: 0.055))
            .background(WindowDragHandle(showsIndicator: false))
            .opacity(activity.screenID == nil ? 0 : 1)
            .allowsHitTesting(activity.screenID != nil)
            ScreenContent(controller: screen.selectedController, cornerRadius: 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .overlay {
            ScreenActivityTrackingView { _ in
                isPointerInside = true
                model.focusScreen(screen.id)
                activity.activate(screen.id)
            } onExit: {
                isPointerInside = false
                activity.leave()
            }
            .accessibilityHidden(true)
            .ignoresSafeArea()
        }
        .onAppear {
            activity.hold(chat.isWorking)
            activity.activate(screen.id)
        }
        .onChange(of: chat.isWorking) { _, working in
            activity.hold(working)
            if working { activity.activate(screen.id) }
            else if !isPointerInside { activity.leave() }
        }
        .preferredColorScheme(.dark)
    }
}
