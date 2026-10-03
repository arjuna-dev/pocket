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
        for app in [SimulatedApp.youtube, SimulatedApp.whatsapp] {
            let controller = WebViewController(app: app, websiteDataStore: .nonPersistent(), loadImmediately: false)
            let view = controller.webView
            view.setFrameSize(NSSize(width: 600, height: 400))
            view.loadHTMLString("<!doctype html><style id='fixture-style'>body{margin:0}main{width:100%;height:100vh}</style><main>Responsive fixture</main>", baseURL: nil)
            try await waitFor("\(app.title): responsive viewport did not resize normally") {
                let m = try await metrics(view)
                return m["width"] as? Int == 600 && m["narrow"] as? Bool == false && view.pageZoom == 1
            }

            view.setFrameSize(NSSize(width: 390, height: 700))
            try await waitFor("\(app.title): narrow window did not retain the minimum viewport") {
                let m = try await metrics(view)
                return abs((m["width"] as? Int ?? 0) - 480) <= 1 && m["narrow"] as? Bool == true
            }

            view.setFrameSize(NSSize(width: 240, height: 150))
            try await waitFor("\(app.title): small window did not shrink to preserve both dimensions") {
                let m = try await metrics(view)
                return abs((m["width"] as? Int ?? 0) - 480) <= 1 && abs((m["height"] as? Int ?? 0) - 300) <= 1
            }

            view.setFrameSize(NSSize(width: 900, height: 240))
            try await waitFor("\(app.title): short window did not preserve minimum height") {
                let m = try await metrics(view)
                return abs((m["height"] as? Int ?? 0) - 300) <= 1
            }

            view.setFrameSize(NSSize(width: 900, height: 400))
            try await waitFor("\(app.title): enlarged window did not restore responsive sizing") {
                let m = try await metrics(view)
                return m["width"] as? Int == 900 && m["height"] as? Int == 400 && view.pageZoom == 1
            }
            _ = try await view.evaluateJavaScript("document.getElementById('fixture-style').textContent='html,body{margin:0;min-width:1200px}'")
            try await waitFor("\(app.title): website minimum width changed the shared zoom policy") {
                let m = try await metrics(view)
                return (m["content"] as? Int ?? 0) >= 1200 && view.pageZoom == 1
            }
            print("PASS: \(app.title) uses shared responsive and minimum viewport behavior")
        }
    }
}
