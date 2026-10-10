import SwiftUI

struct MultiScreenView: View {
    @ObservedObject var model: PocketModel
    @StateObject private var activity = ScreenChromeActivity()

    var body: some View {
        GeometryReader { proxy in
            let frames = model.screenLayout.frames(in: proxy.size)
            ZStack(alignment: .topLeading) {
                ForEach(model.screenLayout.screenIDs, id: \.self) { id in
                    ScreenPageView(screen: model.screens[id])
                        .frame(width: frames[id].width, height: frames[id].height)
                        .position(x: frames[id].midX, y: frames[id].midY)
                }

                VStack(spacing: 0) {
                    HStack {
                        CompactWindowActions()
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .frame(height: ScreenLayout.topBarHeight)
                    .background(Color.screenChromeBackground)
                    .background(WindowDragHandle(showsIndicator: false))
                    Spacer(minLength: 0).allowsHitTesting(false)
                    HStack {
                        Spacer(minLength: 0)
                        CompactGeneralControls(model: model)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: ScreenLayout.bottomBarHeight)
                    .background(Color.screenChromeBackground)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .opacity(activity.screenID == nil ? 0 : 1)
                .allowsHitTesting(activity.screenID != nil)

                // Individual capsules sit outside their own page. On outer
                // rows they overlay the shared bars; on interior rows they
                // extend over the neighboring page without moving either one.
                ForEach(model.screenLayout.screenIDs, id: \.self) { id in
                    ScreenSpecificControls(model: model, screen: model.screens[id], page: frames[id])
                        .opacity(activity.screenID == id ? 1 : 0)
                        .allowsHitTesting(activity.screenID == id)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay {
                ScreenActivityTrackingView { point in
                    let id = ScreenControlGeometry.screenID(at: point, frames: frames,
                        activeScreenID: activity.screenID, focusedScreenID: model.focusedScreenID)
                    model.focusScreen(id)
                    activity.activate(id)
                } onExit: { activity.leave() }
                .accessibilityHidden(true)
            }
        }
        .onChange(of: model.screenLayout) { _, _ in activity.activate(model.focusedScreenID) }
    }
}

private extension Color {
    static let screenChromeBackground = Color(red: 0.055, green: 0.063, blue: 0.082)
}

private struct ScreenPageView: View {
    @ObservedObject var screen: PocketScreen
    var body: some View {
        WebContent(controller: screen.controller(for: screen.selectedApp), cornerRadius: 0).clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScreenSpecificControls: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var screen: PocketScreen
    let page: CGRect

    var body: some View {
        let navigation = ScreenControlGeometry.navigation(above: page)
        let website = ScreenControlGeometry.website(above: page)
        CompactNavigationControls(controller: screen.controller(for: screen.selectedApp))
            .frame(width: navigation.width, height: navigation.height)
            .position(x: navigation.midX, y: navigation.midY)
        CompactWebsiteChooser(model: model, screen: screen, height: website.height)
            .frame(width: website.width, height: website.height)
            .position(x: website.midX, y: website.midY)
    }
}

struct ScreenLayoutIcon: View {
    let layout: ScreenLayout
    var body: some View {
        Image(nsImage: layout.iconImage)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: 16, height: 16)
            .foregroundStyle(.white)
            .accessibilityHidden(true)
    }
}

struct CompactScreenLayoutPicker: View {
    @ObservedObject var model: PocketModel
    @State private var isManagingLayouts = false

    var body: some View {
        Menu {
            ForEach(model.favoriteScreenLayouts) { layout in
                Button {
                    model.screenLayout = layout
                    model.presentationMode = .screen
                } label: {
                    Label { Text(layout.title) } icon: { Image(nsImage: layout.iconImage) }
                }
            }
            Divider()
            Button {
                isManagingLayouts = true
            } label: {
                Label("More layouts…", systemImage: "square.grid.3x3")
            }
        } label: {
            ScreenLayoutIcon(layout: model.screenLayout)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .help("Screen layout")
        .accessibilityLabel("Screen layout")
        .accessibilityValue(model.screenLayout.title)
        .popover(isPresented: $isManagingLayouts, arrowEdge: .bottom) {
            ScreenLayoutFavoritesPicker(model: model)
        }
    }
}

private struct ScreenLayoutFavoritesPicker: View {
    @ObservedObject var model: PocketModel
    private let columns = Array(repeating: GridItem(.fixed(68), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK LAYOUTS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text("Choose which arrangements appear in this menu.")
                .font(.system(size: 11))
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(ScreenLayout.allCases) { layout in
                    let isFavorite = model.favoriteScreenLayouts.contains(layout)
                    Button {
                        model.toggleFavoriteScreenLayout(layout)
                    } label: {
                        VStack(spacing: 3) {
                            ZStack(alignment: .topTrailing) {
                                ScreenLayoutIcon(layout: layout)
                                    .frame(width: 32, height: 30)
                                if isFavorite {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .offset(x: 5, y: -3)
                                }
                            }
                            Text(layout.compactTitle)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                        .frame(width: 64, height: 52)
                        .background(isFavorite ? Color.white.opacity(0.14) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(isFavorite ? 0.24 : 0.10), lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help("\(layout.title)\(isFavorite ? ", shown in menu" : ", hidden from menu")")
                    .accessibilityLabel(layout.title)
                    .accessibilityValue(isFavorite ? "Shown in menu" : "Hidden from menu")
                    .disabled(isFavorite && model.favoriteScreenLayouts.count == 1)
                }
            }
            Text("Columns x rows")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .frame(width: 326)
        .background(.regularMaterial)
    }
}
