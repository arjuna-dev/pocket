import AppKit
import SwiftUI
import UniformTypeIdentifiers
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
                MultiScreenView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(Color.clear)
        .background(
            WindowBridge { window in
                WindowManager.shared.attach(window: window)
                WindowManager.shared.ensureInitialSize(
                    for: model.presentationMode,
                    orientation: model.orientation,
                    layout: model.screenLayout
                )
            }
            .frame(width: 1, height: 1)
        )
        .onAppear {
            selectedController.setPresentationMode(model.presentationMode)
            WindowManager.shared.restoreSize(
                for: model.presentationMode,
                orientation: model.orientation,
                layout: model.screenLayout,
                animated: false
            )
        }
        .onChange(of: model.presentationMode) { _, newMode in
            selectedController.setPresentationMode(newMode)
            WindowManager.shared.restoreSize(
                for: newMode,
                orientation: model.orientation,
                layout: model.screenLayout,
                animated: true
            )
        }
        .onChange(of: model.orientation) { _, newOrientation in
            WindowManager.shared.restoreSize(
                for: model.presentationMode,
                orientation: newOrientation,
                layout: model.screenLayout,
                animated: true
            )
        }
        .onChange(of: model.screenLayout) { _, layout in
            WindowManager.shared.changeScreenLayout(to: layout)
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
    @StateObject private var activity = ScreenChromeActivity()
    private var controlsVisible: Bool { activity.screenID != nil }

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
            ScreenActivityTrackingView { _ in
                activity.activate(model.focusedScreenID)
            } onExit: {
                activity.leave()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
        }
    }
}

// Combined controls are used by the single mock-device presentation.
struct CompactControls: View {
    @ObservedObject var model: PocketModel
    let scale: CGFloat
    private static let idealWidth = CompactLayout.controlsIdealWidth

    static func scaleToFit(width: CGFloat) -> CGFloat { CompactLayout.controlsScale(for: width) }
    static func bayHeight(for width: CGFloat) -> CGFloat { CompactLayout.controlsBayHeight(for: width) }

    var body: some View {
        HStack(spacing: 5) {
            CompactWebsiteChooser(model: model, screen: model.screens[model.focusedScreenID])
            CompactGeneralControls(model: model)
        }
        .frame(width: Self.idealWidth, height: 40)
        .scaleEffect(scale)
        .frame(width: Self.idealWidth * scale, height: 40 * scale)
    }
}

struct CompactWebsiteChooser: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var screen: PocketScreen
    var height: CGFloat = 40

    var body: some View {
        Menu {
            ForEach(model.enabledApps) { app in
                Button { model.select(app, in: screen.id) } label: {
                    Label(app.title, systemImage: app.symbolName)
                }
            }
        } label: {
            HStack(spacing: 7) {
                ServiceIcon(app: screen.selectedApp, size: 16)
                Text(screen.selectedApp.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity)
            .frame(height: height - 4)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity)
        .padding(.trailing, 8)
        .frame(height: height)
        .background(Capsule().fill(Color.pocketBackground))
        .overlay { Capsule().stroke(Color.white.opacity(0.13), lineWidth: 1) }
        .help("Choose website for this screen")
        .accessibilityLabel("Website for screen \(screen.id + 1)")
        .accessibilityValue(screen.selectedApp.title)
    }
}

struct CompactGeneralControls: View {
    @ObservedObject var model: PocketModel

    var body: some View {
        HStack(spacing: 5) {
            CompactScreenLayoutPicker(model: model)
            CompactOrientationSwitcher(selection: $model.orientation)
            CompactAlwaysOnTopButton(model: model)
            CompactWebsiteManagerButton(model: model)
        }
        .padding(6)
        .background(Capsule().fill(Color.pocketBackground))
        .overlay { Capsule().stroke(Color.white.opacity(0.13), lineWidth: 1) }
        .fixedSize()
        .frame(height: 40)
    }
}

struct CompactWindowControlsBar: View {
    @ObservedObject var controller: WebViewController
    var body: some View {
        HStack {
            CompactWindowActions()
            Spacer(minLength: 0)
            CompactNavigationControls(controller: controller)
        }
        .frame(height: CompactLayout.windowControlsBayHeight)
    }
}

struct CompactWindowActions: View {
    @State private var areButtonIconsVisible = false
    var body: some View {
        HStack(spacing: 2) {
            WindowActionButton(symbol: "xmark", color: Color(red: 1.0, green: 0.36, blue: 0.34),
                help: "Close Pocket", showsIcon: areButtonIconsVisible, action: WindowManager.shared.closeWindow)
            WindowActionButton(symbol: "minus", color: Color(red: 1.0, green: 0.75, blue: 0.25),
                help: "Minimize Pocket", showsIcon: areButtonIconsVisible, action: WindowManager.shared.minimizeWindow)
            WindowActionButton(symbol: "arrow.up.left.and.arrow.down.right", color: Color(red: 0.34, green: 0.82, blue: 0.45),
                help: "Zoom Pocket", showsIcon: areButtonIconsVisible, action: WindowManager.shared.zoomWindow)
        }
        .onHover { areButtonIconsVisible = $0 }
    }
}

struct CompactNavigationControls: View {
    @ObservedObject var controller: WebViewController
    var body: some View {
        HStack(spacing: 3) {
            CompactControlButton(symbol: "chevron.left", help: "Back", disabled: !controller.canGoBack, size: 24) { controller.goBack() }
            CompactControlButton(symbol: "chevron.right", help: "Forward", disabled: !controller.canGoForward, size: 24) { controller.goForward() }
            CompactControlButton(symbol: "arrow.clockwise", help: "Reload", size: 24) { controller.load() }
        }
        .padding(3)
        .background(Capsule().fill(Color.pocketBackground))
        .overlay { Capsule().stroke(Color.white.opacity(0.13), lineWidth: 1) }
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
        Button { model.isWebsiteManagerPresented = true } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Manage websites")
        .accessibilityLabel("Settings")
    }
}

struct CompactControlButton: View {
    let symbol: String
    let help: String
    var disabled = false
    var size: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(disabled ? Color.white.opacity(0.68) : Color.white)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
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
        Button { model.alwaysOnTop.toggle() } label: {
            HStack(spacing: 5) {
                Text("Pin")
                Image(systemName: model.alwaysOnTop ? "pin.fill" : "pin")
            }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(model.alwaysOnTop ? Color.white : Color.white.opacity(0.82))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 7).fill(model.alwaysOnTop ? Color.white.opacity(0.13) : Color.clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.alwaysOnTop ? "Always on Top: On" : "Always on Top: Off")
        .accessibilityLabel("Pin")
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
    @State private var isBrowserImportPresented = false

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
                    isBrowserImportPresented = true
                } label: {
                    Label("Import from Browser", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

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
        .sheet(isPresented: $isBrowserImportPresented) {
            BrowserCookieImportSheet(model: model)
        }
    }
}

private struct BrowserCookieImportSheet: View {
    @ObservedObject var model: PocketModel
    @Environment(\.dismiss) private var dismiss
    @State private var profiles = BrowserCookieProfile.discover()
    @State private var selectedProfileID: String?
    @State private var isImporting = false
    @State private var message: String?
    @State private var isError = false
    @State private var savedCredentials = PocketCredentialVault.loadAll()
    @State private var isShowingSavedCredentials = false

    private var selectedProfile: BrowserCookieProfile? {
        profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Import from Browser")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Choose a browser profile to bring its sign-in cookies into Pocket.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.pocketMuted)
            }

            if profiles.isEmpty {
                ContentUnavailableView(
                    "No Session Profiles Found",
                    systemImage: "safari",
                    description: Text("You can still import saved passwords from a browser CSV export.")
                )
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SOURCE PROFILE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(Color.pocketMuted)

                    Picker("Browser profile", selection: $selectedProfileID) {
                        ForEach(profiles) { profile in
                            Text("\(profile.browserName) - \(profile.name)")
                                .tag(Optional(profile.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(isImporting)
                }

                Label {
                    Text("Cookies are copied only to Pocket websites with a matching domain. Each website keeps its own data store.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.pocketMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.pocketMuted)
                }
            }

            Divider().overlay(Color.white.opacity(0.1))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved Passwords")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Import from this Chromium profile or a browser CSV export.")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.pocketMuted)
                }
                Spacer(minLength: 4)
                Button("Import CSV…") { importPasswordCSV() }
                    .buttonStyle(.bordered)
                    .disabled(isImporting)
                Button("Import Passwords") { importSavedPasswords() }
                    .buttonStyle(.bordered)
                    .disabled(selectedProfile == nil || isImporting)
            }

            if !savedCredentials.isEmpty {
                Button {
                    isShowingSavedCredentials.toggle()
                } label: {
                    Label(
                        "\(isShowingSavedCredentials ? "Hide" : "View") Imported Passwords (\(savedCredentials.count))",
                        systemImage: isShowingSavedCredentials ? "chevron.up" : "key.horizontal"
                    )
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                }
                .buttonStyle(.plain)

                if isShowingSavedCredentials {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(savedCredentials) { credential in
                                ImportedCredentialRow(credential: credential) {
                                    PocketCredentialVault.delete(credential)
                                    savedCredentials = PocketCredentialVault.loadAll()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 115)
                }
            }

            if let message {
                Text(message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isError ? Color.orange : Color.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    refreshProfiles()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .help("Rescan browser profiles")
                .disabled(isImporting)

                Button {
                    importSelectedProfile()
                } label: {
                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 115, height: 20)
                    } else {
                        Text("Import Cookies")
                            .frame(width: 115, height: 20)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.78, green: 0.31, blue: 0.20))
                .disabled(selectedProfile == nil || isImporting)
            }
        }
        .padding(24)
        .frame(width: 520, height: 500)
        .background(Color.pocketBackground)
        .preferredColorScheme(.dark)
        .onAppear { refreshProfiles() }
    }

    private func refreshProfiles() {
        profiles = BrowserCookieProfile.discover()
        if !profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = profiles.first?.id
        }
    }

    private func importSelectedProfile() {
        guard let profile = selectedProfile else { return }
        isImporting = true
        message = nil
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try BrowserCookieImporter.readCookies(from: profile)
                }.value
                let installed = await model.installBrowserCookies(result.cookies)
                if installed.cookieCount == 0 {
                    message = "Read \(result.cookies.count) cookies, but none matched a Pocket website."
                    isError = true
                } else {
                    let names = installed.websiteNames.joined(separator: ", ")
                    let skipped = result.skippedEncryptedCookies > 0
                        ? " \(result.skippedEncryptedCookies) encrypted cookies could not be read."
                        : ""
                    message = "Imported \(installed.cookieCount) cookies for \(names).\(skipped)"
                    isError = false
                }
            } catch {
                message = error.localizedDescription
                isError = true
            }
            isImporting = false
        }
    }

    private func importSavedPasswords() {
        guard let profile = selectedProfile else { return }
        switch profile.kind {
        case .chromium:
            isImporting = true
            message = nil
            Task {
                do {
                    let credentials = try await Task.detached(priority: .userInitiated) {
                        try BrowserCredentialImporter.readChromiumPasswords(from: profile)
                    }.value
                    let count = try PocketCredentialVault.save(credentials)
                    savedCredentials = PocketCredentialVault.loadAll()
                    message = "Imported \(count) saved passwords into Pocket's Keychain-backed password list."
                    isError = false
                } catch {
                    message = error.localizedDescription
                    isError = true
                }
                isImporting = false
            }
        case .firefox:
            importPasswordCSV()
        }
    }

    private func importPasswordCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a passwords CSV exported from your browser."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isImporting = true
        message = nil
        Task {
            do {
                let credentials = try await Task.detached(priority: .userInitiated) {
                    try BrowserCredentialImporter.readPasswordCSV(from: url)
                }.value
                let count = try PocketCredentialVault.save(credentials)
                savedCredentials = PocketCredentialVault.loadAll()
                message = "Imported \(count) saved passwords into Pocket's Keychain-backed password list."
                isError = false
            } catch {
                message = error.localizedDescription
                isError = true
            }
            isImporting = false
        }
    }
}

private struct ImportedCredentialRow: View {
    let credential: ImportedBrowserCredential
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(credential.websiteName)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(credential.username)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.pocketMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button("Copy user") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(credential.username, forType: .string)
            }
            .help("Copy username")
            Button("Copy password") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(credential.password, forType: .string)
            }
            .help("Copy password")
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete imported password")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pocketBackground)
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    @ObservedObject var controller: WebViewController

    func makeNSView(context: Context) -> WebViewHost {
        WebViewHost(webView: controller.webView)
    }

    func updateNSView(_ nsView: WebViewHost, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WebViewHost, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

// SwiftUI sizes the tile, and this host pins WebKit to that exact rectangle.
// Website intrinsic content sizes must never influence the grid's geometry.
final class WebViewHost: NSView {
    let webView: WKWebView
    override var isFlipped: Bool { true }

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
        webView.frame = bounds
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        if webView.frame != bounds { webView.frame = bounds }
    }
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
