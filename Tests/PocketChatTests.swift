import AppKit
import Foundation

actor FixtureClient: PocketAIClient {
    var signedIn = false
    var nextChange: PocketWorkspaceChange?
    var delay: Duration = .zero
    var loginWaiter: CheckedContinuation<Void, Error>?
    var isWaitingForLogin = false
    func account() async throws -> PocketAIAccount { .init(isSignedIn: signedIn, email: nil) }
    func setSignedIn(_ value: Bool) { signedIn = value }
    func configure(_ change: PocketWorkspaceChange, delay: Duration = .zero) { nextChange = change; self.delay = delay }
    func startLogin() async throws -> PocketAILogin { .init(id: "login", url: URL(string: "https://auth.openai.com/fixture")!) }
    func finishLogin(_ id: String) async throws {
        try await withCheckedThrowingContinuation { loginWaiter = $0; isWaitingForLogin = true }
    }
    func completeLogin() { signedIn = true; isWaitingForLogin = false; loginWaiter?.resume(); loginWaiter = nil }
    func cancelLogin(_ id: String) async { isWaitingForLogin = false; loginWaiter?.resume(throwing: CancellationError()); loginWaiter = nil }
    func generate(prompt: String, workspace: PocketWorkspace) async throws -> PocketWorkspaceChange {
        let change = nextChange!
        // A late reply must never apply after the controller has been cancelled.
        try? await Task.sleep(for: delay)
        return change
    }
    func interrupt() async {}
    func shutdown() async { await cancelLogin("login") }
}

@main struct PocketChatTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw Failure(description: message) }
    }
    @MainActor static func waitFor(_ condition: () async -> Bool) async throws {
        for _ in 0..<150 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw Failure(description: "Timed out waiting for fixture")
    }
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do { try await run(); print("Pocket chat checks passed"); exit(0) }
            catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        NSApplication.shared.run()
    }
    @MainActor static func run() async throws {
        let suite = "Pocket.ChatTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = FixtureClient()
        let chat = PocketChatController(client: client)
        let model = PocketModel(defaults: defaults, loadPages: false, chat: chat)
        model.select(.youtube, in: 15)
        let retained = model.screens[15].selectedController!
        for layout in ScreenLayout.allCases {
            let before = model.workspace(revision: 7)
            try model.apply(.init(baseRevision: 7, layout: .init(columns: layout.columns, rows: layout.rows), screenUpdates: [], message: ""), expecting: before)
            try require(model.screenLayout == layout && model.screens[15].selectedController === retained,
                "Layout command lost a hidden web view")
        }
        let original = model.workspace(revision: 8)
        for change in [
            PocketWorkspaceChange(baseRevision: 8, layout: .init(columns: 5, rows: 1), screenUpdates: [], message: ""),
            .init(baseRevision: 8, layout: .init(columns: 1, rows: 1), screenUpdates: [.init(screenId: 1, siteId: "youtube", url: nil)], message: ""),
            .init(baseRevision: 8, layout: nil, screenUpdates: [.init(screenId: 0, siteId: "youtube", url: nil), .init(screenId: 1, siteId: "custom", url: "file:///etc/passwd")], message: ""),
            .init(baseRevision: 8, layout: nil, screenUpdates: [.init(screenId: 0, siteId: "unknown", url: nil)], message: ""),
            .init(baseRevision: 8, layout: nil, screenUpdates: [.init(screenId: 0, siteId: nil, url: "https://example.com")], message: ""),
            .init(baseRevision: 8, layout: nil, screenUpdates: [.init(screenId: 0, siteId: "youtube", url: "https://user:password@example.com")], message: ""),
            .init(baseRevision: 8, layout: nil, screenUpdates: [.init(screenId: 0, siteId: "youtube", url: nil), .init(screenId: 0, siteId: nil, url: nil)], message: "")
        ] {
            do { try model.apply(change, expecting: original); throw Failure(description: "Accepted an invalid command") }
            catch is PocketWorkspaceError {}
            try require(model.workspace(revision: 8) == original, "Invalid response partially changed the workspace")
        }
        model.screenLayout = .single
        do {
            try model.apply(.init(baseRevision: 8, layout: original.layout, screenUpdates: [], message: ""), expecting: original)
            throw Failure(description: "Overwrote a manual edit with a stale reply")
        } catch is PocketWorkspaceError {}
        print("PASS: all 16 layouts, hidden web views, atomic validation, and stale reply protection")

        await chat.toggle()
        try require(chat.isLoginPresented && !chat.isComposerVisible, "Signed-out click did not open explanation")
        chat.cancelLogin()
        chat.isLoginPresented = true
        var openedURL: URL?
        chat.login { openedURL = $0; return true }
        try await waitFor { await client.isWaitingForLogin }
        try require(openedURL?.host == "auth.openai.com", "Login did not open the browser flow")
        await client.completeLogin()
        try await waitFor { chat.isSignedIn && chat.isComposerVisible }
        try require(!chat.isLoginPresented, "Successful login left the modal open")
        await chat.toggle()
        try require(!chat.isComposerVisible, "Second click did not hide composer")
        await chat.toggle()
        try require(chat.isComposerVisible && !chat.isLoginPresented, "Signed-in click opened login modal")
        await client.configure(.init(baseRevision: 1, layout: .init(columns: 2, rows: 2), screenUpdates: [.init(screenId: 0, siteId: "telegram", url: nil), .init(screenId: 1, siteId: "youtube", url: nil)], message: "Ready"))
        chat.prompt = "2x2, Telegram top left, YouTube top right"
        chat.submit(to: model)
        try await waitFor { !chat.isWorking }
        try require(!chat.isError && model.screenLayout == .grid && model.screens[0].selectedApp?.id == "telegram" && model.screens[1].selectedApp?.id == "youtube", "Chat did not apply its structured response")
        try require(chat.toast?.message == "Ready", "Successful request did not show a toast")
        try require(model.screens[2].selectedApp == nil && model.screens[3].selectedApp == nil && model.screens[15].selectedController === retained,
            "Unmentioned screens were filled or discarded")
        model.screenLayout = .single
        await client.configure(.init(baseRevision: 2, layout: .init(columns: 4, rows: 4), screenUpdates: [], message: ""), delay: .milliseconds(200))
        chat.prompt = "4x4"
        chat.submit(to: model)
        try await Task.sleep(for: .milliseconds(30))
        chat.cancelRequest()
        try await waitFor { !chat.isWorking }
        try await Task.sleep(for: .milliseconds(250))
        try require(model.screenLayout == .single, "Cancelled command changed the layout")
        print("PASS: signed-out modal, browser login, signed-in composer, request application, cancellation")

        await client.configure(.init(baseRevision: 3, layout: .init(columns: 2, rows: 2), screenUpdates: [], message: "Ready"), delay: .milliseconds(200))
        chat.submit(to: model)
        try await Task.sleep(for: .milliseconds(30))
        model.screenLayout = .stacked
        try await waitFor { !chat.isWorking }
        try require(chat.toast?.isError == true && chat.toast!.message.contains("Your view changed") && model.screenLayout == .stacked,
            "Stale request did not preserve manual edits and show a warning toast")
        let notifications = PocketChatController(client: client, toastDuration: .milliseconds(150))
        notifications.showToast("First")
        try await Task.sleep(for: .milliseconds(100))
        notifications.showToast("Replacement", isError: true)
        try await Task.sleep(for: .milliseconds(80))
        try require(notifications.toast?.message == "Replacement", "Old toast timer cleared a newer notification")
        try await waitFor { notifications.toast == nil }
        notifications.showToast("Dismiss")
        notifications.dismissToast()
        try require(notifications.toast == nil, "Toast did not dismiss immediately")
        print("PASS: transient success and warning toasts, replacement deadlines, and dismissal")

        let activity = ScreenChromeActivity(timeout: 0.2)
        activity.activateForTyping(0)
        try await Task.sleep(for: .milliseconds(100))
        activity.activate(1)
        try await Task.sleep(for: .milliseconds(250))
        try require(activity.screenID == 1, "Mouse movement shortened the double timeout after typing")
        try await waitFor { activity.screenID == nil }
        activity.activateForTyping(0)
        activity.leave()
        try require(activity.screenID == nil, "Pointer exit did not immediately hide controls after typing")
        activity.activate(0)
        activity.hold(true)
        try await Task.sleep(for: .milliseconds(250))
        activity.leave()
        try require(activity.screenID == 0, "Controls hid while the model was working")
        activity.hold(false)
        activity.leave()
        try require(activity.screenID == nil, "Finishing outside the window did not release the visibility hold")
        activity.activate(0)
        activity.hold(true)
        activity.hold(false)
        try require(activity.screenID == 0, "Finishing inside the window did not resume the normal timer")
        try await waitFor { activity.screenID == nil }
        print("PASS: doubled typing deadline, immediate exit hiding, working hold, and normal timeout after completion")

        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let manager = WindowManager(defaults: defaults)
        manager.attach(window: window)
        manager.resize(for: .screen, orientation: .landscape, layout: .single, size: CGSize(width: 600, height: 400), animated: false, force: true)
        let top = window.frame.maxY
        manager.setChatComposerVisible(true)
        let composerHeight = PocketChatController.composerHeight
        try require(window.contentRect(forFrameRect: window.frame).height == 400 + composerHeight && window.frame.maxY == top, "Composer shrank pages or moved the top edge")
        manager.changeScreenLayout(to: .grid)
        let outer = window.contentRect(forFrameRect: window.frame).size
        let page = ScreenLayout.grid.pageSize(in: CGSize(width: outer.width, height: outer.height - composerHeight))
        try require(page == CGSize(width: 600, height: 312), "Layout switch included composer in the page size")
        NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: window)
        manager.setChatComposerVisible(false)
        manager.restoreSize(for: .screen, orientation: .landscape, layout: .single, animated: false)
        try require(window.contentRect(forFrameRect: window.frame).size == CGSize(width: 600, height: 400), "Saved page size included composer")
        print("PASS: composer grows downward, layout switching preserves page size, saved dimensions exclude chat")

        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PocketChatTransport-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for mode in ["normal", "error", "invalid", "timeout", "disconnect"] {
            let server = CodexAppServerClient(executable: fixture, directory: root.appendingPathComponent(mode), requestTimeout: 0.5)
            do {
                if ["timeout", "disconnect"].contains(mode) {
                    do { _ = try await server.account(); throw Failure(description: "Failed to reject broken helper") }
                    catch is PocketAIError {}
                } else {
                    try require(try await server.account().isSignedIn, "Transport lost account response")
                    if mode == "normal" {
                        let login = try await server.startLogin()
                        try await server.finishLogin(login.id)
                        let response = try await server.generate(prompt: "4x3", workspace: model.workspace(revision: 9))
                        try require(response.baseRevision == 9 && response.layout?.rows == 3, "Lost fragmented or early notifications")
                    } else {
                        do { _ = try await server.generate(prompt: "test", workspace: model.workspace(revision: 9)); throw Failure(description: "Accepted invalid or failed inference") }
                        catch is PocketAIError {}
                    }
                }
                await server.shutdown()
            } catch { await server.shutdown(); throw error }
        }
        print("PASS: JSON-RPC fragmentation, early login/turn completion, server errors, malformed JSON, timeout, process exit")
        let live = CodexAppServerClient(directory: root.appendingPathComponent("live"))
        do {
            let account = try await live.account()
            try require(!account.isSignedIn, "Pocket accidentally reused another app's sign-in")
            await live.shutdown()
        } catch { await live.shutdown(); throw error }
        print("PASS: real native Codex helper starts with isolated Pocket credentials")
    }
}
