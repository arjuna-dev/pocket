import Foundation
import WebKit

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

private final class ViewportMessageHandler: NSObject, WKScriptMessageHandler {
    weak var controller: WebViewController?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        controller?.scheduleViewportUpdate()
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

    private var progressObservation: NSKeyValueObservation?
    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?
    private var viewportUpdate: DispatchWorkItem?
    private var viewportGeneration = 0
    private var minimumLayoutWidth: CGFloat = 0

    init(app: SimulatedApp) {
        self.app = app
        self.pageTitle = app.title

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(
            forIdentifier: UUID(uuidString: app.dataStoreKey)!
        )
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.inAppFullscreenScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let viewportHandler = ViewportMessageHandler()
        if app.id == SimulatedApp.whatsapp.id {
            configuration.userContentController.add(viewportHandler, contentWorld: .defaultClient, name: "pocketViewport")
            configuration.userContentController.addUserScript(WKUserScript(
                source: Self.viewportObserverScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                in: .defaultClient
            ))
        }

        let webView = ResponsiveWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = app.customUserAgent
        webView.pageZoom = 1.0
        webView.setValue(false, forKey: "drawsBackground")
        self.webView = webView

        super.init()

        viewportHandler.controller = self
        webView.onViewportSizeChanged = { [weak self] in
            self?.scheduleViewportUpdate()
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

        load()
    }

    deinit {
        viewportUpdate?.cancel()
        progressObservation?.invalidate()
        canGoBackObservation?.invalidate()
        canGoForwardObservation?.invalidate()
    }

    func load() {
        errorMessage = nil
        isLoading = true
        webView.load(URLRequest(url: app.url))
        syncHistoryState()
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
        scheduleViewportUpdate()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        errorMessage = nil
        viewportGeneration += 1
        minimumLayoutWidth = 0
        webView.pageZoom = 1.0
        syncHistoryState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        pageTitle = webView.title?.isEmpty == false ? webView.title! : app.title
        syncHistoryState()
        scheduleViewportUpdate()
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

    fileprivate func scheduleViewportUpdate() {
        guard app.id == SimulatedApp.whatsapp.id else { return }
        viewportGeneration += 1
        let generation = viewportGeneration
        viewportUpdate?.cancel()
        let update = DispatchWorkItem { [weak self] in
            self?.fitDesktopLayout(generation: generation)
        }
        viewportUpdate = update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: update)
    }

    private func fitDesktopLayout(generation: Int) {
        let width = webView.bounds.width
        guard width > 0 else { return }

        if minimumLayoutWidth > 0 {
            applyPageZoom(min(1, width / minimumLayoutWidth))
        }
        webView.evaluateJavaScript(Self.viewportMeasurementScript, in: nil, in: .defaultClient) { [weak self] result in
            guard let self, self.viewportGeneration == generation,
                  case .success(let value) = result,
                  let metrics = value as? [String: Any],
                  let viewport = metrics["viewport"] as? Double,
                  let content = metrics["content"] as? Double,
                  viewport > 0, content.isFinite else { return }

            if let minimum = metrics["minimum"] as? Double, minimum > 0 {
                self.minimumLayoutWidth = minimum
            }
            if content > viewport + 1 {
                // CSS pixels reflect page zoom. Recover the required width at
                // 100% so enlarging the window can restore normal text size.
                self.minimumLayoutWidth = max(self.minimumLayoutWidth, content)
                self.applyPageZoom(min(1, self.webView.pageZoom * viewport / content))
            } else if self.minimumLayoutWidth > 0 {
                self.applyPageZoom(min(1, self.webView.bounds.width / self.minimumLayoutWidth))
            }
        }
    }

    private func applyPageZoom(_ zoom: CGFloat) {
        let zoom = min(max(zoom, 0.1), 1)
        if abs(webView.pageZoom - zoom) > 0.005 {
            webView.pageZoom = zoom
        }
    }

    private static let viewportMeasurementScript = #"""
    (() => {
        const root = document.documentElement;
        const elements = [root, document.body, document.getElementById('app')].filter(Boolean);
        return {
            viewport: root.clientWidth,
            content: Math.max(...elements.map(element => element.scrollWidth)),
            minimum: Math.max(0, ...elements.map(element => parseFloat(getComputedStyle(element).minWidth) || 0))
        };
    })()
    """#

    private static let viewportObserverScript = #"""
    (() => {
        let pending = false;
        const notify = () => {
            if (pending) return;
            pending = true;
            setTimeout(() => {
                pending = false;
                window.webkit.messageHandlers.pocketViewport.postMessage(null);
            }, 80);
        };
        new ResizeObserver(notify).observe(document.documentElement);
        new MutationObserver(notify).observe(document.documentElement, {
            subtree: true, childList: true, attributes: true,
            attributeFilter: ['class', 'style']
        });
        notify();
    })();
    """#

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
        }, true);
    })();
    """#
}
