import SwiftUI
import WebKit

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
    static let controlsIdealWidth: CGFloat = 350
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
                height: screenSize.height * scale
                    + CompactLayout.windowControlsBayHeight
                    + CompactLayout.controlsBayHeight(for: viewingWidth)
            )
        }
    }
}

// A screen owns its web views even while its layout is hidden. Sites share their
// cookie store across screens, but never share a WKWebView or navigation history.
final class PocketScreen: ObservableObject, Identifiable {
    let id: Int
    @Published private(set) var selectedApp: SimulatedApp
    private var controllers: [String: WebViewController] = [:]
    private let defaults: UserDefaults
    private let loadPages: Bool

    init(id: Int, app: SimulatedApp, defaults: UserDefaults, loadPages: Bool) {
        self.id = id
        self.selectedApp = app
        self.defaults = defaults
        self.loadPages = loadPages
        defaults.set(app.id, forKey: "Pocket.screen.\(id).app")
    }

    func select(_ app: SimulatedApp) {
        selectedApp = app
        defaults.set(app.id, forKey: "Pocket.screen.\(id).app")
    }

    func controller(for app: SimulatedApp) -> WebViewController {
        if let controller = controllers[app.id] { return controller }
        let controller = WebViewController(app: app, loadImmediately: false)
        let key = "Pocket.screen.\(id).url.\(app.id)"
        let savedURL = defaults.string(forKey: key).flatMap(URL.init(string:))
        controller.onURLChanged = { [weak self] url in
            guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
            self?.defaults.set(url.absoluteString, forKey: key)
        }
        controllers[app.id] = controller
        if loadPages { controller.load(url: WebViewController.restoredURL(savedURL, for: app)) }
        return controller
    }

    func invalidate(_ app: SimulatedApp) {
        controllers.removeValue(forKey: app.id)?.webView.stopLoading()
        defaults.removeObject(forKey: "Pocket.screen.\(id).url.\(app.id)")
    }
}

final class PocketModel: ObservableObject {
    static let shared = PocketModel()

    @Published var selectedApp: SimulatedApp {
        didSet {
            defaults.set(selectedApp.id, forKey: Self.selectedAppKey)
        }
    }

    @Published var presentationMode: PresentationMode {
        didSet {
            defaults.set(presentationMode.rawValue, forKey: Self.presentationModeKey)
        }
    }

    @Published var orientation: DeviceOrientation {
        didSet {
            defaults.set(orientation.rawValue, forKey: Self.orientationKey)
        }
    }

    @Published var isWebsiteManagerPresented = false
    @Published var alwaysOnTop: Bool {
        didSet {
            defaults.set(alwaysOnTop, forKey: Self.alwaysOnTopKey)
        }
    }

    private let defaults: UserDefaults
    private(set) var screens: [PocketScreen] = []
    @Published private(set) var focusedScreenID = 0
    @Published var favoriteScreenLayouts: [ScreenLayout] {
        didSet {
            let selected = Set(favoriteScreenLayouts)
            let normalized = ScreenLayout.allCases.filter { selected.contains($0) }
            if normalized != favoriteScreenLayouts { favoriteScreenLayouts = normalized }
            defaults.set(normalized.map(\.rawValue), forKey: Self.favoriteLayoutsKey)
        }
    }
    @Published var screenLayout: ScreenLayout = .single {
        didSet {
            defaults.set(screenLayout.rawValue, forKey: "Pocket.screenLayout")
            if !screenLayout.screenIDs.contains(focusedScreenID) { focusScreen(0) }
        }
    }
    @Published private(set) var websites: [SimulatedApp]

    private static let selectedAppKey = "Pocket.selectedApp"
    private static let presentationModeKey = "Pocket.presentationMode"
    private static let orientationKey = "Pocket.orientation"
    private static let alwaysOnTopKey = "Pocket.alwaysOnTop"
    private static let websitesKey = "Pocket.websites"
    private static let favoriteLayoutsKey = "Pocket.screenLayout.favorites"

    var enabledApps: [SimulatedApp] {
        websites.filter(\.isEnabled)
    }

    init(defaults: UserDefaults = .standard, loadPages: Bool = true) {
        self.defaults = defaults
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
        let savedLayouts = (defaults.stringArray(forKey: Self.favoriteLayoutsKey) ?? [])
            .compactMap(ScreenLayout.init(rawValue:))
        let savedLayoutSet = Set(savedLayouts)
        favoriteScreenLayouts = savedLayoutSet.isEmpty
            ? ScreenLayout.defaultQuickLayouts
            : ScreenLayout.allCases.filter { savedLayoutSet.contains($0) }
        screens = (0..<16).map { id in
            let fallback = id == 0 ? selectedApp : enabledApps[id % enabledApps.count]
            let storedID = defaults.string(forKey: "Pocket.screen.\(id).app")
            let app = enabledApps.first(where: { $0.id == storedID }) ?? fallback
            return PocketScreen(id: id, app: app, defaults: defaults, loadPages: loadPages)
        }
        selectedApp = screens[0].selectedApp
        screenLayout = defaults.string(forKey: "Pocket.screenLayout").flatMap(ScreenLayout.init(rawValue:)) ?? .single
        _ = controller(for: selectedApp)
    }

    func toggleFavoriteScreenLayout(_ layout: ScreenLayout) {
        if favoriteScreenLayouts.contains(layout) {
            guard favoriteScreenLayouts.count > 1 else { return }
            favoriteScreenLayouts.removeAll { $0 == layout }
        } else {
            favoriteScreenLayouts.append(layout)
        }
    }

    @MainActor
    func installBrowserCookies(_ cookies: [HTTPCookie]) async -> (cookieCount: Int, websiteNames: [String]) {
        var importedCount = 0
        var importedWebsiteNames: [String] = []

        for website in websites {
            guard let host = website.url.host?.lowercased(),
                  let identifier = UUID(uuidString: website.dataStoreKey) else { continue }
            let matchingCookies = cookies.filter { cookie in
                let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                let relatedDomains: [String]
                switch website.id {
                case "youtube": relatedDomains = ["google.com"]
                case "x": relatedDomains = ["twitter.com"]
                default: relatedDomains = []
                }
                let allowedDomains = [host] + relatedDomains
                return allowedDomains.contains { allowedHost in
                    allowedHost == domain || allowedHost.hasSuffix("." + domain)
                }
            }
            guard !matchingCookies.isEmpty else { continue }

            let cookieStore = WKWebsiteDataStore(forIdentifier: identifier).httpCookieStore
            for cookie in matchingCookies {
                await withCheckedContinuation { continuation in
                    cookieStore.setCookie(cookie) {
                        continuation.resume()
                    }
                }
            }
            importedCount += matchingCookies.count
            importedWebsiteNames.append(website.title)
        }

        return (importedCount, importedWebsiteNames)
    }

    func controller(for app: SimulatedApp) -> WebViewController {
        screens[focusedScreenID].controller(for: app)
    }

    func focusScreen(_ id: Int) {
        guard screens.indices.contains(id), focusedScreenID != id else { return }
        focusedScreenID = id
        selectedApp = screens[id].selectedApp
    }

    func select(_ app: SimulatedApp, in screenID: Int? = nil) {
        guard app.isEnabled else { return }
        let id = screenID ?? focusedScreenID
        guard screens.indices.contains(id) else { return }
        focusScreen(id)
        screens[id].select(app)
        selectedApp = app
        _ = screens[id].controller(for: app)
    }

    private func replaceSelection(of app: SimulatedApp, with replacement: SimulatedApp) {
        for screen in screens where screen.selectedApp.id == app.id {
            screen.select(replacement)
        }
        selectedApp = screens[focusedScreenID].selectedApp
    }

    func setEnabled(_ enabled: Bool, for app: SimulatedApp) {
        guard let index = websites.firstIndex(where: { $0.id == app.id }) else { return }

        if !enabled && websites[index].isEnabled && enabledApps.count == 1 {
            return
        }

        websites[index].isEnabled = enabled
        persistWebsites()

        if !enabled, let fallback = enabledApps.first {
            replaceSelection(of: app, with: fallback)
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

        screens.forEach { $0.invalidate(app) }
        replaceSelection(of: app, with: updated)
    }

    func removeWebsite(_ app: SimulatedApp) {
        guard !app.isBuiltIn,
              let index = websites.firstIndex(where: { $0.id == app.id }) else { return }

        websites.remove(at: index)
        screens.forEach { $0.invalidate(app) }
        persistWebsites()

        if let fallback = enabledApps.first {
            replaceSelection(of: app, with: fallback)
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
        defaults.set(data, forKey: Self.websitesKey)
    }
}
