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
    static let screenBarHeight: CGFloat = windowControlsBayHeight
    static let addStripThickness: CGFloat = 22
    static let slotCount = 4
    static let topRevealHeight: CGFloat = 32
    static let bottomRevealHeight: CGFloat = 24
    static let revealDelay: TimeInterval = 0.25
    static let hideDelay: TimeInterval = 0.6
    static let focusBorderWidth: CGFloat = 1.7
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
        footprint: LayoutFootprint = .single,
        scale: CGFloat = 1.0
    ) -> CGSize {
        let scale = max(scale, minimumScale)
        let width = max(footprint.width, 1)
        let height = max(footprint.height, 1)

        switch self {
        case .device:
            let deviceSize = orientation.deviceSize
            return CGSize(
                width: deviceSize.width * scale * width,
                height: deviceSize.height * scale * height
            )
        case .screen:
            let screenSize = orientation.screenSize
            return CGSize(
                width: screenSize.width * scale * width,
                height: screenSize.height * scale * height
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

    @Published var settingsSection: PocketSettingsSection = .websites
    /// Settings stays on the Pocket window until it is closed.
    @Published var isSettingsPresented = false
    @Published var isBrowserImportPresented = false
    @Published var isSiteMenuPresented = false
    /// The next choice in the site menu fills the empty cell instead of replacing the focused screen.
    @Published var isChoosingSiteForEmptyCell = false
    @Published var isScreenRemovalPresented = false
    @Published var alwaysOnTop: Bool {
        didSet {
            UserDefaults.standard.set(alwaysOnTop, forKey: Self.alwaysOnTopKey)
        }
    }

    @Published private(set) var paneLayout: PaneLayout
    /// A seam drag must not shrink the window when the layout loses a row or column.
    var keepsWindowSizeForLayoutChange = false

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
    private static let paneLayoutKey = "Pocket.paneLayout"
    private static let websitesKey = "Pocket.websites"
    private static let slotsKey = "Pocket.screenSlots"
    private static let layoutSnapshotsKey = "Pocket.layoutStages"
    private static let layoutStageKey = "Pocket.layoutStage"
    private static let rememberedGridKey = "Pocket.rememberedGrid"
    private static let threeScreenKey = "Pocket.threeScreenLayout"

    private var layoutSnapshots: [Int: LayoutSnapshot] = [:]
    private var rememberedGrid = RememberedGrid()
    private var threeScreen: LayoutSnapshot?
    private var layoutStage = 1
    private var isRestoringLayout = false

    var layoutFootprint: LayoutFootprint { paneLayout.footprint }

    var visibleSlots: [ScreenSlot] {
        let ids = Set(paneLayout.leafIDs)
        return slots.filter { ids.contains($0.index) }
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

        if let data = defaults.data(forKey: Self.paneLayoutKey),
           let stored = try? JSONDecoder().decode(PaneLayout.self, from: data) {
            paneLayout = stored.sanitized()
        } else {
            let storedLayoutCount = defaults.integer(forKey: Self.screenLayoutCountKey)
            paneLayout = PaneLayout.migrated(fromScreenCount: storedLayoutCount).sanitized()
        }

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

        if let data = defaults.data(forKey: Self.layoutSnapshotsKey),
           let stored = try? JSONDecoder().decode([Int: LayoutSnapshot].self, from: data) {
            layoutSnapshots = stored
        }
        if let storedStage = defaults.object(forKey: Self.layoutStageKey) as? Int,
           (1...PaneLayout.maxLeaves).contains(storedStage) {
            layoutStage = storedStage
        } else {
            let span = paneLayout.root.gridSpan
            layoutStage = span.rows > 1 && span.columns > 1 ? 4 : min(max(paneLayout.leafCount, 1), 2)
        }
        if let data = defaults.data(forKey: Self.rememberedGridKey),
           let stored = try? JSONDecoder().decode(RememberedGrid.self, from: data) {
            rememberedGrid = stored
        } else {
            rememberedGrid = migratedGrid()
            saveGrid()
        }
        if let data = defaults.data(forKey: Self.threeScreenKey),
           let stored = try? JSONDecoder().decode(LayoutSnapshot.self, from: data) {
            threeScreen = stored
        }
        if paneLayout.spansFullBand {
            threeScreen = LayoutSnapshot(
                layout: paneLayout,
                slots: slots.map { SlotRecord(appID: $0.app.id, urlString: slotURLs[$0.index]) }
            )
            saveThreeScreen()
            layoutStage = 3
            defaults.set(layoutStage, forKey: Self.layoutStageKey)
        } else {
            let shown = layoutStage == 3 ? 3 : (layoutStage >= 4 ? 4 : max(layoutStage, 1))
            layoutStage = shown == 3 ? 3 : shown
            defaults.set(layoutStage, forKey: Self.layoutStageKey)
            if shown == 3 {
                presentThreeScreen(animated: false)
            } else {
                presentGrid(shown, animated: false)
            }
        }
    }

    /// One and two screens are the top of the grid. Four Screens is the 2×2,
    /// empty corner included. Three Screens is the last layout where one
    /// screen spans a full row, such as after it is dragged across a gap.
    func showScreenCount(_ count: Int) {
        guard (1...PaneLayout.maxLeaves).contains(count) else { return }
        if count == 3 {
            presentThreeScreen(animated: true)
            return
        }
        let shown = count
        if gridIsShowing(shown) {
            layoutStage = shown
            UserDefaults.standard.set(layoutStage, forKey: Self.layoutStageKey)
            return
        }
        keepsWindowSizeForLayoutChange = false
        layoutStage = shown
        UserDefaults.standard.set(layoutStage, forKey: Self.layoutStageKey)
        presentGrid(shown, animated: true)
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

    func split(_ slot: ScreenSlot, at edge: PaneEdge) {
        switch edge {
        case .bottom, .top:
            showScreenCount(4)
        case .leading, .trailing:
            showScreenCount(paneLayout.root.gridSpan.rows > 1 ? 4 : 2)
        }
    }

    func chooseSiteForEmptyCell() {
        isChoosingSiteForEmptyCell = true
        isSiteMenuPresented = true
    }

    func fillEmpty(with app: SimulatedApp) {
        guard app.isEnabled, let slot = firstEmptyCornerSlot() else { return }
        isChoosingSiteForEmptyCell = false
        store(appID: app.id, urlString: app.urlString, in: slot)
        focusedSlotIndex = slot
        keepsWindowSizeForLayoutChange = false
        presentGrid(4, animated: true)
        selectedApp = app
    }

    func fillGap() {
        chooseSiteForEmptyCell()
    }

    func closePane(_ index: Int) {
        guard paneLayout.leafCount > 1, paneLayout.root.contains(index) else { return }
        let span = paneLayout.root.gridSpan
        if paneLayout.spansFullBand {
            guard let next = paneLayout.root.removing(index) else { return }
            let collapsed = PaneLayout(root: next)
            keepsWindowSizeForLayoutChange = collapsed.footprint != paneLayout.footprint
            updatePaneLayout(collapsed)
            if !collapsed.spansFullBand {
                let collapsedSpan = collapsed.root.gridSpan
                if collapsedSpan.rows > 1, collapsedSpan.columns > 1 {
                    layoutStage = 4
                } else {
                    layoutStage = min(max(collapsed.leafCount, 1), 2)
                }
                UserDefaults.standard.set(layoutStage, forKey: Self.layoutStageKey)
            }
            return
        }
        if span.rows > 1, span.columns > 1 {
            store(appID: nil, urlString: nil, in: index)
            keepsWindowSizeForLayoutChange = false
            presentGrid(4, animated: true)
            return
        }
        let survivor = paneLayout.leafIDs.first { $0 != index } ?? 0
        keepsWindowSizeForLayoutChange = true
        layoutStage = 1
        UserDefaults.standard.set(layoutStage, forKey: Self.layoutStageKey)
        isRestoringLayout = true
        withAnimation(PocketMotion.fade(duration: 0.18)) {
            paneLayout = PaneLayout(root: .leaf(survivor))
            focusedSlotIndex = survivor
        }
        if let data = try? JSONEncoder().encode(paneLayout) {
            UserDefaults.standard.set(data, forKey: Self.paneLayoutKey)
        }
        isRestoringLayout = false
        if let slot = slots.first(where: { $0.index == focusedSlotIndex }) {
            selectedApp = slot.app
        }
    }

    func updatePaneLayout(_ layout: PaneLayout) {
        let next = layout.sanitized()
        guard next != paneLayout else { return }
        let footprintChanged = next.footprint != paneLayout.footprint
        keepsWindowSizeForLayoutChange = footprintChanged
        paneLayout = next
        if !paneLayout.leafIDs.contains(focusedSlotIndex) {
            focusedSlotIndex = paneLayout.leafIDs.first ?? 0
        }
        if paneLayout.spansFullBand {
            layoutStage = 3
            UserDefaults.standard.set(layoutStage, forKey: Self.layoutStageKey)
            if let ratio = paneLayout.root.columnSplitRatio() {
                rememberedGrid.columnRatio = ratio
            }
            if let ratio = paneLayout.root.rowSplitRatio() {
                rememberedGrid.rowRatio = ratio
            }
            saveGrid()
            saveCurrentThreeScreen()
        } else {
            if let ratio = paneLayout.root.columnSplitRatio() {
                rememberedGrid.columnRatio = ratio
            }
            if paneLayout.root.gridSpan.rows > 1, let ratio = paneLayout.root.rowSplitRatio() {
                rememberedGrid.rowRatio = ratio
            }
            absorbVisibleLayout(overwrite: true)
            saveGrid()
            if paneLayout.root.gridSpan.rows > 1, paneLayout.root.gridSpan.columns > 1 {
                layoutStage = 4
                UserDefaults.standard.set(layoutStage, forKey: Self.layoutStageKey)
            }
        }
        if let data = try? JSONEncoder().encode(paneLayout) {
            UserDefaults.standard.set(data, forKey: Self.paneLayoutKey)
        }
        if !footprintChanged {
            keepsWindowSizeForLayoutChange = false
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
        rememberSite(in: slot)
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
        rememberSite(in: slot)
    }

    private func randomApps(count: Int, excluding appIDs: Set<String>) -> [SimulatedApp] {
        guard count > 0 else { return [] }
        let unused = enabledApps.filter { !appIDs.contains($0.id) }
        let pool = unused.isEmpty ? enabledApps : unused
        guard !pool.isEmpty else { return [] }
        var result: [SimulatedApp] = []
        while result.count < count {
            result.append(contentsOf: pool.shuffled())
        }
        return Array(result.prefix(count))
    }

    private func place(_ app: SimulatedApp, urlString: String?, in slot: ScreenSlot) {
        guard app.isEnabled, slots.indices.contains(slot.index) else { return }
        let existing = sessionControllers[sessionKey(slot: slot.index, appID: app.id)]
        let controller = existing ?? makeSessionController(for: app, slot: slot.index, urlString: urlString)
        slot.app = app
        slot.controller = controller
        bind(slot)
        if let urlString, let url = URL(string: urlString),
           controller.webView.url?.absoluteString != urlString {
            controller.load(url)
        }
        slotURLs[slot.index] = urlString ?? controller.webView.url?.absoluteString ?? app.urlString
        persistSlots()
    }

    private func migratedGrid() -> RememberedGrid {
        var grid = RememberedGrid()
        // The three-screen shortcut kept the layout the user still recognizes.
        // The four-screen copy can be the add button's rearranged grid.
        if let snapshot = layoutSnapshots[3] {
            absorb(snapshot, into: &grid, overwrite: true)
        }
        if let snapshot = layoutSnapshots[4] {
            absorb(snapshot, into: &grid, overwrite: false)
        }
        if let snapshot = layoutSnapshots[2] {
            absorb(snapshot, into: &grid, overwrite: false)
        }
        if let snapshot = layoutSnapshots[1] {
            absorb(snapshot, into: &grid, overwrite: false)
        }
        return grid
    }

    private func absorb(_ snapshot: LayoutSnapshot, into grid: inout RememberedGrid, overwrite: Bool) {
        let layout = snapshot.layout.sanitized()
        let placed = layout.placement()
        let isGrid = layout.root.gridSpan.rows > 1 && layout.root.gridSpan.columns > 1
        if let ratio = layout.root.columnSplitRatio() {
            grid.columnRatio = ratio
        }
        if isGrid, let ratio = layout.root.rowSplitRatio() {
            grid.rowRatio = ratio
        }
        func taken(_ id: Int?) -> RememberedCorner {
            if let id, snapshot.slots.indices.contains(id) {
                return RememberedCorner(
                    appID: snapshot.slots[id].appID,
                    urlString: snapshot.slots[id].urlString,
                    isSet: true
                )
            }
            return RememberedCorner(appID: nil, urlString: nil, isSet: true)
        }
        func write(_ corner: RememberedCorner, to keyPath: WritableKeyPath<RememberedGrid, RememberedCorner?>) {
            if overwrite || grid[keyPath: keyPath]?.isSet != true {
                grid[keyPath: keyPath] = corner
            }
        }
        if placed.topLeading != nil || isGrid {
            write(taken(placed.topLeading), to: \.topLeading)
        }
        if placed.topTrailing != nil || isGrid {
            write(taken(placed.topTrailing), to: \.topTrailing)
        }
        if placed.bottomLeading != nil || isGrid {
            write(taken(placed.bottomLeading), to: \.bottomLeading)
        }
        if placed.bottomTrailing != nil || isGrid {
            write(taken(placed.bottomTrailing), to: \.bottomTrailing)
        }
    }

    private func absorbVisibleLayout(overwrite: Bool) {
        var grid = rememberedGrid
        let slotsNow = slots.enumerated().map { item in
            SlotRecord(appID: item.element.app.id, urlString: slotURLs[item.offset])
        }
        absorb(LayoutSnapshot(layout: paneLayout, slots: slotsNow), into: &grid, overwrite: overwrite)
        rememberedGrid = grid
    }

    private func presentGrid(_ count: Int, animated: Bool) {
        let shown = count >= 3 ? 4 : max(count, 1)
        ensureCorners(for: shown)
        let next = layoutTree(for: shown).sanitized()
        let change = {
            self.paneLayout = next
            if !self.paneLayout.leafIDs.contains(self.focusedSlotIndex) {
                self.focusedSlotIndex = self.paneLayout.leafIDs.first ?? 0
            }
        }
        isRestoringLayout = true
        if animated {
            withAnimation(PocketMotion.fade(duration: 0.18)) { change() }
        } else {
            change()
        }
        if let data = try? JSONEncoder().encode(paneLayout) {
            UserDefaults.standard.set(data, forKey: Self.paneLayoutKey)
        }
        installCornerSites()
        isRestoringLayout = false
        if let focused = slots.first(where: { $0.index == focusedSlotIndex }) {
            selectedApp = focused.app
        }
        saveGrid()
    }

    /// Restores the layout where one screen spans a full row or column.
    /// Sites stay in the four corners, so a change on either layout shows up
    /// in both. Four Screens still rebuilds the 2×2, empty corner included.
    private func presentThreeScreen(animated: Bool) {
        let layout = (threeScreen?.layout ?? synthesizedThreeScreen()?.layout)?.sanitized()
        guard let layout, layout.spansFullBand else {
            presentGrid(4, animated: animated)
            return
        }
        if threeScreen == nil {
            threeScreen = LayoutSnapshot(
                layout: layout,
                slots: slots.map { SlotRecord(appID: $0.app.id, urlString: slotURLs[$0.index]) }
            )
            saveThreeScreen()
        }
        layoutStage = 3
        UserDefaults.standard.set(layoutStage, forKey: Self.layoutStageKey)
        if paneLayout == layout { return }
        keepsWindowSizeForLayoutChange = false
        let change = {
            self.paneLayout = layout
            if !self.paneLayout.leafIDs.contains(self.focusedSlotIndex) {
                self.focusedSlotIndex = self.paneLayout.leafIDs.first ?? 0
            }
        }
        isRestoringLayout = true
        if animated {
            withAnimation(PocketMotion.fade(duration: 0.18)) { change() }
        } else {
            change()
        }
        if let data = try? JSONEncoder().encode(paneLayout) {
            UserDefaults.standard.set(data, forKey: Self.paneLayoutKey)
        }
        installCornerSites()
        isRestoringLayout = false
        if let focused = slots.first(where: { $0.index == focusedSlotIndex }) {
            selectedApp = focused.app
        }
    }

    /// The filled cell on the short row grows across the empty neighbor.
    /// Top-left YouTube, top-right WhatsApp, and a full-width bottom YouTube
    /// come from the same corners as the 2×2.
    private func synthesizedThreeScreen() -> LayoutSnapshot? {
        ensureCorners(for: 4)
        let column = min(max(rememberedGrid.columnRatio, 0.05), 0.95)
        let row = min(max(rememberedGrid.rowRatio, 0.05), 0.95)
        func filled(_ corner: RememberedCorner?, slot: Int) -> PaneNode? {
            guard corner?.appID != nil else { return nil }
            return .leaf(slot)
        }
        guard let topLeading = filled(rememberedGrid.topLeading, slot: 0),
              let topTrailing = filled(rememberedGrid.topTrailing, slot: 1) else { return nil }
        let top = PaneNode.split(axis: .vertical, ratio: column, first: topLeading, second: topTrailing)
        let bottomSlot: Int
        if rememberedGrid.bottomLeading?.appID != nil {
            bottomSlot = 2
        } else if rememberedGrid.bottomTrailing?.appID != nil {
            bottomSlot = 3
        } else {
            return nil
        }
        let layout = PaneLayout(
            root: .split(axis: .horizontal, ratio: row, first: top, second: .leaf(bottomSlot))
        )
        var records = slots.map { SlotRecord(appID: $0.app.id, urlString: slotURLs[$0.index]) }
        func write(_ corner: RememberedCorner?, slot: Int) {
            guard records.indices.contains(slot), let appID = corner?.appID else { return }
            records[slot] = SlotRecord(appID: appID, urlString: corner?.urlString)
        }
        write(rememberedGrid.topLeading, slot: 0)
        write(rememberedGrid.topTrailing, slot: 1)
        write(rememberedGrid.bottomLeading, slot: 2)
        write(rememberedGrid.bottomTrailing, slot: 3)
        return LayoutSnapshot(layout: layout, slots: records)
    }

    private func saveCurrentThreeScreen() {
        threeScreen = LayoutSnapshot(
            layout: paneLayout,
            slots: slots.map { SlotRecord(appID: $0.app.id, urlString: slotURLs[$0.index]) }
        )
        saveThreeScreen()
    }

    private func saveThreeScreen() {
        guard let threeScreen, let data = try? JSONEncoder().encode(threeScreen) else { return }
        UserDefaults.standard.set(data, forKey: Self.threeScreenKey)
    }

    private func ensureCorners(for count: Int) {
        if rememberedGrid.topLeading?.isSet != true {
            let app = enabledApps.first { $0.id == selectedApp.id } ?? enabledApps.first
            if let app {
                rememberedGrid.topLeading = RememberedCorner(appID: app.id, urlString: app.urlString, isSet: true)
            }
        }
        if count >= 2, rememberedGrid.topTrailing?.isSet != true {
            let exclude = Set([rememberedGrid.topLeading?.appID].compactMap { $0 })
            if let app = randomApps(count: 1, excluding: exclude).first {
                rememberedGrid.topTrailing = RememberedCorner(appID: app.id, urlString: app.urlString, isSet: true)
            }
        }
        if count >= 3 {
            let bottomsReady = rememberedGrid.bottomLeading?.isSet == true
                || rememberedGrid.bottomTrailing?.isSet == true
            if !bottomsReady {
                let exclude = Set(
                    [rememberedGrid.topLeading?.appID, rememberedGrid.topTrailing?.appID].compactMap { $0 }
                )
                if let app = randomApps(count: 1, excluding: exclude).first {
                    rememberedGrid.bottomLeading = RememberedCorner(appID: app.id, urlString: app.urlString, isSet: true)
                }
                rememberedGrid.bottomTrailing = RememberedCorner(appID: nil, urlString: nil, isSet: true)
            }
        }
    }

    private func layoutTree(for count: Int) -> PaneLayout {
        let column = min(max(rememberedGrid.columnRatio, 0.05), 0.95)
        let row = min(max(rememberedGrid.rowRatio, 0.05), 0.95)
        func node(_ corner: RememberedCorner?, slot: Int) -> PaneNode {
            guard corner?.appID != nil else { return .empty }
            return .leaf(slot)
        }
        switch count {
        case 1:
            let slot = [0, 1, 2, 3].first { corner(for: $0)?.appID != nil } ?? 0
            return PaneLayout(root: .leaf(slot))
        case 2:
            let leading = node(rememberedGrid.topLeading, slot: 0)
            let trailing = node(rememberedGrid.topTrailing, slot: 1)
            if case .empty = leading, case .leaf = trailing {
                return PaneLayout(root: trailing)
            }
            if case .leaf = leading, case .empty = trailing {
                return PaneLayout(root: leading)
            }
            return PaneLayout(root: .split(axis: .vertical, ratio: column, first: leading, second: trailing))
        default:
            let top = PaneNode.split(
                axis: .vertical,
                ratio: column,
                first: node(rememberedGrid.topLeading, slot: 0),
                second: node(rememberedGrid.topTrailing, slot: 1)
            )
            let bottom = PaneNode.split(
                axis: .vertical,
                ratio: column,
                first: node(rememberedGrid.bottomLeading, slot: 2),
                second: node(rememberedGrid.bottomTrailing, slot: 3)
            )
            return PaneLayout(root: .split(axis: .horizontal, ratio: row, first: top, second: bottom))
        }
    }

    private func installCornerSites() {
        for slot in paneLayout.leafIDs {
            guard let corner = corner(for: slot), let appID = corner.appID else { continue }
            guard let app = enabledApps.first(where: { $0.id == appID }) ?? websites.first(where: { $0.id == appID }) else {
                continue
            }
            guard slots.indices.contains(slot) else { continue }
            let url = corner.urlString ?? slotURLs[slot]
            place(app, urlString: url, in: slots[slot])
        }
    }

    private func gridIsShowing(_ count: Int) -> Bool {
        let placed = paneLayout.placement()
        func matches(_ id: Int?, slot: Int) -> Bool {
            let filled = corner(for: slot)?.appID != nil
            if filled {
                return id == slot && slots.indices.contains(slot) && slots[slot].app.id == corner(for: slot)?.appID
            }
            return id == nil
        }
        switch count {
        case 1:
            let slot = [0, 1, 2, 3].first { corner(for: $0)?.appID != nil } ?? 0
            return paneLayout.leafCount == 1 && paneLayout.leafIDs.first == slot
                && matches(placed.topLeading ?? placed.bottomLeading, slot: slot)
        case 2:
            return matches(placed.topLeading, slot: 0) && matches(placed.topTrailing, slot: 1)
                && placed.bottomLeading == nil && placed.bottomTrailing == nil
        default:
            let span = paneLayout.root.gridSpan
            guard span.rows > 1, span.columns > 1, !paneLayout.spansFullBand else { return false }
            return matches(placed.topLeading, slot: 0) && matches(placed.topTrailing, slot: 1)
                && matches(placed.bottomLeading, slot: 2) && matches(placed.bottomTrailing, slot: 3)
        }
    }

    private func corner(for slot: Int) -> RememberedCorner? {
        switch slot {
        case 0: return rememberedGrid.topLeading
        case 1: return rememberedGrid.topTrailing
        case 2: return rememberedGrid.bottomLeading
        case 3: return rememberedGrid.bottomTrailing
        default: return nil
        }
    }

    private func firstEmptyCornerSlot() -> Int? {
        let placed = paneLayout.placement()
        let span = paneLayout.root.gridSpan
        guard span.rows > 1, span.columns > 1 else { return nil }
        if placed.topLeading == nil { return 0 }
        if placed.topTrailing == nil { return 1 }
        if placed.bottomLeading == nil { return 2 }
        if placed.bottomTrailing == nil { return 3 }
        return nil
    }

    private func store(appID: String?, urlString: String?, in slot: Int) {
        let corner = RememberedCorner(appID: appID, urlString: urlString, isSet: true)
        switch slot {
        case 0: rememberedGrid.topLeading = corner
        case 1: rememberedGrid.topTrailing = corner
        case 2: rememberedGrid.bottomLeading = corner
        case 3: rememberedGrid.bottomTrailing = corner
        default: return
        }
        saveGrid()
    }

    private func rememberSite(in slot: ScreenSlot) {
        guard !isRestoringLayout else { return }
        guard (0..<4).contains(slot.index) else { return }
        store(appID: slot.app.id, urlString: slotURLs[slot.index] ?? slot.app.urlString, in: slot.index)
        if paneLayout.spansFullBand {
            saveCurrentThreeScreen()
        }
    }

    private func saveGrid() {
        guard let data = try? JSONEncoder().encode(rememberedGrid) else { return }
        UserDefaults.standard.set(data, forKey: Self.rememberedGridKey)
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

private struct RememberedCorner: Codable, Equatable {
    var appID: String?
    var urlString: String?
    var isSet: Bool = false
}

private struct RememberedGrid: Codable, Equatable {
    var topLeading: RememberedCorner?
    var topTrailing: RememberedCorner?
    var bottomLeading: RememberedCorner?
    var bottomTrailing: RememberedCorner?
    var columnRatio: Double = 0.5
    var rowRatio: Double = 0.5
}

private struct LayoutSnapshot: Codable {
    var layout: PaneLayout
    var slots: [SlotRecord]
}

private struct SlotRecord: Codable {
    var appID: String
    var urlString: String?
}
