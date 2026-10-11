import AppKit
import SwiftUI

// A panel is used so the pinned window can join full-screen Spaces. Its
// activation behavior is switched with the Always on Top setting.
final class PocketPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: PocketPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }

        let model = PocketModel.shared
        let panel = PocketPanel(
            contentRect: NSRect(x: 0, y: 0, width: 344, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable,
                        .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentView = NSHostingView(rootView: AppRootView(model: model))
        self.panel = panel

        WindowManager.shared.attach(window: panel)
        WindowManager.shared.setAlwaysOnTop(model.alwaysOnTop)
        WindowManager.shared.restoreSize(
            for: model.presentationMode,
            orientation: model.orientation,
            layout: model.screenLayout,
            animated: false
        )
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel?.makeKeyAndOrderFront(nil)
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // The utility panel is at normal level when unpinned. Bring it forward
        // when Pocket is selected so another app's window cannot cover it.
        panel?.makeKeyAndOrderFront(nil)
    }
}
