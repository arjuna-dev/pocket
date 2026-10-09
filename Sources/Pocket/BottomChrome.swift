import AppKit
import SwiftUI

struct CompactControls: View {
    @ObservedObject var model: PocketModel
    @State private var isOrientationHovering = false

    private static let orientationHoverText = "Cmd + 1 - Portrait, Cmd + 2 - Landscape"

    var body: some View {
        ViewThatFits(in: .horizontal) {
            controlsBar(showsTitles: true)
            controlsBar(showsTitles: false)
        }
    }

    private func controlsBar(showsTitles: Bool) -> some View {
        HStack(spacing: showsTitles ? 10 : 6) {
            CompactChromeButton(
                symbol: model.orientation == .portrait ? "iphone" : "iphone.landscape",
                title: model.orientation.title,
                showsTitle: showsTitles,
                showsHoverTitle: false
            ) {
                model.orientation = model.orientation == .portrait ? .landscape : .portrait
            }
            .onHover { isOrientationHovering = $0 }

            CompactChromeButton(
                symbol: model.alwaysOnTop ? "pin.fill" : "pin",
                title: "Pin",
                showsTitle: showsTitles,
                accessibilityValue: model.alwaysOnTop ? "On" : "Off"
            ) {
                model.alwaysOnTop.toggle()
            }

            CompactChromeButton(
                symbol: "slider.horizontal.3",
                title: "Manage sites",
                showsTitle: showsTitles
            ) {
                model.isWebsiteManagerPresented = true
            }
        }
        .padding(.horizontal, showsTitles ? 12 : 10)
        .overlay(alignment: .top) {
            if isOrientationHovering {
                Text(Self.orientationHoverText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(Color(white: 0.22))
                    }
                    .fixedSize()
                    .offset(y: -32)
                    .allowsHitTesting(false)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct CompactChromeButton: View {
    let symbol: String
    let title: String
    var showsTitle: Bool
    var showsHoverTitle = true
    var accessibilityValue: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CompactChromeLabel(symbol: symbol, title: title, showsTitle: showsTitle)
        }
        .buttonStyle(.plain)
        .modifier(
            CompactHoverTitleModifier(
                title: title,
                showsTitle: showsTitle,
                showsHoverTitle: showsHoverTitle
            )
        )
        .chromeControl(label: title, value: accessibilityValue)
    }
}

private struct CompactChromeLabel: View {
    let symbol: String
    let title: String
    var showsTitle: Bool
    var showsChevron = false
    var chevronPointsUp = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 16, height: 16)

            if showsTitle {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if showsChevron {
                    Image(systemName: chevronPointsUp ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
        }
        .foregroundStyle(Color.white.opacity(0.88))
        .padding(.horizontal, showsTitle ? 2 : 4)
        .frame(height: 24)
        .contentShape(Rectangle())
    }
}

private struct CompactHoverTitleModifier: ViewModifier {
    let title: String
    let showsTitle: Bool
    var showsHoverTitle = true
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .overlay(alignment: .top) {
                if isHovering && showsHoverTitle && !showsTitle {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(Color(white: 0.22))
                        }
                        .fixedSize()
                        .offset(y: -30)
                        .allowsHitTesting(false)
                }
            }
            .zIndex(isHovering && showsHoverTitle && !showsTitle ? 1 : 0)
            .modifier(CompactHelpModifier(title: showsHoverTitle ? title : nil))
    }
}

private struct CompactHelpModifier: ViewModifier {
    let title: String?

    func body(content: Content) -> some View {
        if let title {
            content.help(title)
        } else {
            content
        }
    }
}


