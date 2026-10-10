import AppKit
import SwiftUI
import WebKit

@main
struct MultiScreenTests {
    struct Failure: Error, CustomStringConvertible { let description: String }

    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                try await run()
                print("Multi-screen checks passed")
                exit(0)
            } catch {
                fputs("FAIL: \(error)\n", stderr)
                exit(1)
            }
        }
        NSApplication.shared.run()
    }

    @MainActor static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    @MainActor static func waitFor(_ message: String, condition: () async throws -> Bool) async throws {
        for _ in 0..<100 {
            if (try? await condition()) == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw Failure(description: message)
    }

    @MainActor static func webViews(in view: NSView) -> [WKWebView] {
        if let webView = view as? WKWebView { return [webView] }
        return view.subviews.flatMap { webViews(in: $0) }
    }

    @MainActor static func checkWindowSizing(defaults: UserDefaults) throws {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 401, height: 331),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let manager = WindowManager(defaults: defaults)
        manager.attach(window: window)
        defer { window.close() }
        manager.resize(for: .screen, orientation: .landscape, layout: .single,
            size: CGSize(width: 401, height: 331), animated: false, force: true)
        var expectedPage = CGSize(width: 401, height: 243)
        let anchor = CGPoint(x: window.frame.minX, y: window.frame.maxY)
        for layout in [ScreenLayout.sideBySide, .grid, .stacked, .single, .grid] {
            manager.changeScreenLayout(to: layout)
            let actual = layout.pageSize(in: window.contentRect(forFrameRect: window.frame).size)
            try require(abs(actual.width - expectedPage.width) < 0.01 && abs(actual.height - expectedPage.height) < 0.01,
                "Changing to \(layout.title) shrank or enlarged an individual screen: \(actual)")
            try require(abs(window.frame.minX - anchor.x) < 0.01 && abs(window.frame.maxY - anchor.y) < 0.01,
                "Changing layouts moved the original top-left corner")
        }
        // Simulate an actual user resize after the initial cached window size.
        window.setContentSize(CGSize(width: 789, height: 555))
        NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: window)
        expectedPage = CGSize(width: 394.5, height: 233.5)
        manager.changeScreenLayout(to: .single)
        let afterDrag = ScreenLayout.single.pageSize(in: window.contentRect(forFrameRect: window.frame).size)
        try require(abs(afterDrag.width - expectedPage.width) <= 0.51 && abs(afterDrag.height - expectedPage.height) <= 0.51,
            "Layout switching used the cached size instead of the live resized window: \(afterDrag), expected \(expectedPage)")
        // AppKit rounds a fractional outer window size to a device point.
        expectedPage = afterDrag
        manager.restoreSize(for: .screen, orientation: .landscape, layout: .stacked, animated: false)
        let restored = ScreenLayout.stacked.pageSize(in: window.contentRect(forFrameRect: window.frame).size)
        try require(abs(restored.width - expectedPage.width) < 0.01 && abs(restored.height - expectedPage.height) < 0.01,
            "Restoring a different layout changed the saved individual screen size")
        print("PASS: native window grows with added screens, preserves page size and position, and restores live resize dimensions")
    }

    @MainActor static func run() async throws {
        let suite = "Pocket.MultiScreenTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try checkWindowSizing(defaults: defaults)
        let model = PocketModel(defaults: defaults, loadPages: false)
        model.screenLayout = .grid
        model.select(.youtube, in: 3)
        model.select(.youtube, in: 0)
        let bottom = model.screens[3].controller(for: .youtube)
        let top = model.screens[0].controller(for: .youtube)
        try require(bottom !== top && bottom.webView !== top.webView,
            "The same site on two screens must have independent views and histories")

        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: MultiScreenView(model: model))
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }

        // Loaded pages can report very different preferred/minimum widths.
        // Exercise the mounted grid after WebKit has real content, not just
        // initially empty native views.
        for screen in model.screens {
            let view = screen.controller(for: screen.selectedApp).webView
            view.loadHTMLString("<!doctype html><style>html,body{margin:0;min-width:1200px}main{width:500px}</style><main>Wide site fixture</main>", baseURL: nil)
            try await waitFor("Wide site fixture did not load") {
                try await view.evaluateJavaScript("document.querySelector('main')?.textContent") as? String == "Wide site fixture"
            }
        }

        for layout in ScreenLayout.allCases {
            model.screenLayout = layout
            try await waitFor("Incorrect number of mounted web views for \(layout.title)") {
                webViews(in: host).count == layout.screenIDs.count
            }
            host.layoutSubtreeIfNeeded()
            let frames = layout.frames(in: host.bounds.size)
            for id in layout.screenIDs {
                let view = model.screens[id].controller(for: model.screens[id].selectedApp).webView
                let rect = view.convert(view.bounds, to: host)
                try require(abs(rect.width - frames[id].width) < 1 && abs(rect.height - frames[id].height) < 1,
                    "Page size does not fill its tile for \(layout.title)")
                try require(abs(rect.minX - frames[id].minX) < 1 && abs(rect.minY - frames[id].minY) < 1,
                    "Page has a gap or misplaced tile in \(layout.title): \(rect) vs \(frames[id])")
                let hitPoint = host.convert(CGPoint(x: rect.midX, y: rect.midY), to: host.superview)
                let hit = host.hitTest(hitPoint)
                try require(hit === view || hit?.isDescendant(of: view) == true,
                    "The activity overlay blocks web interaction in \(layout.title), tile \(id): \(String(describing: hit)), target \(view), rect \(rect)")
            }
        }
        print("PASS: loaded sites with different content widths fill equal tiles in all four layouts")

        for size in [CGSize(width: 901, height: 603), CGSize(width: 623, height: 537), CGSize(width: 441, height: 371)] {
            window.setContentSize(size)
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let views = model.screenLayout.screenIDs.map { model.screens[$0].controller(for: model.screens[$0].selectedApp).webView }
            let rects = views.map { $0.convert($0.bounds, to: host) }
            for rect in rects {
                try require(abs(rect.width - rects[0].width) < 0.51 && abs(rect.height - rects[0].height) < 0.51,
                    "Resizing to \(size) produced unequal screens: \(rects)")
            }
            try require(abs(rects[0].maxX - rects[1].minX) < 0.51 && abs(rects[0].maxY - rects[2].minY) < 0.51,
                "Resizing introduced an interior gap")
            for rect in rects {
                let top = ScreenControlGeometry.navigation(above: rect)
                let website = ScreenControlGeometry.website(above: rect)
                try require(top.maxY <= rect.minY && website.maxY <= rect.minY,
                    "Individual controls cover their own website")
                try require(abs(top.maxX - (rect.maxX - 8)) < 0.01 && abs(website.maxX + 6 - top.minX) < 0.01 && website.minY == top.minY,
                    "Individual controls are not aligned to their screen edges")
            }
        }
        for layout in ScreenLayout.allCases {
            let frames = layout.frames(in: CGSize(width: 900, height: 600))
            for id in layout.screenIDs {
                let page = frames[id]
                let navigation = ScreenControlGeometry.navigation(above: page)
                let website = ScreenControlGeometry.website(above: page)
                // Follow the pointer from the page, through the five-point
                // margin, into each control, and across the capsule gap.
                let path = [CGPoint(x: website.midX, y: page.minY + 1),
                            CGPoint(x: website.midX, y: page.minY - 2),
                            CGPoint(x: website.midX, y: website.midY),
                            CGPoint(x: website.maxX + 3, y: website.midY),
                            CGPoint(x: navigation.midX, y: page.minY - 2),
                            CGPoint(x: navigation.midX, y: navigation.midY)]
                for point in path {
                    try require(ScreenControlGeometry.screenID(at: point, frames: frames,
                        activeScreenID: id, focusedScreenID: id) == id,
                        "Crossing a control margin switched screens in \(layout.title), tile \(id)")
                }
                if id >= layout.columns {
                    let outside = CGPoint(x: page.minX + 1, y: navigation.midY)
                    try require(ScreenControlGeometry.screenID(at: outside, frames: frames,
                        activeScreenID: id, focusedScreenID: id) == id - layout.columns,
                        "Controls kept focus after leaving their hover area")
                }
            }
        }
        print("PASS: controls and connecting margins retain their screen across every layout")

        window.setContentSize(CGSize(width: 900, height: 600))
        try await Task.sleep(for: .milliseconds(100))
        print("PASS: repeated odd-size resizes keep all screens equal and controls outside their own pages")

        bottom.webView.loadHTMLString("<!doctype html><body style='height:3000px'><input id='draft' value='remember me'><script>window.screenMarker=42</script>",
            baseURL: URL(string: "https://www.youtube.com/"))
        try await waitFor("Fixture did not load") {
            try await bottom.webView.evaluateJavaScript("window.screenMarker") as? Int == 42
        }
        _ = try await bottom.webView.evaluateJavaScript("history.replaceState({}, '', '/watch?v=pocket-fixture'); scrollTo(0, 200)")
        try await waitFor("Navigation URL was not persisted") {
            defaults.string(forKey: "Pocket.screen.3.url.youtube") == "https://www.youtube.com/watch?v=pocket-fixture"
        }
        let savedScroll = try await bottom.webView.evaluateJavaScript("scrollY") as! Double
        model.focusScreen(3)
        model.screenLayout = .single
        try await waitFor("Hidden screens remain attached") { webViews(in: host).count == 1 }
        try require(model.focusedScreenID == 0, "Single screen must focus the remaining screen")
        model.screenLayout = .grid
        try await waitFor("Returning grid did not attach retained views") { webViews(in: host).count == 4 }
        try require(model.screens[3].controller(for: .youtube) === bottom,
            "Returning to grid rebuilt the bottom-right controller")
        try require(bottom.webView.url?.absoluteString == "https://www.youtube.com/watch?v=pocket-fixture",
            "Returning to grid lost the navigation URL")
        let retained = try await bottom.webView.evaluateJavaScript("window.screenMarker===42 && document.getElementById('draft').value==='remember me'") as? Bool
        let restoredScroll = try await bottom.webView.evaluateJavaScript("scrollY") as! Double
        try require(abs(restoredScroll - savedScroll) <= 1, "Returning grid lost the scroll position")
        try require(retained == true, "Returning to grid lost live document or scroll state")
        let restored = PocketModel(defaults: defaults, loadPages: false)
        try require(restored.screenLayout == .grid && restored.screens[3].selectedApp.id == "youtube",
            "Saved layout and per-screen selections did not restore")
        print("PASS: grid to single to grid retains URL, live document, form, scroll, and controller identity")

        try require(ScreenChromeActivity().timeout == 3, "Default idle timeout must be three seconds")
        let activity = ScreenChromeActivity(timeout: 0.2)
        activity.activate(3)
        try require(activity.screenID == 3, "Chrome did not appear synchronously")
        try await Task.sleep(for: .milliseconds(130))
        activity.activate(1)
        try await Task.sleep(for: .milliseconds(130))
        try require(activity.screenID == 1, "Recent activity did not extend the deadline")
        try await waitFor("Chrome did not hide after inactivity") { activity.screenID == nil }
        activity.activate(0)
        activity.hold(true)
        try await Task.sleep(for: .milliseconds(250))
        try require(activity.screenID == 0, "Chrome hid while layout picker was open")
        activity.hold(false)
        try await waitFor("Chrome did not hide after picker dismissal") { activity.screenID == nil }
        activity.activate(2)
        activity.leave()
        try require(activity.screenID == nil, "Leaving the window did not hide chrome")
        print("PASS: immediate chrome, activity deadline, idle hiding, picker hold, and window exit")

        let tracker = ScreenActivityNSView(frame: host.bounds)
        host.addSubview(tracker)
        let pointerActivity = ScreenChromeActivity(timeout: 0.15)
        tracker.onActivity = { _ in pointerActivity.activate(0) }
        let point = tracker.convert(CGPoint(x: 10, y: 50), to: nil)
        let typing = NSEvent.keyEvent(with: .keyDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a",
            isARepeat: false, keyCode: 0)!
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let movement = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        tracker.handlePointerMovement(typing)
        tracker.handlePointerMovement(click)
        try require(pointerActivity.screenID == nil, "Typing or clicking revealed hidden controls")
        tracker.handlePointerMovement(movement)
        try require(pointerActivity.screenID == 0, "Mouse movement did not reveal controls immediately")
        try await Task.sleep(for: .milliseconds(100))
        tracker.handlePointerMovement(typing)
        tracker.handlePointerMovement(click)
        try await Task.sleep(for: .milliseconds(80))
        try require(pointerActivity.screenID == nil, "Typing or clicking extended the inactivity deadline")
        tracker.handlePointerMovement(typing)
        try require(pointerActivity.screenID == nil, "Typing brought hidden controls back")
        tracker.removeFromSuperview()
        print("PASS: only mouse movement reveals controls or extends the inactivity deadline")

        try await checkPopupAndRecovery()

        model.setEnabled(false, for: .youtube)
        try require(model.screens.allSatisfy { $0.selectedApp.id != "youtube" },
            "Disabling a site did not replace it on every screen")
        print("PASS: disabling a site updates every screen, including retained screens")
    }

    @MainActor static func checkPopupAndRecovery() async throws {
        let controller = WebViewController(app: .x, websiteDataStore: .nonPersistent(), loadImmediately: false)
        let view = controller.webView
        view.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        defer { window.close() }
        view.loadHTMLString("<!doctype html><main>Original site</main><script>window.marker=42;addEventListener('message',e=>window.popupMessage=e.data)</script>",
            baseURL: URL(string: "https://x.com/"))
        try await waitFor("Popup opener fixture did not load") {
            try await view.evaluateJavaScript("window.marker") as? Int == 42
        }
        _ = try await view.evaluateJavaScript("window.child=window.open('about:blank','pocket-test'); true")
        try await waitFor("New-window navigation did not create a separate popup") {
            window.childWindows?.count == 1
        }
        let popupWindow = window.childWindows![0]
        let popup = webViews(in: popupWindow.contentView!)[0]
        try await waitFor("Popup lost its opener") {
            try await popup.evaluateJavaScript("window.opener?.marker") as? Int == 42
        }
        _ = try await popup.evaluateJavaScript("window.opener.postMessage('popup-result','*'); true")
        try await waitFor("Popup could not communicate with the original page") {
            try await view.evaluateJavaScript("window.popupMessage") as? String == "popup-result"
        }
        try require(view.url?.host == "x.com", "Popup replaced the main screen's URL")
        _ = try await popup.evaluateJavaScript("window.close(); true")
        try await waitFor("Closed popup window was not removed") { window.childWindows?.isEmpty != false }
        let oldPopupURL = URL(string: "https://accounts.google.com/gsi/select?origin=https%3A%2F%2Fx.com")!
        try require(WebViewController.restoredURL(oldPopupURL, for: .x) == SimulatedApp.x.url,
            "Old popup-only sign-in URL restored as a blank main screen")
        let pageURL = URL(string: "https://x.com/example/status/123")!
        try require(WebViewController.restoredURL(pageURL, for: .x) == pageURL,
            "Normal saved page URL was discarded")
        controller.webViewWebContentProcessDidTerminate(view)
        try require(controller.isLoading && controller.errorMessage == nil, "Web process termination did not attempt recovery")
        controller.webViewWebContentProcessDidTerminate(view)
        try require(!controller.isLoading && controller.errorMessage?.isEmpty == false,
            "Repeated process termination left an empty screen or entered a reload loop")
        print("PASS: separate popups preserve opener, return results, close cleanly, and keep the main page; old popup URLs and process crashes recover")
    }
}
