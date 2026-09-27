import Foundation
import WebKit

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

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = app.customUserAgent
        webView.pageZoom = app.id == SimulatedApp.whatsapp.id ? 0.52 : 1.0
        webView.setValue(false, forKey: "drawsBackground")
        self.webView = webView

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        progressObservation = webView.observe(\WKWebView.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            self?.loadingProgress = webView.estimatedProgress
        }

        load()
    }

    deinit {
        progressObservation?.invalidate()
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
        guard app.id == SimulatedApp.whatsapp.id else { return }
        webView.pageZoom = mode == .device ? 0.52 : 1.0
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        errorMessage = nil
        syncHistoryState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        pageTitle = webView.title?.isEmpty == false ? webView.title! : app.title
        syncHistoryState()
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
