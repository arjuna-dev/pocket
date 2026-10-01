import AppKit
import WebKit

@main
struct ResponsiveViewportTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                try await run()
                print("Responsive viewport checks passed")
                exit(0)
            } catch {
                fputs("FAIL: \(error)\n", stderr)
                exit(1)
            }
        }
        NSApplication.shared.run()
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @MainActor static func metrics(_ view: WKWebView) async throws -> [String: Any] {
        let value = try await view.evaluateJavaScript("({width:innerWidth,height:innerHeight,content:document.documentElement.scrollWidth,narrow:matchMedia('(max-width: 500px)').matches})")
        guard let result = value as? [String: Any] else { throw Failure(description: "No viewport metrics") }
        return result
    }

    @MainActor static func waitFor(_ message: String, condition: () async throws -> Bool) async throws {
        for _ in 0..<80 {
            if (try? await condition()) == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Failure(description: message)
    }

    @MainActor static func run() async throws {
        let responsive = WebViewController(app: .youtube, websiteDataStore: .nonPersistent(), loadImmediately: false)
        responsive.webView.setFrameSize(NSSize(width: 390, height: 700))
        responsive.webView.loadHTMLString("<!doctype html><style>body{margin:0}main{width:100%;height:100vh}</style><main>Responsive fixture</main>", baseURL: nil)
        try await waitFor("Narrow viewport didn't activate media query") {
            let m = try await metrics(responsive.webView)
            return m["narrow"] as? Bool == true && m["width"] as? Int == 390
        }
        responsive.webView.setFrameSize(NSSize(width: 900, height: 400))
        try await waitFor("Resizing didn't update the website viewport") {
            let m = try await metrics(responsive.webView)
            return m["narrow"] as? Bool == false && m["width"] as? Int == 900 && m["height"] as? Int == 400
        }
        guard responsive.webView.pageZoom == 1 else { throw Failure(description: "Responsive website was unnecessarily zoomed") }
        print("PASS: responsive media queries and viewport dimensions update")

        let desktop = WebViewController(app: .whatsapp, websiteDataStore: .nonPersistent(), loadImmediately: false)
        desktop.webView.setFrameSize(NSSize(width: 390, height: 700))
        desktop.webView.loadHTMLString("<!doctype html><style id='fixture-style'>html,body{margin:0;min-width:1000px}#app{min-width:1000px;height:100vh}</style><main id='app'>Desktop fixture</main>", baseURL: nil)
        try await waitFor("Desktop layout didn't fit a narrow window") {
            abs(desktop.webView.pageZoom - 0.39) < 0.015
        }
        desktop.webView.setFrameSize(NSSize(width: 700, height: 350))
        try await waitFor("Desktop zoom didn't follow resizing") {
            abs(desktop.webView.pageZoom - 0.7) < 0.015
        }
        desktop.webView.setFrameSize(NSSize(width: 1300, height: 700))
        try await waitFor("Desktop zoom didn't return to normal in a large window") {
            abs(desktop.webView.pageZoom - 1) < 0.005
        }
        desktop.webView.setFrameSize(NSSize(width: 400, height: 700))
        try await waitFor("Desktop layout didn't fit after shrinking again") {
            abs(desktop.webView.pageZoom - 0.4) < 0.015
        }
        _ = try await desktop.webView.evaluateJavaScript("document.getElementById('fixture-style').textContent='html,body{margin:0;min-width:1200px}#app{min-width:1200px;height:100vh}'")
        try await waitFor("Fit didn't update after dynamic page layout changed") {
            abs(desktop.webView.pageZoom - 1.0 / 3.0) < 0.015
        }
        print("PASS: desktop fitting updates on resize and dynamic content changes")
    }
}
