import SwiftUI

struct SimulatedApp: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var subtitle: String
    var urlString: String
    var symbolName: String
    var tintHex: String
    let dataStoreKey: String
    let customUserAgent: String?
    let isBuiltIn: Bool
    var isEnabled: Bool

    var url: URL {
        URL(string: urlString) ?? URL(string: "about:blank")!
    }

    var tint: Color {
        Color(hex: tintHex)
    }

    var isCustom: Bool {
        !isBuiltIn
    }

    static let whatsapp = SimulatedApp(
        id: "whatsapp",
        title: "WhatsApp",
        subtitle: "Messages",
        urlString: "https://web.whatsapp.com",
        symbolName: "message.fill",
        tintHex: "#30C878",
        dataStoreKey: "C5E5F76F-0D51-4D4D-BB38-8D72AC9C1A01",
        customUserAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36",
        isBuiltIn: true
    )

    static let telegram = SimulatedApp(
        id: "telegram",
        title: "Telegram",
        subtitle: "Messages",
        urlString: "https://web.telegram.org/k/",
        symbolName: "paperplane.fill",
        tintHex: "#389CE0",
        dataStoreKey: "C5E5F76F-0D51-4D4D-BB38-8D72AC9C1A02",
        isBuiltIn: true
    )

    static let youtube = SimulatedApp(
        id: "youtube",
        title: "YouTube",
        subtitle: "Video",
        urlString: "https://www.youtube.com",
        symbolName: "play.rectangle.fill",
        tintHex: "#FA332E",
        dataStoreKey: "C5E5F76F-0D51-4D4D-BB38-8D72AC9C1A03",
        isBuiltIn: true
    )

    static let x = SimulatedApp(
        id: "x",
        title: "X",
        subtitle: "Social",
        urlString: "https://x.com",
        symbolName: "at",
        tintHex: "#D6DBE5",
        dataStoreKey: "C5E5F76F-0D51-4D4D-BB38-8D72AC9C1A04",
        isBuiltIn: true
    )

    static let spotify = SimulatedApp(
        id: "spotify",
        title: "Spotify",
        subtitle: "Music",
        urlString: "https://open.spotify.com",
        symbolName: "waveform",
        tintHex: "#4DDC6E",
        dataStoreKey: "C5E5F76F-0D51-4D4D-BB38-8D72AC9C1A05",
        isBuiltIn: true
    )

    static let allCases = [whatsapp, telegram, youtube, x, spotify]

    static func custom(
        title: String,
        subtitle: String,
        urlString: String,
        symbolName: String
    ) -> SimulatedApp {
        let id = UUID().uuidString
        return SimulatedApp(
            id: id,
            title: title,
            subtitle: subtitle,
            urlString: urlString,
            symbolName: symbolName,
            tintHex: "#C65F38",
            dataStoreKey: id,
            isBuiltIn: false
        )
    }

    private init(
        id: String,
        title: String,
        subtitle: String,
        urlString: String,
        symbolName: String,
        tintHex: String,
        dataStoreKey: String,
        customUserAgent: String? = nil,
        isBuiltIn: Bool,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.urlString = urlString
        self.symbolName = symbolName
        self.tintHex = tintHex
        self.dataStoreKey = dataStoreKey
        self.customUserAgent = customUserAgent
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
    }

    static func == (lhs: SimulatedApp, rhs: SimulatedApp) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(cleaned, radix: 16) ?? 0xC65F38
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

enum PresentationMode: String, CaseIterable, Identifiable {
    case device
    case screen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .device: return "Device"
        case .screen: return "Screen"
        }
    }

    var symbolName: String {
        switch self {
        case .device: return "iphone"
        case .screen: return "rectangle.inset.filled"
        }
    }
}

enum DeviceOrientation: String, CaseIterable, Identifiable {
    case portrait
    case landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portrait: return "Portrait"
        case .landscape: return "Landscape"
        }
    }

    var symbolName: String {
        switch self {
        case .portrait: return "iphone"
        case .landscape: return "iphone.landscape"
        }
    }

    var toggleSymbolName: String {
        self == .portrait ? DeviceOrientation.landscape.symbolName : DeviceOrientation.portrait.symbolName
    }

    var deviceSize: CGSize {
        switch self {
        case .portrait: return CGSize(width: 344, height: 732)
        case .landscape: return CGSize(width: 732, height: 344)
        }
    }

    var screenSize: CGSize {
        switch self {
        case .portrait: return CGSize(width: 398, height: 856)
        case .landscape: return CGSize(width: 856, height: 398)
        }
    }
}

enum CompactLayout {
    static let controlsIdealWidth: CGFloat = 310
    static let controlsBaseHeight: CGFloat = 40
    static let windowControlsBayHeight: CGFloat = 40
    static let controlsHorizontalInset: CGFloat = 8
    static let controlsBaySpacing: CGFloat = 8

    static func controlsScale(for width: CGFloat) -> CGFloat {
        min(
            max((width - controlsHorizontalInset) / controlsIdealWidth, 0.1),
            1
        )
    }

    static func controlsBayHeight(for width: CGFloat) -> CGFloat {
        controlsBaseHeight * controlsScale(for: width) + controlsBaySpacing
    }
}

extension PresentationMode {
    var screenDragBarHeight: CGFloat {
        self == .screen ? 16 : 0
    }

    var minimumScale: CGFloat {
        switch self {
        case .device: return 0.62
        case .screen: return 0.52
        }
    }

    func contentSize(for orientation: DeviceOrientation, scale: CGFloat = 1.0) -> CGSize {
        let scale = max(scale, minimumScale)

        switch self {
        case .device:
            let deviceSize = orientation.deviceSize
            return CGSize(
                width: deviceSize.width * scale,
                height: deviceSize.height * scale
                    + CompactLayout.windowControlsBayHeight
                    + CompactLayout.controlsBayHeight(for: deviceSize.width * scale)
            )
        case .screen:
            let screenSize = orientation.screenSize
            let viewingWidth = screenSize.width * scale
            return CGSize(
                width: viewingWidth,
                height: (screenSize.height + screenDragBarHeight) * scale
                    + CompactLayout.windowControlsBayHeight
                    + CompactLayout.controlsBayHeight(for: viewingWidth)
            )
        }
    }
}

final class PocketModel: ObservableObject {
    static let shared = PocketModel()

    @Published var selectedApp: SimulatedApp {
        didSet {
            UserDefaults.standard.set(selectedApp.id, forKey: Self.selectedAppKey)
        }
    }

    @Published var presentationMode: PresentationMode {
        didSet {
            UserDefaults.standard.set(presentationMode.rawValue, forKey: Self.presentationModeKey)
        }
    }

    @Published var orientation: DeviceOrientation {
        didSet {
            UserDefaults.standard.set(orientation.rawValue, forKey: Self.orientationKey)
        }
    }

    @Published var isWebsiteManagerPresented = false
    @Published var alwaysOnTop: Bool {
        didSet {
            UserDefaults.standard.set(alwaysOnTop, forKey: Self.alwaysOnTopKey)
        }
    }

    private var controllers: [SimulatedApp: WebViewController] = [:]
    @Published private(set) var websites: [SimulatedApp]

    private static let selectedAppKey = "Pocket.selectedApp"
    private static let presentationModeKey = "Pocket.presentationMode"
    private static let orientationKey = "Pocket.orientation"
    private static let alwaysOnTopKey = "Pocket.alwaysOnTop"
    private static let websitesKey = "Pocket.websites"

    var enabledApps: [SimulatedApp] {
        websites.filter(\.isEnabled)
    }

    init() {
        let defaults = UserDefaults.standard
        var loadedWebsites = Self.loadWebsites(from: defaults)
        if !loadedWebsites.contains(where: \.isEnabled) {
            loadedWebsites[0].isEnabled = true
        }
        websites = loadedWebsites

        if let rawValue = defaults.string(forKey: Self.selectedAppKey),
           let storedApp = loadedWebsites.first(where: { $0.id == rawValue && $0.isEnabled }) {
            selectedApp = storedApp
        } else {
            selectedApp = loadedWebsites.first(where: \.isEnabled) ?? SimulatedApp.telegram
        }

        if let rawValue = defaults.string(forKey: Self.presentationModeKey),
           let storedMode = PresentationMode(rawValue: rawValue) {
            presentationMode = storedMode
        } else {
            presentationMode = .screen
        }

        if let rawValue = defaults.string(forKey: Self.orientationKey),
           let storedOrientation = DeviceOrientation(rawValue: rawValue) {
            orientation = storedOrientation
        } else {
            orientation = .landscape
        }

        alwaysOnTop = defaults.object(forKey: Self.alwaysOnTopKey) as? Bool ?? true
        _ = controller(for: selectedApp)
    }

    func controller(for app: SimulatedApp) -> WebViewController {
        if let controller = controllers[app] {
            return controller
        }

        let controller = WebViewController(app: app)
        controllers[app] = controller
        controller.setPresentationMode(presentationMode)
        return controller
    }

    func select(_ app: SimulatedApp) {
        guard app.isEnabled else { return }
        selectedApp = app
        _ = controller(for: app)
    }

    func setEnabled(_ enabled: Bool, for app: SimulatedApp) {
        guard let index = websites.firstIndex(where: { $0.id == app.id }) else { return }

        if !enabled && websites[index].isEnabled && enabledApps.count == 1 {
            return
        }

        websites[index].isEnabled = enabled
        persistWebsites()

        if selectedApp.id == app.id, !enabled,
           let fallback = enabledApps.first {
            select(fallback)
        }
    }

    func addWebsite(
        title: String,
        subtitle: String,
        urlString: String,
        symbolName: String
    ) {
        let website = SimulatedApp.custom(
            title: title,
            subtitle: subtitle,
            urlString: urlString,
            symbolName: symbolName
        )
        websites.append(website)
        persistWebsites()
        select(website)
    }

    func updateWebsite(
        _ app: SimulatedApp,
        title: String,
        subtitle: String,
        urlString: String,
        symbolName: String
    ) {
        guard let index = websites.firstIndex(where: { $0.id == app.id }) else { return }

        var updated = websites[index]
        updated.title = title
        updated.subtitle = subtitle
        updated.urlString = urlString
        updated.symbolName = symbolName
        websites[index] = updated
        persistWebsites()

        controllers[app]?.webView.stopLoading()
        controllers.removeValue(forKey: app)

        if selectedApp.id == app.id {
            selectedApp = updated
            _ = controller(for: updated)
        }
    }

    func removeWebsite(_ app: SimulatedApp) {
        guard !app.isBuiltIn,
              let index = websites.firstIndex(where: { $0.id == app.id }) else { return }

        websites.remove(at: index)
        controllers[app]?.webView.stopLoading()
        controllers.removeValue(forKey: app)
        persistWebsites()

        if selectedApp.id == app.id,
           let fallback = enabledApps.first {
            select(fallback)
        }
    }

    private static func loadWebsites(from defaults: UserDefaults) -> [SimulatedApp] {
        guard let data = defaults.data(forKey: websitesKey),
              let websites = try? JSONDecoder().decode([SimulatedApp].self, from: data),
              !websites.isEmpty else {
            return SimulatedApp.allCases
        }

        return websites
    }

    private func persistWebsites() {
        guard let data = try? JSONEncoder().encode(websites) else { return }
        UserDefaults.standard.set(data, forKey: Self.websitesKey)
    }
}
