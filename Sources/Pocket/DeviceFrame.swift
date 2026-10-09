import AppKit
import SwiftUI
import WebKit

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
