import SwiftUI

struct SimulatedApp: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var subtitle: String
    var urlString: String
    var symbolName: String
    var tintHex: String
    let dataStoreKey: String
    /// A site-specific user agent. Nil means the web view sends the current Safari user agent.
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
    static let windowControlsBayHeight: CGFloat = 40
    static let controlsStripHeight: CGFloat = windowControlsBayHeight * 1.2
    static let paneGap: CGFloat = 0
    static let screenBarHeight: CGFloat = windowControlsBayHeight
    static let slotCount = 4
    static let topRevealHeight: CGFloat = 32
    static let bottomRevealHeight: CGFloat = 24
    static let revealDelay: TimeInterval = 0.25
    static let hideDelay: TimeInterval = 0.6
    static let focusLineHeight: CGFloat = 2
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

    func contentSize(
        for orientation: DeviceOrientation,
        screenCount: Int = 1,
        scale: CGFloat = 1.0
    ) -> CGSize {
        let scale = max(scale, minimumScale)
        let resolvedCount = max(1, min(screenCount, CompactLayout.slotCount))
        let columns = CGFloat(resolvedCount <= 2 ? 1 : 2)
        let rows = CGFloat(resolvedCount == 1 ? 1 : 2)
        let gapX = columns > 1 ? CompactLayout.paneGap * scale : 0
        let gapY = rows > 1 ? CompactLayout.paneGap * scale : 0

        switch self {
        case .device:
            let deviceSize = orientation.deviceSize
            return CGSize(
                width: deviceSize.width * scale * columns + gapX,
                height: deviceSize.height * scale * rows + gapY
            )
        case .screen:
            let screenSize = orientation.screenSize
            return CGSize(
                width: screenSize.width * scale * columns + gapX,
                height: screenSize.height * scale * rows + gapY
            )
        }
    }
}

final class ScreenSlot: ObservableObject, Identifiable {
    let index: Int
    @Published var app: SimulatedApp
    @Published var controller: WebViewController

    var id: Int { index }

    init(index: Int, app: SimulatedApp, controller: WebViewController) {
        self.index = index
        self.app = app
        self.controller = controller
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
    @Published var isBrowserImportPresented = false
    @Published var alwaysOnTop: Bool {
        didSet {
            UserDefaults.standard.set(alwaysOnTop, forKey: Self.alwaysOnTopKey)
        }
    }

    @Published var screenLayoutCount: Int {
        didSet {
            UserDefaults.standard.set(screenLayoutCount, forKey: Self.screenLayoutCountKey)
            if focusedSlotIndex >= screenLayoutCount {
                focusedSlotIndex = max(screenLayoutCount - 1, 0)
            }
        }
    }

    @Published var focusedSlotIndex = 0
    @Published private(set) var slots: [ScreenSlot] = []
    @Published private(set) var websites: [SimulatedApp]

    private var sessionControllers: [String: WebViewController] = [:]
    private var slotURLs: [Int: String] = [:]

    private static let selectedAppKey = "Pocket.selectedApp"
    private static let presentationModeKey = "Pocket.presentationMode"
    private static let orientationKey = "Pocket.orientation"
    private static let alwaysOnTopKey = "Pocket.alwaysOnTop"
    private static let screenLayoutCountKey = "Pocket.screenLayoutCount"
    private static let websitesKey = "Pocket.websites"
    private static let slotsKey = "Pocket.screenSlots"

    var visibleSlots: [ScreenSlot] {
        Array(slots.prefix(max(1, min(screenLayoutCount, slots.count))))
    }

    var openAppIDs: Set<String> {
        Set(visibleSlots.map(\.app.id))
    }

    var activeSlot: ScreenSlot? {
        visibleSlots.first { $0.index == focusedSlotIndex } ?? visibleSlots.first
    }

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

        let storedLayoutCount = defaults.integer(forKey: Self.screenLayoutCountKey)
        screenLayoutCount = (1...CompactLayout.slotCount).contains(storedLayoutCount) ? storedLayoutCount : 1

        let records = Self.loadSlotRecords(from: defaults)
        slots = (0..<CompactLayout.slotCount).map { index in
            let record = records.indices.contains(index) ? records[index] : nil
            let app = loadedWebsites.first { $0.id == record?.appID && $0.isEnabled } ?? selectedApp
            if let urlString = record?.urlString {
                slotURLs[index] = urlString
            }
            let controller = makeSessionController(for: app, slot: index, urlString: record?.urlString)
            return ScreenSlot(index: index, app: app, controller: controller)
        }
        for slot in slots {
            bind(slot)
        }
        if let first = slots.first {
            selectedApp = first.app
        }
    }

    func applyPresentationMode() {
        for controller in sessionControllers.values {
            controller.setPresentationMode(presentationMode)
        }
    }

    func reloadSessions(forAppIDs appIDs: Set<String>) {
        guard !appIDs.isEmpty else { return }
        for controller in sessionControllers.values where appIDs.contains(controller.app.id) {
            controller.reloadPage()
        }
    }

    func select(_ app: SimulatedApp) {
        guard let slot = activeSlot else { return }
        select(app, in: slot)
    }

    func select(_ app: SimulatedApp, in slot: ScreenSlot) {
        guard app.isEnabled, slots.indices.contains(slot.index) else { return }
        focusedSlotIndex = slot.index
        guard slot.app.id != app.id else {
            selectedApp = app
            return
        }

        let controller = sessionControllers[sessionKey(slot: slot.index, appID: app.id)]
            ?? makeSessionController(for: app, slot: slot.index, urlString: nil)
        slot.app = app
        slot.controller = controller
        bind(slot)
        selectedApp = app
        slotURLs[slot.index] = controller.webView.url?.absoluteString
        persistSlots()
    }

    func setEnabled(_ enabled: Bool, for app: SimulatedApp) {
        guard let index = websites.firstIndex(where: { $0.id == app.id }) else { return }

        if !enabled && websites[index].isEnabled && enabledApps.count == 1 {
            return
        }

        websites[index].isEnabled = enabled
        persistWebsites()

        guard !enabled, let fallback = enabledApps.first else { return }
        for slot in slots where slot.app.id == app.id {
            select(fallback, in: slot)
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

        discardSessions(forAppID: app.id)

        for slot in slots where slot.app.id == app.id {
            slot.app = updated
            slot.controller = makeSessionController(for: updated, slot: slot.index, urlString: updated.urlString)
            bind(slot)
        }
        if selectedApp.id == app.id {
            selectedApp = updated
        }
        persistSlots()
    }

    func removeWebsite(_ app: SimulatedApp) {
        guard websites.count > 1,
              let index = websites.firstIndex(where: { $0.id == app.id }) else { return }

        websites.remove(at: index)
        discardSessions(forAppID: app.id)

        if enabledApps.isEmpty, websites.indices.contains(0) {
            websites[0].isEnabled = true
        }
        persistWebsites()

        guard let fallback = enabledApps.first ?? websites.first else { return }
        for slot in slots where slot.app.id == app.id {
            select(fallback, in: slot)
        }
        if selectedApp.id == app.id {
            selectedApp = fallback
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

    private func sessionKey(slot: Int, appID: String) -> String {
        "\(slot)|\(appID)"
    }

    private func makeSessionController(
        for app: SimulatedApp,
        slot: Int,
        urlString: String?
    ) -> WebViewController {
        let initialURL = urlString.flatMap(URL.init(string:))
        let controller = WebViewController(app: app, initialURL: initialURL)
        controller.setPresentationMode(presentationMode)
        sessionControllers[sessionKey(slot: slot, appID: app.id)] = controller
        return controller
    }

    private func bind(_ slot: ScreenSlot) {
        slot.controller.onLocationChange = { [weak self, weak slot] in
            guard let self, let slot else { return }
            self.noteLocation(of: slot)
        }
    }

    private func noteLocation(of slot: ScreenSlot) {
        guard let url = slot.controller.webView.url?.absoluteString,
              !url.isEmpty,
              url != "about:blank" else { return }
        guard slotURLs[slot.index] != url else { return }
        slotURLs[slot.index] = url
        persistSlots()
    }

    private func persistSlots() {
        let records = slots.map { slot in
            SlotRecord(appID: slot.app.id, urlString: slotURLs[slot.index])
        }
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.slotsKey)
    }

    private func discardSessions(forAppID appID: String) {
        let suffix = "|\(appID)"
        for key in sessionControllers.keys where key.hasSuffix(suffix) {
            sessionControllers[key]?.webView.stopLoading()
            sessionControllers.removeValue(forKey: key)
        }
    }

    private static func loadSlotRecords(from defaults: UserDefaults) -> [SlotRecord] {
        guard let data = defaults.data(forKey: slotsKey),
              let records = try? JSONDecoder().decode([SlotRecord].self, from: data) else {
            return []
        }
        return records
    }
}

private struct SlotRecord: Codable {
    var appID: String
    var urlString: String?
}
