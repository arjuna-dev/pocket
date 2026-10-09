import AppKit
import SwiftUI
import WebKit

struct ScreenStage: View {
    @ObservedObject var controller: WebViewController

    var body: some View {
        WebContent(controller: controller, cornerRadius: 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }
}

struct WebContent: View {
    @ObservedObject var controller: WebViewController
    let cornerRadius: CGFloat

    var body: some View {
        if cornerRadius > 0 {
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
        }
    }

    private var content: some View {
        ZStack(alignment: .top) {
            WebViewRepresentable(controller: controller)
                .id(ObjectIdentifier(controller))

            if controller.isLoading {
                VStack(spacing: 0) {
                    ProgressView(value: controller.loadingProgress)
                        .tint(controller.app.tint)
                        .progressViewStyle(.linear)
                        .frame(height: 2)

                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)

                        Text("Connecting to \(controller.app.title)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.78))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 14)
                }
            }

            if let errorMessage = controller.errorMessage, !errorMessage.isEmpty {
                ErrorOverlay(message: errorMessage, tint: controller.app.tint) {
                    controller.load()
                }
            }
        }
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    @ObservedObject var controller: WebViewController

    func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct ErrorOverlay: View {
    let message: String
    let tint: Color
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: 50, height: 50)

                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(tint)
            }

            Text("Could not connect")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: retry) {
                Text("Try again")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(tint)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(26)
        .frame(maxWidth: 310)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.20))
    }
}
