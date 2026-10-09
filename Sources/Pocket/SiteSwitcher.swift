import AppKit
import SwiftUI
import WebKit

struct CompactSiteSwitcher: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var slot: ScreenSlot
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                ServiceIcon(app: slot.app, size: 16)
                    .layoutPriority(1)

                Text(slot.app.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .layoutPriority(1)
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(Color.white.opacity(0.06))
            }
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Switch site")
        .chromeControl(label: slot.app.title, hint: "Switch site")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            CompactSiteMenu(model: model, slot: slot, isPresented: $isPresented)
                .presentationBackground {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.145, green: 0.155, blue: 0.175))
                }
        }
    }
}


private struct CompactSiteMenu: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var slot: ScreenSlot
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.enabledApps) { app in
                Button {
                    model.select(app, in: slot)
                    isPresented = false
                } label: {
                    HStack(spacing: 10) {
                        ServiceIcon(app: app, size: 16)

                        Text(app.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)

                        Spacer(minLength: 12)

                        if app.id == slot.app.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(red: 0.45, green: 0.84, blue: 0.52))
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 180)
    }
}
