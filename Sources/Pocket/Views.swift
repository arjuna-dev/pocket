import AppKit
import SwiftUI
import WebKit

private extension Color {
    static let pocketBackground = Color(red: 0.055, green: 0.063, blue: 0.082)
    static let pocketSidebar = Color(red: 0.075, green: 0.084, blue: 0.108)
    static let pocketSurface = Color(red: 0.095, green: 0.105, blue: 0.133)
    static let pocketSurfaceRaised = Color(red: 0.125, green: 0.137, blue: 0.170)
    static let pocketMuted = Color(red: 0.48, green: 0.50, blue: 0.57)
}

private enum PocketBrand {
    static let icon: NSImage? = {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: iconURL)
    }()
}

struct PocketIcon: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = PocketBrand.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .fill(Color(red: 0.40, green: 0.83, blue: 0.73))

                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: size * 0.46, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct AppRootView: View {
    @ObservedObject var model: WorkspaceModel

    private var selectedController: WebViewController {
        model.controller(for: model.selectedApp)
    }

    var body: some View {
        Group {
            switch model.presentationMode {
            case .device:
                CompactDeviceView(model: model, controller: selectedController)
            case .screen:
                CompactScreenView(model: model, controller: selectedController)
            case .workspace:
                WorkspaceView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background {
            if model.presentationMode == .workspace {
                Color.pocketBackground
            } else {
                Color.clear
            }
        }
        .background(
            WindowBridge { window in
                WindowManager.shared.attach(window: window)
                WindowManager.shared.setAlwaysOnTop(model.alwaysOnTop)
                WindowManager.shared.ensureInitialSize(
                    for: model.presentationMode,
                    orientation: model.orientation
                )
            }
            .frame(width: 1, height: 1)
        )
        .onAppear {
            selectedController.setPresentationMode(model.presentationMode)
            WindowManager.shared.restoreSize(
                for: model.presentationMode,
                orientation: model.orientation,
                animated: false
            )
        }
        .onChange(of: model.presentationMode) { _, newMode in
            selectedController.setPresentationMode(newMode)
            WindowManager.shared.restoreSize(
                for: newMode,
                orientation: model.orientation,
                animated: true
            )
        }
        .onChange(of: model.orientation) { _, newOrientation in
            WindowManager.shared.restoreSize(
                for: model.presentationMode,
                orientation: newOrientation,
                animated: true
            )
        }
        .onChange(of: model.alwaysOnTop) { _, newValue in
            WindowManager.shared.setAlwaysOnTop(newValue)
        }
        .preferredColorScheme(.dark)
    }
}

struct CompactDeviceView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var controller: WebViewController
    @State private var controlsVisible = false

    var body: some View {
        GeometryReader { proxy in
            let deviceSize = model.orientation.deviceSize
            let availableWidth = max(proxy.size.width, 1)
            let controlsScale = CompactControls.scaleToFit(width: availableWidth)
            let controlsBayHeight = CompactControls.bayHeight(for: availableWidth)
            let availableHeight = max(proxy.size.height - controlsBayHeight, 1)
            let scale = max(
                min(availableWidth / deviceSize.width, availableHeight / deviceSize.height),
                0.1
            )

            VStack(spacing: 0) {
                ZStack {
                    DeviceFrame(
                        app: model.selectedApp,
                        controller: controller,
                        orientation: model.orientation
                    )
                    .frame(width: deviceSize.width, height: deviceSize.height)
                    .scaleEffect(scale)
                    .frame(
                        width: deviceSize.width * scale,
                        height: deviceSize.height * scale
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ZStack {
                    if controlsVisible {
                        CompactControls(
                            model: model,
                            controller: controller,
                            scale: controlsScale
                        )
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: controlsBayHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(Color.clear)
        .overlay {
            HoverTrackingView { isHovering in
                guard controlsVisible != isHovering else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    controlsVisible = isHovering
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
        }
    }
}

struct CompactScreenView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var controller: WebViewController
    @State private var controlsVisible = false

    var body: some View {
        GeometryReader { proxy in
            let screenSize = model.orientation.screenSize
            let dragBarBaseHeight = model.presentationMode.screenDragBarHeight
            let baseContentSize = CGSize(
                width: screenSize.width,
                height: screenSize.height + dragBarBaseHeight
            )
            let availableWidth = max(proxy.size.width, 1)
            let controlsScale = CompactControls.scaleToFit(width: availableWidth)
            let controlsBayHeight = CompactControls.bayHeight(for: availableWidth)
            let availableHeight = max(proxy.size.height - controlsBayHeight, 1)
            let scale = max(
                min(
                    availableWidth / baseContentSize.width,
                    availableHeight / baseContentSize.height
                ),
                0.1
            )
            let dragBarHeight = dragBarBaseHeight * scale
            let scaledScreenSize = CGSize(
                width: screenSize.width * scale,
                height: screenSize.height * scale
            )

            VStack(spacing: 0) {
                WindowDragHandle(showsIndicator: controlsVisible)
                    .frame(width: availableWidth, height: dragBarHeight)
                    .frame(maxWidth: .infinity)
                    .help("Drag to move window")

                ZStack {
                    WebContent(controller: controller, cornerRadius: 0)
                        .frame(width: screenSize.width, height: screenSize.height)
                        .scaleEffect(scale)
                        .frame(width: scaledScreenSize.width, height: scaledScreenSize.height)
                }

                ZStack {
                    if controlsVisible {
                        CompactControls(
                            model: model,
                            controller: controller,
                            scale: controlsScale
                        )
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: controlsBayHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(Color.clear)
        .overlay {
            HoverTrackingView { isHovering in
                guard controlsVisible != isHovering else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    controlsVisible = isHovering
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
        }
    }
}

struct CompactControls: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var controller: WebViewController
    let scale: CGFloat

    private static let idealWidth = CompactLayout.controlsIdealWidth

    static func scaleToFit(width: CGFloat) -> CGFloat {
        CompactLayout.controlsScale(for: width)
    }

    static func bayHeight(for width: CGFloat) -> CGFloat {
        CompactLayout.controlsBayHeight(for: width)
    }

    var body: some View {
        HStack(spacing: 8) {
            CompactNavigationButton(
                symbol: "chevron.left",
                help: "Back"
            ) {
                controller.goBack()
            }

            HStack(spacing: 5) {
                Menu {
                    ForEach(model.enabledApps) { app in
                        Button {
                            model.select(app)
                        } label: {
                            Label(app.title, systemImage: app.symbolName)
                        }
                    }
                } label: {
                    ServiceIcon(app: model.selectedApp, size: 28)
                }
                .menuStyle(.borderlessButton)
                .help("Switch app")

                CompactControlButton(symbol: "arrow.clockwise", help: "Reload") {
                    controller.load()
                }

                CompactOrientationSwitcher(selection: $model.orientation)

                CompactAlwaysOnTopButton(model: model)
            }
            .padding(6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.13), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.35), radius: 14, y: 7)

            CompactNavigationButton(
                symbol: "chevron.right",
                help: "Forward"
            ) {
                controller.goForward()
            }
        }
        .frame(width: Self.idealWidth, height: 40)
        .scaleEffect(scale)
        .frame(
            width: Self.idealWidth * scale,
            height: 40 * scale
        )
    }
}

struct CompactControlButton: View {
    let symbol: String
    let help: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(disabled ? Color.white.opacity(0.22) : Color.white.opacity(0.82))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }
}

struct CompactNavigationButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.80))
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct CompactOrientationSwitcher: View {
    @Binding var selection: DeviceOrientation

    var body: some View {
        Button {
            selection = selection == .portrait ? .landscape : .portrait
        } label: {
            Image(systemName: selection.toggleSymbolName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.82))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("Switch to \(selection == .portrait ? "Landscape" : "Portrait")")
        .accessibilityLabel("Orientation")
        .accessibilityValue(selection.title)
    }
}

struct CompactAlwaysOnTopButton: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        Button {
            model.alwaysOnTop.toggle()
        } label: {
            Image(systemName: model.alwaysOnTop ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(model.alwaysOnTop ? Color.white : Color.white.opacity(0.82))
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(model.alwaysOnTop ? Color.white.opacity(0.13) : Color.clear)
                }
        }
        .buttonStyle(.plain)
        .help(model.alwaysOnTop ? "Always on Top: On" : "Always on Top: Off")
        .accessibilityLabel("Always on Top")
        .accessibilityValue(model.alwaysOnTop ? "On" : "Off")
    }
}

struct WorkspaceView: View {
    @ObservedObject var model: WorkspaceModel
    @State private var isWebsiteManagerPresented = false

    private var selectedController: WebViewController {
        model.controller(for: model.selectedApp)
    }

    var body: some View {
        HStack(spacing: 0) {
            if model.sidebarVisible {
                AppSidebar(model: model)
            }

            VStack(spacing: 0) {
                WorkspaceToolbar(
                    model: model,
                    controller: selectedController,
                    isWebsiteManagerPresented: $isWebsiteManagerPresented
                )

                SimulatorStage(
                    app: model.selectedApp,
                    controller: selectedController,
                    mode: .screen
                )
            }
        }
        .background(Color.pocketBackground)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isWebsiteManagerPresented) {
            WebsiteManagerSheet(model: model)
        }
        .onChange(of: model.presentationMode) { _, newMode in
            selectedController.setPresentationMode(newMode)
        }
    }
}

struct AppSidebar: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                PocketIcon(size: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Pocket")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("web app simulator")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.pocketMuted)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 28)

            Text("YOUR APPS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Color.pocketMuted)
                .padding(.horizontal, 19)
                .padding(.bottom, 10)

            ScrollView(.vertical) {
                VStack(spacing: 5) {
                    ForEach(model.enabledApps) { app in
                        SidebarAppRow(
                            app: app,
                            isSelected: model.selectedApp == app
                        ) {
                            model.select(app)
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity, alignment: .top)

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(red: 0.32, green: 0.84, blue: 0.59))
                        .frame(width: 7, height: 7)

                    Text("WebKit runtime")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.76))
                }

                Text("Each service keeps its own cookies and login session.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.pocketMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(14)
            .background(Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .padding(14)
        }
        .frame(width: 246)
        .background(Color.pocketSidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.055))
                .frame(width: 1)
        }
    }
}

private enum WebsiteEditorTarget: Identifiable {
    case new
    case edit(SimulatedApp)

    var id: String {
        switch self {
        case .new:
            return "new"
        case .edit(let website):
            return website.id
        }
    }

    var website: SimulatedApp? {
        if case .edit(let website) = self {
            return website
        }
        return nil
    }
}

struct WebsiteManagerSheet: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var editorTarget: WebsiteEditorTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Websites")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Choose what appears in Pocket's app switcher.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.pocketMuted)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 18)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.websites) { website in
                        WebsiteManagerRow(
                            website: website,
                            isSelected: model.selectedApp.id == website.id,
                            onToggle: { model.setEnabled($0, for: website) },
                            onEdit: { editorTarget = .edit(website) },
                            onRemove: { model.removeWebsite(website) }
                        )
                    }
                }
            }
            .scrollIndicators(.visible)

            HStack(spacing: 12) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.pocketMuted)

                Text("Disabled websites stay saved but disappear from the sidebar and compact switcher.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.pocketMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                Button {
                    editorTarget = .new
                } label: {
                    Label("Add Website", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.78, green: 0.31, blue: 0.20))
            }
            .padding(.top, 18)
        }
        .padding(24)
        .frame(width: 600, height: 570)
        .background(Color.pocketBackground)
        .preferredColorScheme(.dark)
        .sheet(item: $editorTarget) { target in
            WebsiteEditorSheet(model: model, website: target.website)
        }
    }
}

struct WebsiteManagerRow: View {
    let website: SimulatedApp
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    private var locationLabel: String {
        website.url.host ?? website.urlString
    }

    var body: some View {
        HStack(spacing: 12) {
            ServiceIcon(app: website, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(website.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(website.isEnabled ? .white : Color.white.opacity(0.48))

                    if isSelected {
                        Text("OPEN")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(website.tint)
                    }
                }

                Text(locationLabel)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(website.isEnabled ? Color.pocketMuted : Color.pocketMuted.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: Binding(
                get: { website.isEnabled },
                set: onToggle
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .help(website.isEnabled ? "Disable website" : "Enable website")

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Edit website")

            if website.isCustom {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Remove website")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(website.isEnabled ? Color.white.opacity(0.055) : Color.white.opacity(0.025))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(website.isEnabled ? 0.08 : 0.04), lineWidth: 1)
        }
        .opacity(website.isEnabled ? 1 : 0.72)
    }
}

struct WebsiteEditorSheet: View {
    @ObservedObject var model: WorkspaceModel
    let website: SimulatedApp?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var subtitle: String
    @State private var urlString: String
    @State private var symbolName: String
    @State private var validationMessage: String?

    private static let iconOptions = [
        "globe",
        "globe.americas.fill",
        "globe.europe.africa.fill",
        "globe.asia.australia.fill",
        "link",
        "safari",
        "network",
        "rectangle.on.rectangle",
        "macwindow",
        "server.rack",
        "wifi",
        "antenna.radiowaves.left.and.right",
        "cloud.fill",
        "lock.fill",
        "key.fill",
        "shield.fill",
        "gearshape.fill",
        "wrench.and.screwdriver.fill",
        "slider.horizontal.3",
        "message.fill",
        "bubble.left.and.bubble.right.fill",
        "paperplane.fill",
        "phone.fill",
        "video.fill",
        "envelope.fill",
        "megaphone.fill",
        "bell.fill",
        "person.crop.circle.fill",
        "person.2.fill",
        "person.3.fill",
        "radio.fill",
        "mic.fill",
        "video.camera.fill",
        "play.rectangle.fill",
        "play.fill",
        "music.note",
        "music.mic",
        "headphones",
        "film.fill",
        "tv.fill",
        "gamecontroller.fill",
        "camera.fill",
        "photo.fill",
        "doc.text.image.fill",
        "cart.fill",
        "bag.fill",
        "creditcard.fill",
        "banknote.fill",
        "gift.fill",
        "book.fill",
        "newspaper.fill",
        "bookmark.fill",
        "note.text",
        "folder.fill",
        "tray.full.fill",
        "checklist",
        "list.bullet.rectangle.portrait.fill",
        "pencil.and.outline",
        "calendar",
        "clock.fill",
        "map.fill",
        "mappin.and.ellipse",
        "house.fill",
        "building.2.fill",
        "car.fill",
        "airplane",
        "fork.knife",
        "cup.and.saucer.fill",
        "bolt.fill",
        "flame.fill",
        "leaf.fill",
        "sun.max.fill",
        "moon.fill",
        "heart.fill",
        "star.fill",
        "flag.fill",
        "checkmark.seal.fill",
        "briefcase.fill",
        "terminal.fill",
        "chevron.left.forwardslash.chevron.right",
        "cpu.fill",
        "brain.head.profile",
        "chart.bar.fill",
        "chart.pie.fill",
        "face.smiling.fill",
        "hand.thumbsup.fill",
        "quote.bubble.fill",
        "rosette",
        "ellipsis.circle.fill"
    ]

    init(model: WorkspaceModel, website: SimulatedApp?) {
        self.model = model
        self.website = website
        _title = State(initialValue: website?.title ?? "")
        _subtitle = State(initialValue: website?.subtitle ?? "Website")
        _urlString = State(initialValue: website?.urlString ?? "https://")
        _symbolName = State(initialValue: website?.symbolName ?? "globe")
        _validationMessage = State(initialValue: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(website == nil ? "Add Website" : "Edit Website")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Give the site a name, URL, and icon for Pocket.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.pocketMuted)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 11) {
                Text("Name")
                    .formLabelStyle()
                TextField("e.g. Notion", text: $title)
                    .textFieldStyle(.roundedBorder)

                Text("Subtitle")
                    .formLabelStyle()
                TextField("e.g. Notes", text: $subtitle)
                    .textFieldStyle(.roundedBorder)

                Text("Website URL")
                    .formLabelStyle()
                TextField("https://example.com", text: $urlString)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .formLabelStyle()

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 8)], spacing: 8) {
                        ForEach(Self.iconOptions, id: \.self) { icon in
                            Button {
                                symbolName = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(symbolName == icon ? .white : Color.white.opacity(0.68))
                                    .frame(width: 40, height: 34)
                                    .background {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(symbolName == icon ? Color(red: 0.78, green: 0.31, blue: 0.20).opacity(0.75) : Color.white.opacity(0.06))
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(icon)
                        }
                    }
                }
                .frame(maxHeight: 210)
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.orange)
            }

            Spacer(minLength: 0)

            HStack {
                if let website, website.isBuiltIn {
                    Text("Built-in website")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.pocketMuted)
                }

                Spacer()

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.78, green: 0.31, blue: 0.20))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 620)
        .background(Color.pocketBackground)
        .preferredColorScheme(.dark)
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            validationMessage = "Add a name for this website."
            return
        }

        let cleanURL = normalizedURL()
        guard let cleanURL else {
            validationMessage = "Enter a valid http or https website URL."
            return
        }

        let cleanSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let website {
            model.updateWebsite(
                website,
                title: cleanTitle,
                subtitle: cleanSubtitle.isEmpty ? "Website" : cleanSubtitle,
                urlString: cleanURL,
                symbolName: symbolName
            )
        } else {
            model.addWebsite(
                title: cleanTitle,
                subtitle: cleanSubtitle.isEmpty ? "Website" : cleanSubtitle,
                urlString: cleanURL,
                symbolName: symbolName
            )
        }
        dismiss()
    }

    private func normalizedURL() -> String? {
        var value = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if !value.contains("://") {
            value = "https://" + value
        }

        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }

        return url.absoluteString
    }
}

private extension View {
    func formLabelStyle() -> some View {
        font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.72))
    }
}

struct SidebarAppRow: View {
    let app: SimulatedApp
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ServiceIcon(app: app, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : Color.white.opacity(0.79))

                    Text(app.subtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.60) : Color.pocketMuted)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Circle()
                        .fill(app.tint)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.10) : Color.clear)
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(app.title)")
    }
}

struct WorkspaceToolbar: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var controller: WebViewController
    @Binding var isWebsiteManagerPresented: Bool

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 11) {
                ServiceIcon(app: model.selectedApp, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.pageTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(model.selectedApp.tint)
                            .frame(width: 5, height: 5)

                        Text("Live web session")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.pocketMuted)
                    }
                }
            }

            Spacer(minLength: 16)

            HStack(spacing: 3) {
                ToolbarButton(symbol: "chevron.left", help: "Back") {
                    controller.goBack()
                }

                ToolbarButton(symbol: "chevron.right", help: "Forward") {
                    controller.goForward()
                }

                ToolbarButton(symbol: "arrow.clockwise", help: "Reload") {
                    controller.load()
                }
            }

            ModeSwitcher(selection: $model.presentationMode)

            OrientationSwitcher(selection: $model.orientation)

            ToolbarButton(symbol: "slider.horizontal.3", help: "Manage websites") {
                isWebsiteManagerPresented = true
            }

            ToolbarButton(
                symbol: model.sidebarVisible ? "sidebar.left" : "sidebar.left",
                help: model.sidebarVisible ? "Hide sidebar" : "Show sidebar"
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.sidebarVisible.toggle()
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 74)
        .background(Color.pocketSurface.opacity(0.94))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }
}

struct ModeSwitcher: View {
    @Binding var selection: PresentationMode

    var body: some View {
        HStack(spacing: 3) {
            ForEach(PresentationMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection = mode
                    }
                } label: {
                    Label(mode.title, systemImage: mode.symbolName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(selection == mode ? .white : Color.pocketMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == mode ? Color.white.opacity(0.13) : Color.clear)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }
}

struct OrientationSwitcher: View {
    @Binding var selection: DeviceOrientation

    var body: some View {
        Button {
            selection = selection == .portrait ? .landscape : .portrait
        } label: {
            Image(systemName: selection.toggleSymbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 27, height: 28)
        }
        .buttonStyle(.plain)
        .help("Switch to \(selection == .portrait ? "Landscape" : "Portrait")")
        .accessibilityLabel("Orientation")
        .accessibilityValue(selection.title)
        .padding(4)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }
}

struct ToolbarButton: View {
    let symbol: String
    let help: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(disabled ? Color.white.opacity(0.20) : Color.white.opacity(0.72))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(disabled ? 0.01 : 0.045))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }
}

struct SimulatorStage: View {
    let app: SimulatedApp
    @ObservedObject var controller: WebViewController
    let mode: PresentationMode

    var body: some View {
        ZStack {
            if mode == .device {
                DeviceStage(app: app, controller: controller)
            } else {
                ScreenStage(controller: controller)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Color.pocketBackground

                RadialGradient(
                    colors: [app.tint.opacity(mode == .device ? 0.10 : 0.045), Color.clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 560
                )
            }
        }
        .clipped()
    }
}

struct DeviceStage: View {
    let app: SimulatedApp
    @ObservedObject var controller: WebViewController

    var body: some View {
        GeometryReader { proxy in
            let availableHeight = max(proxy.size.height - 54, 430)
            let deviceHeight = min(availableHeight, 780)
            let deviceWidth = deviceHeight * 0.468

            DeviceFrame(app: app, controller: controller, orientation: .portrait)
                .frame(width: deviceWidth, height: deviceHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct DeviceFrame: View {
    let app: SimulatedApp
    @ObservedObject var controller: WebViewController
    let orientation: DeviceOrientation

    var body: some View {
        Group {
            if orientation == .portrait {
                portraitBody
            } else {
                landscapeBody
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(app.title) in \(orientation.title.lowercased()) device mode")
    }

    private var portraitBody: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 47, style: .continuous)
                .fill(Color.black)
                .shadow(color: Color.black.opacity(0.42), radius: 32, y: 16)

            VStack(spacing: 0) {
                DeviceStatusBar()

                WebContent(controller: controller, cornerRadius: 25)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HomeIndicator()
            }
            .padding(7)
            .clipShape(RoundedRectangle(cornerRadius: 41, style: .continuous))

            Capsule()
                .fill(Color.black)
                .frame(width: 92, height: 25)
                .padding(.top, 13)
        }
    }

    private var landscapeBody: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 47, style: .continuous)
                .fill(Color.black)
                .shadow(color: Color.black.opacity(0.42), radius: 32, y: 16)

            HStack(spacing: 0) {
                LandscapeStatusBar()

                WebContent(controller: controller, cornerRadius: 25)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                LandscapeHomeIndicator()
            }
            .padding(7)
            .clipShape(RoundedRectangle(cornerRadius: 41, style: .continuous))

            Capsule()
                .fill(Color.black)
                .frame(width: 25, height: 92)
                .padding(.leading, 13)
        }
    }
}

struct DeviceStatusBar: View {
    var body: some View {
        HStack {
            Text(Date(), style: .time)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 17)
        .frame(height: 42)
        .background(Color.black)
    }
}

struct HomeIndicator: View {
    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.86))
            .frame(width: 93, height: 4)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .background(Color.black)
    }
}

struct LandscapeStatusBar: View {
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "cellularbars")
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 42)
        .background(Color.black)
    }
}

struct LandscapeHomeIndicator: View {
    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.86))
            .frame(width: 4, height: 93)
            .padding(.horizontal, 12)
            .frame(width: 42)
            .background(Color.black)
    }
}

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
                .id(controller.app.id)

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

struct ServiceIcon: View {
    let app: SimulatedApp
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [app.tint.opacity(0.98), app.tint.opacity(0.64)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: app.symbolName)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(app.id == SimulatedApp.x.id ? Color.black.opacity(0.82) : .white)
        }
        .frame(width: size, height: size)
        .shadow(color: app.tint.opacity(0.18), radius: 8, y: 4)
    }
}
