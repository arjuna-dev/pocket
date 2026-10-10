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
            .renderingMode(.template)
            .frame(width: 16, height: 16)
            .foregroundStyle(.white)
            .accessibilityHidden(true)
    }
}

struct CompactScreenLayoutPicker: View {
    @ObservedObject var model: PocketModel

    var body: some View {
        Menu {
            ForEach(ScreenLayout.allCases) { layout in
                Button {
                    model.screenLayout = layout
                    model.presentationMode = .screen
                } label: {
                    Label { Text(layout.title) } icon: { Image(nsImage: layout.iconImage) }
                }
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
    }
}
