import AppKit
import SwiftUI

enum PocketSettingsSection: String, Hashable, Identifiable {
    case websites
    case shortcuts

    var id: String { rawValue }
}

struct PocketSettingsOverlayRoot: View {
    @ObservedObject var model: PocketModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if model.isSettingsPresented {
                PocketSettingsOverlay(model: model)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(!model.isSettingsPresented)
        .animation(PocketMotion.fade(reduceMotion), value: model.isSettingsPresented)
    }
}

private struct SettingsFocusBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsFocusView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.didFocus else { return }
        context.coordinator.didFocus = true
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var didFocus = false
    }
}

private final class SettingsFocusView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            PocketModel.shared.isSettingsPresented = false
            return
        }
        super.keyDown(with: event)
    }
}

/// Covers Pocket until Settings is closed. Clicks pass through while it is hidden.
final class PocketOverlayHost: NSHostingView<PocketSettingsOverlayRoot> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard PocketModel.shared.isSettingsPresented else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return super.hitTest(point) ?? self
    }

    override func mouseDown(with event: NSEvent) {}

    override func rightMouseDown(with event: NSEvent) {}

    override func otherMouseDown(with event: NSEvent) {}

    override func scrollWheel(with event: NSEvent) {
        guard PocketModel.shared.isSettingsPresented else { return }
        super.scrollWheel(with: event)
    }
}

private struct PocketSettingsOverlay: View {
    @ObservedObject var model: PocketModel

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = min(520, max(0, proxy.size.width - 28))
            let cardHeight = min(740, max(0, proxy.size.height - 28))

            ZStack {
                Color.black.opacity(0.58)
                    .contentShape(Rectangle())
                    .onTapGesture {}

                PocketSettingsCard(model: model)
                    .frame(width: cardWidth, height: cardHeight)
            }
        }
        .background(SettingsFocusBridge())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Settings")
    }
}

private struct PocketSettingsCard: View {
    @ObservedObject var model: PocketModel

    var body: some View {
        VStack(spacing: 0) {
            SettingsOverlayHeader {
                KeyBindingStore.shared.recording = nil
                model.isSettingsPresented = false
            }

            SettingsSectionSwitcher(selection: $model.settingsSection)

            Group {
                switch model.settingsSection {
                case .websites:
                    WebsiteManagerSheet(model: model, showsHeading: false)
                case .shortcuts:
                    KeywordShortcutsPage(showsHeading: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.pocketBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.5), radius: 28, y: 12)
    }
}

private struct SettingsOverlayHeader: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Text("Settings")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background {
                            Circle()
                                .fill(Color.white.opacity(0.14))
                        }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close Settings")

                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

private struct SettingsSectionSwitcher: View {
    @Binding var selection: PocketSettingsSection

    var body: some View {
        HStack(spacing: 4) {
            SettingsSectionButton(
                title: "Websites",
                accessibilityTitle: "Websites",
                systemImage: "globe",
                isSelected: selection == .websites
            ) {
                selection = .websites
            }

            SettingsSectionButton(
                title: "Shortcuts",
                accessibilityTitle: "Keyword Shortcuts",
                systemImage: "keyboard",
                isSelected: selection == .shortcuts
            ) {
                selection = .shortcuts
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

private struct SettingsSectionButton: View {
    let title: String
    let accessibilityTitle: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.62))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.14) : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PocketSettingsView: View {
    @ObservedObject var model: PocketModel

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $model.settingsSection)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)

            Group {
                switch model.settingsSection {
                case .websites:
                    WebsiteManagerSheet(model: model)
                case .shortcuts:
                    KeywordShortcutsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Color.pocketBackground)
        .preferredColorScheme(.dark)
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: PocketSettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.pocketMuted)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

            SettingsSidebarRow(
                title: "Websites",
                systemImage: "globe",
                isSelected: selection == .websites
            ) {
                selection = .websites
            }

            SettingsSidebarRow(
                title: "Keyword Shortcuts",
                systemImage: "keyboard",
                isSelected: selection == .shortcuts
            ) {
                selection = .shortcuts
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .padding(.top, 8)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.pocketChrome)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }
}

private struct SettingsSidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.72))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.14) : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct KeywordShortcutsPage: View {
    var showsHeading = true
    @ObservedObject private var bindings = KeyBindingStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeading {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyword Shortcuts")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Click a shortcut, then press the new keys.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.pocketMuted)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)
            } else {
                Text("Click a shortcut, then press the new keys. Escape cancels.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.pocketMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(PocketCommand.allCases) { command in
                        KeywordShortcutRow(command: command, bindings: bindings)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.pocketBackground)
    }
}

private struct KeywordShortcutRow: View {
    let command: PocketCommand
    @ObservedObject var bindings: KeyBindingStore

    private var isRecording: Bool { bindings.recording == command }
    private var chord: KeyChord { bindings.chord(for: command) }

    var body: some View {
        HStack(spacing: 12) {
            Text(command.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Spacer(minLength: 12)

            Button {
                bindings.beginRecording(command)
            } label: {
                Text(isRecording ? "Press keys" : chord.symbols)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(Color.white.opacity(isRecording ? 0.22 : 0.08))
                    }
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(isRecording ? 0.55 : 0.16), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRecording ? "Press a new shortcut for \(command.title)" : "\(command.title), \(chord.spoken)")
            .accessibilityHint("Click, then press a new shortcut. Escape cancels.")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.055))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}
