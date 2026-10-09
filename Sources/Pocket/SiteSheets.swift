import AppKit
import SwiftUI
import WebKit

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
    var showsHeading = true
    @State private var editorTarget: WebsiteEditorTarget?
    @State private var websitePendingRemoval: SimulatedApp?
    @State private var isBrowserImportPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WebsiteManagerHeader(websiteCount: model.websites.count, showsHeading: showsHeading) {
                editorTarget = .new
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.websites) { website in
                        WebsiteManagerRow(
                            website: website,
                            isOpen: model.openAppIDs.contains(website.id),
                            onToggle: { model.setEnabled($0, for: website) },
                            onEdit: { editorTarget = .edit(website) },
                            onRemove: { websitePendingRemoval = website }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            WebsiteImportBar {
                isBrowserImportPresented = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.pocketBackground)
        .sheet(isPresented: $isBrowserImportPresented) {
            BrowserImportSheet(model: model)
        }
        .sheet(item: $editorTarget) { target in
            WebsiteEditorSheet(model: model, website: target.website)
        }
        .alert(
            removeAlertTitle,
            isPresented: removeAlertPresented
        ) {
            if model.websites.count > 1 {
                Button("Delete", role: .destructive) {
                    if let websitePendingRemoval {
                        model.removeWebsite(websitePendingRemoval)
                    }
                    websitePendingRemoval = nil
                }
                Button("Cancel", role: .cancel) {
                    websitePendingRemoval = nil
                }
            } else {
                Button("OK", role: .cancel) {
                    websitePendingRemoval = nil
                }
            }
        } message: {
            Text(removeAlertMessage)
        }
    }

    private var removeAlertPresented: Binding<Bool> {
        Binding(
            get: { websitePendingRemoval != nil },
            set: { if !$0 { websitePendingRemoval = nil } }
        )
    }

    private var removeAlertTitle: String {
        guard let websitePendingRemoval else { return "Remove website?" }
        if model.websites.count == 1 {
            return "Can’t remove \(websitePendingRemoval.title)"
        }
        return "Remove \(websitePendingRemoval.title)?"
    }

    private var removeAlertMessage: String {
        guard let websitePendingRemoval else { return "" }
        if model.websites.count == 1 {
            return "Pocket needs at least one website."
        }
        return "\(websitePendingRemoval.title) will be removed from Pocket."
    }
}

private struct WebsiteManagerHeader: View {
    let websiteCount: Int
    var showsHeading = true
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                if showsHeading {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Websites")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("\(websiteCount)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background {
                                Capsule()
                                    .fill(Color.white.opacity(0.1))
                            }
                            .accessibilityLabel("\(websiteCount) websites")
                    }
                }

                Text("Choose what appears in Pocket's app switcher.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.pocketMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(action: onAdd) {
                Label("Add Website", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.78, green: 0.31, blue: 0.20))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.top, showsHeading ? 18 : 8)
        .padding(.bottom, 14)
    }
}

private struct WebsiteImportBar: View {
    let onImport: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(BrowserSessionImporter.websitesButtonTitle())
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Import Sessions…", action: onImport)
                .buttonStyle(SettingsImportButtonStyle())
                .fixedSize(horizontal: true, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color.pocketChrome)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }
}

private struct SettingsImportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.24 : 0.14))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            }
    }
}

struct WebsiteManagerRow: View {
    let website: SimulatedApp
    let isOpen: Bool
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

                    if isOpen {
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
            .accessibilityLabel("Enabled")

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Edit website")
            .accessibilityLabel("Edit website")

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Remove website")
            .accessibilityLabel("Remove website")
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
