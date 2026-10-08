import Foundation
import WebKit

enum SafariCompatibleUserAgent {
    /// WKWebView's default user agent omits the Safari version. Google then reads the
    /// frozen WebKit token and treats the browser as unsupported.
    static var current: String {
        let version = installedSafariVersion
            ?? "\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).0"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(version) Safari/605.1.15"
    }

    private static var installedSafariVersion: String? {
        guard let version = Bundle(url: URL(fileURLWithPath: "/Applications/Safari.app"))?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

final class ResponsiveWebView: WKWebView {
    var onViewportSizeChanged: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        let previousSize = frame.size
        super.setFrameSize(newSize)
        if previousSize != newSize {
            onViewportSizeChanged?()
        }
    }
}

final class WebViewController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let app: SimulatedApp
    let webView: WKWebView

    @Published private(set) var isLoading = true
    @Published private(set) var loadingProgress = 0.0
    @Published private(set) var errorMessage: String?
    @Published private(set) var pageTitle: String
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    /// True when the loaded page is dark, so the active edge can stay light.
    @Published private(set) var pageUsesDarkBackground = true

    var onLocationChange: (() -> Void)?
    private let themeRelay = PageThemeRelay()

    private var progressObservation: NSKeyValueObservation?
    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var themeSampleGeneration = 0
    private var themeSampleWork: DispatchWorkItem?
    private static let minimumViewportSize = CGSize(width: 480, height: 300)

    init(
        app: SimulatedApp,
        websiteDataStore: WKWebsiteDataStore? = nil,
        initialURL: URL? = nil,
        loadImmediately: Bool = true
    ) {
        self.app = app
        self.pageTitle = app.title

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore ?? WKWebsiteDataStore(
            forIdentifier: UUID(uuidString: app.dataStoreKey)!
        )
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.userContentController.add(themeRelay, name: "pocketPageTheme")
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.pageThemeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.inAppFullscreenScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let webView = ResponsiveWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = app.customUserAgent ?? SafariCompatibleUserAgent.current
        webView.pageZoom = 1.0
        webView.setValue(false, forKey: "drawsBackground")
        self.webView = webView

        super.init()
        themeRelay.owner = self

        webView.onViewportSizeChanged = { [weak self] in
            self?.applyViewportZoom()
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            self?.loadingProgress = webView.estimatedProgress
        }
        canGoBackObservation = webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, change in
            self?.canGoBack = change.newValue ?? false
        }
        canGoForwardObservation = webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, change in
            self?.canGoForward = change.newValue ?? false
        }
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.onLocationChange?()
            }
        }

        if loadImmediately {
            load(initialURL ?? app.url)
        }
    }

    deinit {
        progressObservation?.invalidate()
        canGoBackObservation?.invalidate()
        canGoForwardObservation?.invalidate()
        urlObservation?.invalidate()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "pocketPageTheme")
    }

    func load() {
        load(app.url)
    }

    func load(_ url: URL) {
        errorMessage = nil
        isLoading = true
        webView.load(URLRequest(url: url))
        syncHistoryState()
    }

    func reloadPage() {
        if webView.url != nil {
            webView.reload()
        } else {
            load()
        }
    }

    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }

    func setPresentationMode(_ mode: PresentationMode) {
        applyViewportZoom()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        errorMessage = nil
        themeSampleGeneration += 1
        applyViewportZoom()
        syncHistoryState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        pageTitle = webView.title?.isEmpty == false ? webView.title! : app.title
        syncHistoryState()
        applyViewportZoom()
        onLocationChange?()
        notePageThemeMayHaveChanged()
        for delay in [1.0, 2.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.capturePageTheme(generation: self.themeSampleGeneration)
            }
        }
    }

    func notePageThemeMayHaveChanged() {
        themeSampleWork?.cancel()
        let generation = themeSampleGeneration
        let work = DispatchWorkItem { [weak self] in
            self?.capturePageTheme(generation: generation)
        }
        themeSampleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// The border has to contrast with the pixels on the page. WhatsApp keeps a
    /// light document background behind a dark wallpaper, so a style walk gets
    /// the color wrong and draws a black edge on a dark screen.
    private func capturePageTheme(generation: Int) {
        guard generation == themeSampleGeneration else { return }
        let bounds = webView.bounds
        guard bounds.width > 8, bounds.height > 8 else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = bounds
        configuration.snapshotWidth = 96
        configuration.afterScreenUpdates = true
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            guard let self, generation == self.themeSampleGeneration, let image else { return }
            guard let dark = Self.edgeIsDark(image) else { return }
            DispatchQueue.main.async {
                guard generation == self.themeSampleGeneration else { return }
                if self.pageUsesDarkBackground != dark {
                    self.pageUsesDarkBackground = dark
                }
            }
        }
    }

    private static func edgeIsDark(_ image: NSImage) -> Bool? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 4, height > 4 else { return nil }

        var brightnesses: [CGFloat] = []
        let inset = 1
        func sample(_ x: Int, _ y: Int) {
            guard x >= 0, y >= 0, x < width, y < height,
                  let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return }
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            guard alpha > 0.4 else { return }
            brightnesses.append((red * 299 + green * 587 + blue * 114) / 1000)
        }

        let columns = 18
        let rows = 18
        for index in 0..<columns {
            let x = inset + (width - 1 - inset * 2) * index / max(columns - 1, 1)
            sample(x, inset)
            sample(x, height - 1 - inset)
        }
        for index in 1..<(rows - 1) {
            let y = inset + (height - 1 - inset * 2) * index / max(rows - 1, 1)
            sample(inset, y)
            sample(width - 1 - inset, y)
        }
        guard brightnesses.count >= 8 else { return nil }
        brightnesses.sort()
        return brightnesses[brightnesses.count / 2] < 0.62
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        errorMessage = userFacingMessage(for: error)
        syncHistoryState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        errorMessage = userFacingMessage(for: error)
        syncHistoryState()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    private func applyViewportZoom() {
        let size = webView.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        // Let sites reflow normally until either dimension becomes too small.
        // Below that threshold, zoom out to retain a usable CSS viewport.
        let zoom = min(1, size.width / Self.minimumViewportSize.width, size.height / Self.minimumViewportSize.height)
        applyPageZoom(zoom)
    }

    private func applyPageZoom(_ zoom: CGFloat) {
        let zoom = min(max(zoom, 0.1), 1)
        if abs(webView.pageZoom - zoom) > 0.005 {
            webView.pageZoom = zoom
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "Pocket could not reach the internet. Check your connection and try again."
            case NSURLErrorCancelled:
                return ""
            default:
                break
            }
        }
        return "This service could not be loaded right now."
    }

    private func syncHistoryState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    private static let pageThemeScript = #"""
    (() => {
        const opaque = (color) => {
            const match = String(color).match(/rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:[,\s/]+([\d.]+))?/);
            if (!match) return null;
            const alpha = match[4] == null ? 1 : Number(match[4]);
            if (!(alpha > 0.35)) return null;
            const brightness = (Number(match[1]) * 299 + Number(match[2]) * 587 + Number(match[3]) * 114) / 1000;
            return brightness < 148;
        };

        const backgroundIsDark = (element) => {
            let node = element;
            while (node && node.nodeType === 1) {
                const dark = opaque(getComputedStyle(node).backgroundColor);
                if (dark != null) return dark;
                node = node.parentElement;
            }
            return null;
        };

        const sample = () => {
            const width = window.innerWidth || 0;
            const height = window.innerHeight || 0;
            const points = [
                [width * 0.5, height * 0.5],
                [width * 0.18, height * 0.18],
                [width * 0.82, height * 0.18],
                [width * 0.18, height * 0.82],
                [width * 0.82, height * 0.82]
            ];
            let dark = 0;
            let light = 0;
            for (const [x, y] of points) {
                const hit = document.elementFromPoint(Math.max(1, x), Math.max(1, y));
                const value = backgroundIsDark(hit);
                if (value === true) dark += 1;
                else if (value === false) light += 1;
            }
            if (dark + light === 0) {
                const scheme = getComputedStyle(document.documentElement).colorScheme || "";
                if (scheme.includes("light") && !scheme.includes("dark")) return "light";
                if (scheme.includes("dark")) return "dark";
                return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
            }
            return dark >= light ? "dark" : "light";
        };

        let last = "";
        let timer = 0;
        const report = () => {
            let theme = "dark";
            try { theme = sample(); } catch (_) {}
            if (theme === last) return;
            last = theme;
            try { window.webkit.messageHandlers.pocketPageTheme.postMessage(theme); } catch (_) {}
        };
        const schedule = () => {
            window.clearTimeout(timer);
            timer = window.setTimeout(report, 120);
        };

        window.__pocketSamplePageTheme = () => {
            try { return sample(); } catch (_) { return "dark"; }
        };

        const watch = () => {
            report();
            const observer = new MutationObserver(schedule);
            observer.observe(document.documentElement, {
                attributes: true,
                attributeFilter: ["class", "style", "data-theme", "data-color-mode"]
            });
            if (document.body) {
                observer.observe(document.body, {
                    attributes: true,
                    attributeFilter: ["class", "style"]
                });
            }
            const media = window.matchMedia("(prefers-color-scheme: dark)");
            if (media.addEventListener) media.addEventListener("change", schedule);
        };

        if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", watch, { once: true });
        } else {
            watch();
        }
        window.setTimeout(schedule, 400);
        window.setTimeout(schedule, 1400);
    })();
    """#

    private static let inAppFullscreenScript = #"""
    (() => {
        const htmlClass = "pocket-in-app-fullscreen";
        const targetClass = "pocket-fullscreen-target";
        let fullscreenElement = null;
        let fullscreenTarget = null;

        const style = document.createElement("style");
        style.id = "pocket-in-app-fullscreen-styles";
        style.textContent = `
            html.${htmlClass},
            html.${htmlClass} body {
                background: #000 !important;
                overflow: hidden !important;
            }

            html.${htmlClass} .${targetClass} {
                position: fixed !important;
                inset: 0 !important;
                width: 100vw !important;
                height: 100vh !important;
                max-width: none !important;
                max-height: none !important;
                margin: 0 !important;
                z-index: 2147483647 !important;
                background: #000 !important;
                overflow: hidden !important;
            }

            html.${htmlClass} .${targetClass} .html5-video-container,
            html.${htmlClass} .${targetClass} .html5-main-video,
            html.${htmlClass} .${targetClass} video {
                position: absolute !important;
                inset: 0 !important;
                width: 100% !important;
                height: 100% !important;
                max-width: none !important;
                max-height: none !important;
                object-fit: contain !important;
            }
        `;

        const installStyles = () => {
            const parent = document.head || document.documentElement;
            if (parent && style.parentNode !== parent) {
                parent.appendChild(style);
            }
        };

        installStyles();

        const defineGetter = (target, name, getter) => {
            try {
                Object.defineProperty(target, name, {
                    configurable: true,
                    get: getter
                });
            } catch (_) {
                // Some WebKit properties may be non-configurable.
            }
        };

        const installMethod = (target, name, method) => {
            try {
                Object.defineProperty(target, name, {
                    configurable: true,
                    writable: true,
                    value: method
                });
            } catch (_) {
                try {
                    target[name] = method;
                } catch (_) {
                    // Keep the native method if WebKit does not allow replacement.
                }
            }
        };

        const playerFor = (element) => {
            if (!(element instanceof Element)) {
                return document.querySelector(".html5-video-player, #movie_player") || element;
            }

            return element.closest(".html5-video-player, #movie_player") || element;
        };

        const dispatchFullscreenChange = (element) => {
            document.dispatchEvent(new Event("fullscreenchange"));
            document.dispatchEvent(new Event("webkitfullscreenchange"));

            if (element instanceof Element) {
                element.dispatchEvent(new Event("fullscreenchange"));
                element.dispatchEvent(new Event("webkitfullscreenchange"));
            }
        };

        const enterFullscreen = function() {
            if (fullscreenTarget instanceof Element) {
                fullscreenTarget.classList.remove(targetClass);
            }

            fullscreenElement = this instanceof Element ? this : null;
            fullscreenTarget = playerFor(fullscreenElement);

            if (fullscreenTarget instanceof Element) {
                fullscreenTarget.classList.add(targetClass);
            }

            installStyles();
            document.documentElement.classList.add(htmlClass);
            dispatchFullscreenChange(fullscreenElement);
            return Promise.resolve();
        };

        const exitFullscreen = function() {
            const previousElement = fullscreenElement;

            if (fullscreenTarget instanceof Element) {
                fullscreenTarget.classList.remove(targetClass);
            }

            fullscreenElement = null;
            fullscreenTarget = null;
            document.documentElement.classList.remove(htmlClass);
            dispatchFullscreenChange(previousElement);
            return Promise.resolve();
        };

        defineGetter(Document.prototype, "fullscreenEnabled", () => true);
        defineGetter(Document.prototype, "webkitFullscreenEnabled", () => true);
        defineGetter(Document.prototype, "fullscreenElement", () => fullscreenElement);
        defineGetter(Document.prototype, "webkitFullscreenElement", () => fullscreenElement);

        installMethod(Element.prototype, "requestFullscreen", enterFullscreen);
        installMethod(Element.prototype, "webkitRequestFullscreen", enterFullscreen);
        installMethod(Element.prototype, "webkitRequestFullScreen", enterFullscreen);
        installMethod(Document.prototype, "exitFullscreen", exitFullscreen);
        installMethod(Document.prototype, "webkitExitFullscreen", exitFullscreen);

        if (window.HTMLVideoElement) {
            installMethod(HTMLVideoElement.prototype, "webkitEnterFullscreen", enterFullscreen);
            installMethod(HTMLVideoElement.prototype, "webkitExitFullscreen", exitFullscreen);
        }

        const fullscreenButtonFor = (node) => {
            if (!(node instanceof Element)) {
                return null;
            }

            let current = node;
            while (current && current !== document.documentElement) {
                const label = (current.getAttribute("aria-label") || "").toLowerCase();
                const title = (current.getAttribute("title") || "").toLowerCase();
                const classTokens = typeof current.className === "string"
                    ? current.className.toLowerCase().split(/\s+/).filter(Boolean)
                    : [];
                const isButtonLike = current.tagName === "BUTTON" ||
                    current.getAttribute("role") === "button" ||
                    classTokens.includes("ytp-fullscreen-button") ||
                    classTokens.includes("fullscreen-button");
                const hasFullscreenClass = classTokens.includes("ytp-fullscreen-button") ||
                    classTokens.includes("fullscreen-button");

                if (
                    isButtonLike && (hasFullscreenClass ||
                        label.includes("full screen") ||
                        label.includes("fullscreen") ||
                        title.includes("full screen") ||
                        title.includes("fullscreen"))
                ) {
                    return current;
                }

                current = current.parentElement;
            }

            return null;
        };

        const fullscreenButtonFromEvent = (event) => {
            for (const node of event.composedPath()) {
                const button = fullscreenButtonFor(node);
                if (button) {
                    return button;
                }
            }

            return fullscreenButtonFor(event.target);
        };

        const playerForEvent = (event) => {
            const button = fullscreenButtonFromEvent(event);
            return button?.closest(".html5-video-player, #movie_player") ||
                document.querySelector(".html5-video-player, #movie_player");
        };

        const playerForKeyEvent = (event) => {
            const target = event.target instanceof Element ? event.target : document.activeElement;
            const textInput = target?.matches("input, textarea, [contenteditable='true']") ||
                target?.closest("input, textarea, [contenteditable='true']");

            if (textInput) {
                return null;
            }

            return target?.closest(".html5-video-player, #movie_player") ||
                (target === document.body ? document.querySelector(".html5-video-player, #movie_player") : null);
        };

        document.addEventListener("click", (event) => {
            const button = fullscreenButtonFromEvent(event);
            if (!button) {
                return;
            }

            const player = playerForEvent(event);
            if (!(player instanceof Element)) {
                return;
            }

            event.preventDefault();
            event.stopImmediatePropagation();

            if (fullscreenElement) {
                exitFullscreen();
            } else {
                enterFullscreen.call(player);
            }
        }, true);

        document.addEventListener("keydown", (event) => {
            if (event.key === "Escape" && fullscreenElement) {
                exitFullscreen();
                return;
            }

            if ((event.key === "f" || event.key === "F") && !event.metaKey && !event.ctrlKey && !event.altKey) {
                const player = playerForKeyEvent(event);
                if (player instanceof Element) {
                    event.preventDefault();
                    event.stopImmediatePropagation();

                    if (fullscreenElement) {
                        exitFullscreen();
                    } else {
                        enterFullscreen.call(player);
                    }
                }
            }
        },         true);
    })();
    """#
}

private final class PageThemeRelay: NSObject, WKScriptMessageHandler {
    weak var owner: WebViewController?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.body is String else { return }
        DispatchQueue.main.async { [weak owner] in
            owner?.notePageThemeMayHaveChanged()
        }
    }
}
