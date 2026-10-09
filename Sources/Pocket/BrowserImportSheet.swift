import AppKit
import SwiftUI
import WebKit

struct BrowserImportSheet: View {
    @ObservedObject var model: PocketModel
    @Environment(\.dismiss) private var dismiss

    @State private var offer: BrowserImportOffer
    @State private var selectedProfileID: String
    @State private var isImporting = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    init(model: PocketModel) {
        self.model = model
        let offer = BrowserSessionImporter.loadOffer()
        _offer = State(initialValue: offer)
        let selected = offer.profiles.first(where: \.isDefault)?.id ?? offer.profiles.first?.id ?? ""
        _selectedProfileID = State(initialValue: selected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(offer.buttonTitle)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(offer.explanation)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.pocketMuted)
                .fixedSize(horizontal: false, vertical: true)

            if offer.profiles.count > 1 {
                Picker(offer.profileMenuTitle, selection: $selectedProfileID) {
                    ForEach(offer.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isImporting)
            } else if let profile = offer.profiles.first {
                Text("\(offer.profileMenuTitle): \(profile.name)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }

            if let resultMessage {
                Text(resultMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isImporting ? "Importing…" : "Import") {
                    Task { await runImport() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.78, green: 0.31, blue: 0.20))
                .disabled(isImporting || !offer.canImport || selectedProfile == nil)
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
        .background(Color.pocketBackground)
        .preferredColorScheme(.dark)
    }

    private var selectedProfile: BrowserProfile? {
        offer.profiles.first { $0.id == selectedProfileID }
    }

    private func runImport() async {
        guard let profile = selectedProfile else { return }
        isImporting = true
        errorMessage = nil
        resultMessage = nil
        defer { isImporting = false }

        let sites = model.websites.map {
            BrowserImportSite(id: $0.id, title: $0.title, dataStoreKey: $0.dataStoreKey, url: $0.url)
        }
        do {
            let report = try await BrowserSessionImporter.importCookies(from: profile, into: sites)
            let imported = Set(report.sites.filter { $0.cookieCount > 0 }.map(\.appID))
            model.reloadSessions(forAppIDs: imported)
            resultMessage = report.summary
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
