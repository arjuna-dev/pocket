import AppKit
import SwiftUI
import WebKit

struct PocketTopChrome: View {
    @ObservedObject var model: PocketModel
    @ObservedObject private var windowManager = WindowManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: Bool {
        windowManager.isChromeVisible
            || windowManager.accessibilityFocusKeepsChrome
            || model.isSiteMenuPresented
            || model.isScreenRemovalPresented
    }

    var body: some View {
        ZStack {
            if let slot = model.activeSlot {
                ScreenControlsBar(
                    model: model,
                    slot: slot,
                    showsWindowButtons: true,
                    isSiteMenuPresented: $model.isSiteMenuPresented
                )
                .padding(.horizontal, 12)
                .pocketFade(shown)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shown ? Color.pocketChrome : Color.clear)
        .animation(PocketMotion.fade(reduceMotion), value: shown)
        .ignoresSafeArea()
        .onPreferenceChange(ChromeControlFocusedKey.self) { focused in
            WindowManager.shared.setChromeFocused(focused, source: "top")
        }
        .alert(
            "Remove \(model.activeSlot?.app.title ?? "this screen")?",
            isPresented: $model.isScreenRemovalPresented
        ) {
            Button("Remove", role: .destructive) {
                if let index = model.activeSlot?.index {
                    model.closePane(index)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected screen.")
        }
    }
}

struct PocketBottomChrome: View {
    @ObservedObject var model: PocketModel
    @ObservedObject private var windowManager = WindowManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: Bool {
        windowManager.isChromeVisible || windowManager.accessibilityFocusKeepsChrome
    }

    var body: some View {
        ZStack {
            CompactControls(model: model)
                .pocketFade(shown)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shown ? Color.pocketChrome : Color.clear)
        .animation(PocketMotion.fade(reduceMotion), value: shown)
        .ignoresSafeArea()
        .onPreferenceChange(ChromeControlFocusedKey.self) { focused in
            WindowManager.shared.setChromeFocused(focused, source: "bottom")
        }
    }
}


private struct WindowTrafficLights: View {
    @State private var areButtonIconsVisible = false

    var body: some View {
        HStack(spacing: 4) {
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
    }
}

private struct ScreenControlsBar: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var slot: ScreenSlot
    var showsWindowButtons: Bool
    @Binding var isSiteMenuPresented: Bool

    var body: some View {
        ScreenNavigationControls(
            model: model,
            slot: slot,
            controller: slot.controller,
            showsWindowButtons: showsWindowButtons,
            isSiteMenuPresented: $isSiteMenuPresented
        )
    }
}

private struct ScreenNavigationControls: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var slot: ScreenSlot
    @ObservedObject var controller: WebViewController
    var showsWindowButtons: Bool
    @Binding var isSiteMenuPresented: Bool

    var body: some View {
        HStack(spacing: 10) {
            if showsWindowButtons {
                WindowTrafficLights()
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }

            HStack(spacing: 8) {
                CompactControlButton(
                    symbol: "chevron.left",
                    help: "Back",
                    disabled: !controller.canGoBack
                ) {
                    model.focusedSlotIndex = slot.index
                    controller.goBack()
                }

                CompactControlButton(
                    symbol: "chevron.right",
                    help: "Forward",
                    disabled: !controller.canGoForward
                ) {
                    model.focusedSlotIndex = slot.index
                    controller.goForward()
                }

                CompactControlButton(symbol: "arrow.clockwise", help: "Reload") {
                    model.focusedSlotIndex = slot.index
                    controller.reloadPage()
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if model.paneLayout.leafCount > 1 {
                    Button {
                        model.focusedSlotIndex = slot.index
                        model.isScreenRemovalPresented = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .frame(width: 28, height: 28)
                            .background {
                                Circle()
                                    .fill(Color.white.opacity(0.06))
                            }
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Remove screen")
                    .chromeControl(label: "Remove screen")
                }

                CompactSiteSwitcher(model: model, slot: slot, isPresented: $isSiteMenuPresented)
            }
            .layoutPriority(1)
            .frame(minWidth: 0, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CompactLayout.windowControlsBayHeight)
        .clipped()
    }
}

private struct WindowActionButton: View {
    let symbol: String
    let color: Color
    let help: String
    let showsIcon: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .animation(PocketMotion.fade(reduceMotion, duration: 0.1), value: showsIcon)
            }
            .frame(width: 18, height: 18)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .chromeControl(label: help)
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(disabled ? Color.white.opacity(0.78) : Color.white)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .chromeControl(label: help, interactive: !disabled)
    }
}
