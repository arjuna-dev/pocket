import AppKit
import SwiftUI

extension Color {
    static let pocketBackground = Color(red: 0.055, green: 0.063, blue: 0.082)
    static let pocketChrome = Color(red: 0.145, green: 0.155, blue: 0.175)
    static let pocketMuted = Color(red: 0.48, green: 0.50, blue: 0.57)
}

struct AppRootView: View {
    @ObservedObject var model: PocketModel

    var body: some View {
        PocketStageView(model: model)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(Color.clear)
        .background(
            WindowBridge { window in
                WindowManager.shared.attach(window: window)
                WindowManager.shared.setAlwaysOnTop(model.alwaysOnTop)
                WindowManager.shared.ensureInitialSize(
                    for: model.presentationMode,
                    orientation: model.orientation,
                    footprint: model.layoutFootprint
                )
            }
            .frame(width: 1, height: 1)
        )
        .onAppear {
            model.applyPresentationMode()
            WindowManager.shared.restoreSize(
                for: model.presentationMode,
                orientation: model.orientation,
                footprint: model.layoutFootprint,
                animated: false
            )
        }
        .onChange(of: model.presentationMode) { _, newMode in
            model.applyPresentationMode()
            WindowManager.shared.restoreSize(
                for: newMode,
                orientation: model.orientation,
                footprint: model.layoutFootprint,
                animated: true
            )
        }
        .onChange(of: model.orientation) { _, newOrientation in
            WindowManager.shared.restoreSize(
                for: model.presentationMode,
                orientation: newOrientation,
                footprint: model.layoutFootprint,
                animated: true
            )
        }
        .onChange(of: model.layoutFootprint) { _, newFootprint in
            let keepSize = model.keepsWindowSizeForLayoutChange
            model.keepsWindowSizeForLayoutChange = false
            WindowManager.shared.restoreSize(
                for: model.presentationMode,
                orientation: model.orientation,
                footprint: newFootprint,
                animated: !keepSize,
                allowShrink: !keepSize
            )
        }
        .onChange(of: model.alwaysOnTop) { _, newValue in
            WindowManager.shared.setAlwaysOnTop(newValue)
        }
        .sheet(item: rootSheet) { sheet in
            switch sheet {
            case .websites:
                WebsiteManagerSheet(model: model)
            case .browserImport:
                BrowserImportSheet(model: model)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var rootSheet: Binding<PocketRootSheet?> {
        Binding(
            get: {
                if model.isBrowserImportPresented { return .browserImport }
                if model.isWebsiteManagerPresented { return .websites }
                return nil
            },
            set: { sheet in
                model.isWebsiteManagerPresented = sheet == .websites
                model.isBrowserImportPresented = sheet == .browserImport
            }
        )
    }
}

private enum PocketRootSheet: Identifiable {
    case websites
    case browserImport

    var id: String {
        switch self {
        case .websites: return "websites"
        case .browserImport: return "browserImport"
        }
    }
}


struct ServiceIcon: View {
    let app: SimulatedApp
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(app.tint)

                Image(systemName: app.symbolName)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(app.id == SimulatedApp.x.id ? Color.black.opacity(0.82) : .white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .task(id: app.urlString) {
            let data = await FaviconStore.shared.imageData(for: app.url)
            image = data.flatMap(NSImage.init(data:))
        }
    }
}
