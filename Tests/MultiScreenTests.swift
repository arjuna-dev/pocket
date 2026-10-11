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

    actor HoverClient: PocketAIClient {
        func account() async throws -> PocketAIAccount { .init(isSignedIn: false, email: nil) }
        func startLogin() async throws -> PocketAILogin { throw PocketAIError.unavailable }
        func finishLogin(_ id: String) async throws { throw PocketAIError.unavailable }
        func cancelLogin(_ id: String) async {}
        func generate(prompt: String, workspace: PocketWorkspace) async throws -> PocketWorkspaceChange { throw PocketAIError.unavailable }
        func interrupt() async {}
        func shutdown() async {}
    }

    @MainActor static func trackers(in view: NSView) -> [ScreenActivityNSView] {
        if let tracker = view as? ScreenActivityNSView { return [tracker] }
        return view.subviews.flatMap { trackers(in: $0) }
    }

    @MainActor static func checkRootControlHover() async throws {
        let suite = "Pocket.RootHoverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let chat = PocketChatController(client: HoverClient())
        let model = PocketModel(defaults: defaults, loadPages: false, chat: chat)
        let activity = ScreenChromeActivity()
        let manager = WindowManager(defaults: defaults)
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 1001, height: 801),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: AppRootView(model: model, activity: activity, windowManager: manager))
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        for screen in model.screens {
            model.select(.youtube, in: screen.id)
            screen.selectedController!.webView.loadHTMLString("<main>Hover fixture</main>", baseURL: nil)
        }
        for composerVisible in [false, true] {
            chat.isComposerVisible = composerVisible
            for layout in ScreenLayout.allCases {
                model.screenLayout = layout
                try await waitFor("Root view did not mount its pages and tracker") {
                    webViews(in: host).count == layout.screenIDs.count && trackers(in: host).count == 1
                }
                window.setContentSize(CGSize(width: 1001, height: 801))
                try await Task.sleep(for: .milliseconds(80))
                host.layoutSubtreeIfNeeded()
                let tracker = trackers(in: host)[0]
                for id in layout.screenIDs {
                    let web = model.screens[id].selectedController!.webView
                    // Use the mounted page's actual rect, not a second calculation of the grid.
                    let page = web.convert(web.bounds, to: tracker)
                    let website = ScreenControlGeometry.website(above: page)
                    let navigation = ScreenControlGeometry.navigation(above: page)
                    let path = [CGPoint(x: website.midX, y: page.minY + 2),
                                CGPoint(x: website.midX, y: page.minY - 2),
                                CGPoint(x: website.midX, y: website.midY),
                                CGPoint(x: website.maxX + 3, y: website.midY),
                                CGPoint(x: navigation.midX, y: navigation.midY),
                                CGPoint(x: navigation.maxX + 2, y: navigation.midY),
                                CGPoint(x: navigation.midX, y: navigation.minY - 2)]
                    for point in path {
                        let event = NSEvent.mouseEvent(with: .mouseMoved,
                            location: tracker.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
                        tracker.handlePointerMovement(event)
                        try require(activity.screenID == id && model.focusedScreenID == id,
                            "Root hover switched away from tile \(id) in \(layout.title), chat \(composerVisible), at \(point)")
                    }
                    try await Task.sleep(for: .milliseconds(10))
                    host.layoutSubtreeIfNeeded()
                    for x in [navigation.minX + 69, navigation.maxX - 15] {
                        let buttonPoint = tracker.convert(CGPoint(x: x, y: navigation.midY), to: host.superview)
                        let hit = host.hitTest(buttonPoint)
                        try require(hit != nil && !webViews(in: host).contains(where: { hit === $0 || hit?.isDescendant(of: $0) == true }),
                            "Refresh or Expand passes clicks through to a website in tile \(id)")
                    }
                    activity.leave()
                    let resume = NSEvent.mouseEvent(with: .mouseMoved,
                        location: tracker.convert(CGPoint(x: navigation.midX, y: navigation.midY), to: nil),
                        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                        eventNumber: 0, clickCount: 0, pressure: 0)!
                    tracker.handlePointerMovement(resume)
                    try require(activity.screenID == id, "Moving on an idle capsule revealed the neighboring screen")
                    // AppKit can report exits when tracking areas change under the pointer.
                    // An exit over an interior control is not a whole-window exit.
                    let internalExit = NSEvent.enterExitEvent(with: .mouseExited,
                        location: tracker.convert(CGPoint(x: navigation.midX, y: navigation.midY), to: nil),
                        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                        eventNumber: 0, trackingNumber: 0, userData: nil)!
                    tracker.mouseExited(with: internalExit)
                    try require(activity.screenID == id,
                        "An internal tracking exit hid tile \(id)'s controls before they could be clicked")
                }
                let outside = NSEvent.enterExitEvent(with: .mouseExited,
                    location: tracker.convert(CGPoint(x: -2, y: 100), to: nil), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
                tracker.mouseExited(with: outside)
                try require(activity.screenID == nil, "Actual window exit did not hide controls immediately")
            }
        }
        print("PASS: full app hover crosses page/control gaps in all layouts with chat open and closed; only true window exits hide controls")
    }

    @MainActor static func checkScreenExpansion() async throws {
        let suite = "Pocket.ExpansionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = PocketModel(defaults: defaults, loadPages: false,
                                chat: PocketChatController(client: HoverClient()))
        model.screenLayout = ScreenLayout(columns: 4, rows: 4)
        model.select(.youtube, in: 0)
        model.select(.youtube, in: 15)
        let controller = model.screens[15].selectedController!
        let page = controller.webView
        page.loadHTMLString("<body style='height:5000px'><input id='draft' value='original'><script>window.marker=42</script>",
                            baseURL: URL(string: "https://www.youtube.com/"))
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 1001, height: 801),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let expansion = ScreenExpansionController(model: model)
        let host = NSHostingView(rootView: AppRootView(model: model, windowManager: WindowManager(defaults: defaults),
                                                       expansion: expansion))
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        try await waitFor("Expansion fixture did not mount") {
            let marker = try? await page.evaluateJavaScript("window.marker")
            return page.window === window && marker as? Int == 42
        }
        _ = try await page.evaluateJavaScript("document.getElementById('draft').value='keep my draft'; history.pushState({}, '', '/watch?v=expanded-fixture'); scrollTo(0,300)")
        try await Task.sleep(for: .milliseconds(100))
        let oldHost = page.superview as! WebViewHost
        let originalWindowFrame = window.frame
        let originalRects = webViews(in: host).map { $0.convert($0.bounds, to: host) }
        let historyCount = page.backForwardList.backList.count
        for _ in 0..<3 {
            model.expandScreen(15)
            try await waitFor("Expand did not move the live page into a floating window") {
                expansion.window?.isVisible == true && page.window === expansion.window && webViews(in: host).count == 1
            }
            let panel = expansion.window!
            try require(window.childWindows?.count == 1 && model.screenLayout == ScreenLayout(columns: 4, rows: 4),
                        "Expansion changed the grid or created multiple floating windows")
            try require(window.frame == originalWindowFrame, "Expansion resized the main grid")
            let expectedFrame = ScreenExpansionController.expandedFrame(in: window.screen!.visibleFrame)
            try require(abs(panel.frame.width - expectedFrame.width) <= 1 && abs(panel.frame.height - expectedFrame.height) <= 1 &&
                        abs(panel.frame.midX - expectedFrame.midX) <= 1 && abs(panel.frame.midY - expectedFrame.midY) <= 1,
                        "Expanded window is not centered at 75 percent of the current display")
            try require(controller === model.screens[15].selectedController && webViews(in: panel.contentView!).first === page,
                        "Expansion created a replacement web view")
            let expandedSize = page.frame.size
            oldHost.layout()
            try require(page.frame.size == expandedSize, "The detached grid host resized the expanded page")
            _ = try await page.evaluateJavaScript("scrollTo(0,300)")
            try require((try await page.evaluateJavaScript("window.marker===42 && document.getElementById('draft').value==='keep my draft'")) as? Bool == true,
                        "Expanding lost the live document or input")
            let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: 53)!
            try require(expansion.handleEscape(escape), "Escape in the floating window was not handled")
            try await waitFor("Collapse did not restore the same page to its original grid tile") {
                expansion.window == nil && page.window === window && webViews(in: host).count == 2
            }
            host.layoutSubtreeIfNeeded()
            try require(webViews(in: host).map { $0.convert($0.bounds, to: host) } == originalRects,
                        "Collapsing changed the grid tile sizes")
            try require(page.url?.absoluteString == "https://www.youtube.com/watch?v=expanded-fixture" &&
                        page.backForwardList.backList.count == historyCount,
                        "Expand/collapse lost URL or navigation history")
            try require((try await page.evaluateJavaScript("window.marker===42 && document.getElementById('draft').value==='keep my draft' && Math.abs(scrollY-300)<2")) as? Bool == true,
                        "Collapse reloaded the page, lost a draft, or reset the scroll position")
        }
        model.expandScreen(15)
        try await waitFor("Second expansion did not open") { expansion.window != nil }
        let oldPanel = expansion.window!
        model.expandScreen(0)
        try await waitFor("Switching expanded screens did not restore the previous page") {
            expansion.window !== oldPanel && expansion.window != nil && page.window === window
        }
        try require(!oldPanel.isVisible && window.childWindows?.count == 1, "Switching left an extra floating window")
        expansion.window!.close()
        try await waitFor("Closing the floating window did not collapse it") { model.expandedScreenID == nil && expansion.window == nil }
        model.expandScreen(15)
        try await waitFor("Layout-collapse fixture did not open") { expansion.window != nil }
        model.screenLayout = .single
        try await waitFor("Hiding an expanded screen in a new layout left an orphan window") { expansion.window == nil }
        model.expandScreen(0)
        try await waitFor("Presentation-collapse fixture did not open") { expansion.window != nil }
        model.presentationMode = .device
        try await waitFor("Switching presentation did not collapse expansion") { expansion.window == nil }
        model.presentationMode = .screen
        model.select(nil, in: 0)
        model.expandScreen(0)
        try await waitFor("An off screen could not be expanded") { expansion.window != nil }
        try require(webViews(in: expansion.window!.contentView!).isEmpty, "Expanding an off screen opened an arbitrary page")
        window.close()
        try require(expansion.window == nil && model.expandedScreenID == nil, "Closing Pocket left the expanded window open")
        print("PASS: 75-percent floating expansion preserves live page, URL, history, draft, scroll and grid; Escape, switching, native close, Off and parent close work")
    }

    @MainActor static func checkLayoutIcons() throws {
        for layout in ScreenLayout.allCases {
            let dimension = max(2, layout.columns, layout.rows)
            let gap: CGFloat = dimension == 2 ? 2 : 1
            let cell = (16 - gap * CGFloat(dimension - 1)) / CGFloat(dimension)
            let bitmap = NSBitmapImageRep(data: layout.iconImage.tiffRepresentation!)!
            let scale = CGFloat(bitmap.pixelsWide) / 16
            for row in 0..<dimension {
                for column in 0..<dimension {
                    let x = Int((CGFloat(column) * (cell + gap) + cell / 2) * scale)
                    let y = Int((CGFloat(row) * (cell + gap) + cell / 2) * scale)
                    let alpha = bitmap.colorAt(x: x, y: y)!.alphaComponent
                    let expected: CGFloat = row < layout.rows && column < layout.columns ? 1 : 0.22
                    try require(abs(alpha - expected) < 0.02,
                        "Incorrect highlighted cell in \(layout.rawValue) at column \(column), row \(row)")
                }
            }
        }
        print("PASS: all layout icons show white active squares and dim unused squares in a 2x2, 3x3, or 4x4 grid")
    }

    @MainActor static func checkSelectionMigration() throws {
        let suite = "Pocket.SelectionMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("whatsapp", forKey: "Pocket.selectedApp")
        defaults.set("whatsapp", forKey: "Pocket.screen.0.app")
        defaults.set("youtube", forKey: "Pocket.screen.1.app")
        defaults.set("telegram", forKey: "Pocket.screen.2.app")
        defaults.set("https://web.telegram.org/a/", forKey: "Pocket.screen.2.url.telegram")
        let migrated = PocketModel(defaults: defaults, loadPages: false)
        try require(migrated.screens[0].selectedApp?.id == "whatsapp" && migrated.screens[2].selectedApp?.id == "telegram",
            "Migration discarded an existing primary screen or a saved page")
        try require(migrated.screens[1].selectedApp == nil && migrated.screens[15].selectedApp == nil,
            "Migration retained unused automatic site assignments")
        migrated.select(.youtube, in: 1)
        let restored = PocketModel(defaults: defaults, loadPages: false)
        try require(restored.screens[1].selectedApp?.id == "youtube",
            "An explicit selection without a loaded URL did not restore")
        print("PASS: migration preserves opened pages, clears unused assignments, and restores new explicit choices")
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
        try checkLayoutIcons()
        try checkSelectionMigration()
        try checkWindowSizing(defaults: defaults)
        let model = PocketModel(defaults: defaults, loadPages: false)
        try require(model.screens.allSatisfy { $0.selectedApp == nil && $0.selectedController == nil },
            "A new screen chose a site or created a web view automatically")
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

        try await waitFor("Blank screens mounted arbitrary web views") { webViews(in: host).count == 2 }
        model.screenLayout = ScreenLayout(columns: 4, rows: 4)
        try await waitFor("Adding unused screens opened arbitrary sites") { webViews(in: host).count == 2 }
        print("PASS: fresh and newly added screens stay off and mount no web views")

        // Loaded pages can report very different preferred/minimum widths.
        // Exercise the mounted grid after WebKit has real content, not just
        // initially empty native views.
        for screen in model.screens {
            if screen.selectedApp == nil { model.select(.youtube, in: screen.id) }
            let view = screen.selectedController!.webView
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
                let view = model.screens[id].selectedController!.webView
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
        print("PASS: loaded sites with different content widths fill equal tiles in all sixteen layouts")

        for size in [CGSize(width: 901, height: 603), CGSize(width: 623, height: 537), CGSize(width: 441, height: 371)] {
            window.setContentSize(size)
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let views = model.screenLayout.screenIDs.map { model.screens[$0].selectedController!.webView }
            let rects = views.map { $0.convert($0.bounds, to: host) }
            for rect in rects {
                try require(abs(rect.width - rects[0].width) < 0.51 && abs(rect.height - rects[0].height) < 0.51,
                    "Resizing to \(size) produced unequal screens: \(rects)")
            }
            try require(abs(rects[0].maxX - rects[1].minX) < 0.51 && abs(rects[0].maxY - rects[model.screenLayout.columns].minY) < 0.51,
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
        model.screenLayout = .grid
        model.select(nil, in: 3)
        try await waitFor("Off screen still mounted its web view") { webViews(in: host).count == 3 }
        try require(model.selectedApp == nil && model.selectedController == nil,
            "Off screen retained active navigation controls")
        let restoredOff = PocketModel(defaults: defaults, loadPages: false)
        try require(restoredOff.screens[3].selectedApp == nil,
            "Off selection did not persist across launches")
        try require(defaults.string(forKey: "Pocket.screen.3.url.youtube") == "https://www.youtube.com/watch?v=pocket-fixture",
            "Switching off discarded the site's saved URL")
        model.select(.youtube, in: 3)
        try await waitFor("Choosing a site after Off did not restore its view") { webViews(in: host).count == 4 }
        try require(model.selectedController === bottom,
            "Choosing a site after Off rebuilt its controller")
        let afterOff = try await bottom.webView.evaluateJavaScript("window.screenMarker===42 && document.getElementById('draft').value==='remember me'") as? Bool
        try require(afterOff == true, "Switching off and back lost the live page or form")
        print("PASS: Off unmounts the page, persists across launches, and retains URL, controller, and live document")
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
        try require(restored.screenLayout == .grid && restored.screens[3].selectedApp?.id == "youtube",
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

        try await checkRootControlHover()
        try await checkScreenExpansion()
        try await checkPopupAndRecovery()

        model.setEnabled(false, for: .youtube)
        try require(model.screens.allSatisfy { $0.selectedApp == nil },
            "Disabling a site did not replace it on every screen")
        print("PASS: disabling a site switches its screens off without opening replacement websites")
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
