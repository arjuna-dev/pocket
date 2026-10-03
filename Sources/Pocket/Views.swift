import AppKit
import SwiftUI
import WebKit

private extension Color {
    static let pocketBackground = Color(red: 0.055, green: 0.063, blue: 0.082)
    static let pocketMuted = Color(red: 0.48, green: 0.50, blue: 0.57)
}

struct AppRootView: View {
    @ObservedObject var model: PocketModel

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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(Color.clear)
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
        .sheet(isPresented: $model.isWebsiteManagerPresented) {
            WebsiteManagerSheet(model: model)
        }
        .preferredColorScheme(.dark)
    }
}

struct CompactDeviceView: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var controller: WebViewController
    @State private var controlsVisible = false

    var body: some View {
        GeometryReader { proxy in
            let deviceSize = model.orientation.deviceSize
            let availableWidth = max(proxy.size.width, 1)
            let controlsScale = CompactControls.scaleToFit(width: availableWidth)
            let controlsBayHeight = CompactControls.bayHeight(for: availableWidth)
            let topControlsBayHeight = CompactLayout.windowControlsBayHeight
            let availableHeight = max(proxy.size.height - topControlsBayHeight - controlsBayHeight, 1)
            let scale = max(
                min(availableWidth / deviceSize.width, availableHeight / deviceSize.height),
                0.1
            )

            VStack(spacing: 0) {
                ZStack {
                    if controlsVisible {
                        CompactWindowControlsBar(controller: controller)
                            .padding(.horizontal, 8)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: topControlsBayHeight)
                .background(controlsVisible ? Color.pocketBackground : Color.clear)
                .transaction { $0.animation = nil }

                ZStack {
                    DeviceFrame(
                        app: model.selectedApp,
                        controller: controller,
                        orientation: model.orientation
                    )
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
                            scale: controlsScale
                        )
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: controlsBayHeight)
                .background(controlsVisible ? Color.pocketBackground : Color.clear)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @ObservedObject var model: PocketModel
    @ObservedObject var controller: WebViewController
    @State private var controlsVisible = false

    var body: some View {
        GeometryReader { proxy in
            let screenSize = model.orientation.screenSize
            let dragBarBaseHeight = model.presentationMode.screenDragBarHeight
            let availableWidth = max(proxy.size.width, 1)
            let controlsScale = CompactControls.scaleToFit(width: availableWidth)
            let controlsBayHeight = CompactControls.bayHeight(for: availableWidth)
            let topControlsBayHeight = CompactLayout.windowControlsBayHeight
            let availableHeight = max(proxy.size.height - topControlsBayHeight - controlsBayHeight, 1)
            let widthScale = availableWidth / screenSize.width
            let dragBarHeight = min(dragBarBaseHeight * widthScale, max(availableHeight - 1, 0))
            let screenHeight = max(availableHeight - dragBarHeight, 1)

            VStack(spacing: 0) {
                ZStack {
                    if controlsVisible {
                        CompactWindowControlsBar(controller: controller)
                            .padding(.horizontal, 8)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: topControlsBayHeight)
                .background(controlsVisible ? Color.pocketBackground : Color.clear)
                .transaction { $0.animation = nil }

                WindowDragHandle(showsIndicator: controlsVisible)
                    .frame(width: availableWidth, height: dragBarHeight)
                    .frame(maxWidth: .infinity)
                    .help("Drag to move window")

                ZStack {
                    WebContent(controller: controller, cornerRadius: 0)
                        .frame(width: availableWidth, height: screenHeight)
                }

                ZStack {
                    if controlsVisible {
                        CompactControls(
                            model: model,
                            scale: controlsScale
                        )
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: controlsBayHeight)
                .background(controlsVisible ? Color.pocketBackground : Color.clear)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @ObservedObject var model: PocketModel
    let scale: CGFloat

    private static let idealWidth = CompactLayout.controlsIdealWidth

    static func scaleToFit(width: CGFloat) -> CGFloat {
        CompactLayout.controlsScale(for: width)
    }

    static func bayHeight(for width: CGFloat) -> CGFloat {
        CompactLayout.controlsBayHeight(for: width)
    }

    var body: some View {
        HStack(spacing: 5) {
            Menu {
                ForEach(model.enabledApps) { app in
                    Button {
                        model.select(app)
                    } label: {
                        HStack(spacing: 7) {
                            ServiceIcon(app: app, size: 16)
                            Text(app.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    ServiceIcon(app: model.selectedApp, size: 16)

                    Text(model.selectedApp.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 112, alignment: .leading)
                }
            }
            .menuStyle(.borderlessButton)
            .help("Switch app")

            CompactOrientationSwitcher(selection: $model.orientation)

            CompactAlwaysOnTopButton(model: model)
            CompactWebsiteManagerButton(model: model)
        }
        .padding(6)
        .background(Capsule().fill(Color.pocketBackground))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 14, y: 7)
        .frame(width: Self.idealWidth, height: 40)
        .scaleEffect(scale)
        .frame(
            width: Self.idealWidth * scale,
            height: 40 * scale
        )
    }
}

struct CompactWindowControlsBar: View {
    @State private var areButtonIconsVisible = false
    @ObservedObject var controller: WebViewController

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                WindowActionButton(
                    symbol: "xmark",
                    color: Color(red: 1.0, green: 0.36, blue: 0.34),
                    help: "Close Pocket",
                    showsIcon: areButtonIconsVisible,
                    action: WindowManager.shared.closeWindow
                )

                WindowActionButton(
                    symbol: "minus",
                    color: Color(red: 1.0, green: 0.75, blue: 0.25),
                    help: "Minimize Pocket",
                    showsIcon: areButtonIconsVisible,
                    action: WindowManager.shared.minimizeWindow
                )

                WindowActionButton(
                    symbol: "arrow.up.left.and.arrow.down.right",
                    color: Color(red: 0.34, green: 0.82, blue: 0.45),
                    help: "Zoom Pocket",
                    showsIcon: areButtonIconsVisible,
                    action: WindowManager.shared.zoomWindow
                )
            }
            .onHover { areButtonIconsVisible = $0 }

            Spacer(minLength: 0)

            HStack(spacing: 3) {
                CompactControlButton(
                    symbol: "chevron.left",
                    help: "Back",
                    disabled: !controller.canGoBack
                ) {
                    controller.goBack()
                }

                CompactControlButton(
                    symbol: "chevron.right",
                    help: "Forward",
                    disabled: !controller.canGoForward
                ) {
                    controller.goForward()
                }

                CompactControlButton(symbol: "arrow.clockwise", help: "Reload") {
                    controller.load()
                }
            }
            .padding(6)
            .background(Capsule().fill(Color.pocketBackground))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.13), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.35), radius: 14, y: 7)
        }
        .frame(maxWidth: .infinity)
        .frame(height: CompactLayout.windowControlsBayHeight)
    }
}

private struct WindowActionButton: View {
    let symbol: String
    let color: Color
    let help: String
    let showsIcon: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                .frame(width: 14, height: 14)

                Image(systemName: symbol)
                    .font(.system(size: 6, weight: .heavy))
                    .foregroundStyle(Color.black.opacity(0.78))
                    .opacity(showsIcon ? 1 : 0)
                    .animation(.easeOut(duration: 0.1), value: showsIcon)
            }
            .frame(width: 18, height: 18)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct CompactWebsiteManagerButton: View {
    @ObservedObject var model: PocketModel

    var body: some View {
        Button {
            model.isWebsiteManagerPresented = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                Text("Manage sites")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Manage websites")
        .accessibilityLabel("Manage sites")
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
                .foregroundStyle(disabled ? Color.white.opacity(0.68) : Color.white)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
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
    @ObservedObject var model: PocketModel

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
    @ObservedObject var model: PocketModel
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

                Text("Disabled websites stay saved but disappear from Pocket's app switcher.")
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
    @ObservedObject var model: PocketModel
    let website: SimulatedApp?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var subtitle: String
    @State private var urlString: String
    @State private var symbolName: String
    @State private var validationMessage: String?

    private static let iconOptions = [
        "globe", "globe.americas.fill", "globe.europe.africa.fill", "globe.asia.australia.fill",
        "link", "safari", "network", "rectangle.on.rectangle", "macwindow", "server.rack",
        "wifi", "antenna.radiowaves.left.and.right", "cloud.fill", "lock.fill", "key.fill",
        "shield.fill", "gearshape.fill", "wrench.and.screwdriver.fill", "slider.horizontal.3",
        "message.fill", "bubble.left.and.bubble.right.fill", "paperplane.fill", "phone.fill",
        "video.fill", "envelope.fill", "megaphone.fill", "bell.fill", "person.crop.circle.fill",
        "person.2.fill", "person.3.fill", "radio.fill", "mic.fill", "video.camera.fill",
        "play.rectangle.fill", "play.fill", "music.note", "music.mic", "headphones", "film.fill",
        "tv.fill", "gamecontroller.fill", "camera.fill", "photo.fill", "doc.text.image.fill",
        "cart.fill", "bag.fill", "creditcard.fill", "banknote.fill", "gift.fill", "book.fill",
        "newspaper.fill", "bookmark.fill", "note.text", "folder.fill", "tray.full.fill",
        "checklist", "list.bullet.rectangle.portrait.fill", "pencil.and.outline", "calendar",
        "clock.fill", "map.fill", "mappin.and.ellipse", "house.fill", "building.2.fill", "car.fill",
        "airplane", "fork.knife", "cup.and.saucer.fill", "bolt.fill", "flame.fill", "leaf.fill",
        "sun.max.fill", "moon.fill", "heart.fill", "star.fill", "flag.fill", "checkmark.seal.fill",
        "briefcase.fill", "terminal.fill", "chevron.left.forwardslash.chevron.right", "cpu.fill",
        "brain.head.profile", "chart.bar.fill", "chart.pie.fill", "face.smiling.fill",
        "hand.thumbsup.fill", "quote.bubble.fill", "rosette", "ellipsis.circle.fill"
    ]

    init(model: PocketModel, website: SimulatedApp?) {
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
            header
            websiteFields
            iconPicker
            validationNotice
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: 480, height: 540)
        .background(Color.pocketBackground)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
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
    }

    private var websiteFields: some View {
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
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Icon")
                .formLabelStyle()

            ScrollView(.vertical) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 8), spacing: 7) {
                    ForEach(Self.iconOptions, id: \.self) { icon in
                        iconButton(for: icon)
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.visible)
            .frame(height: 156)
        }
    }

    private func iconButton(for icon: String) -> some View {
        Button {
            symbolName = icon
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(symbolName == icon ? Color.white : Color.white.opacity(0.68))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(symbolName == icon
                              ? Color(red: 0.78, green: 0.31, blue: 0.20).opacity(0.75)
                              : Color.white.opacity(0.06))
                }
        }
        .buttonStyle(.plain)
        .help(icon)
    }

    @ViewBuilder
    private var validationNotice: some View {
        if let validationMessage {
            Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.orange)
        }
    }

    private var footer: some View {
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
                .fill(app.tint)

            fallbackSymbol
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }

    private var fallbackSymbol: some View {
        Image(systemName: app.symbolName)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(app.id == SimulatedApp.x.id ? Color.black.opacity(0.82) : .white)
    }
}
