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
        VStack(alignment: .leading, spacing: 20) {
            BrowserImportIntroduction(title: offer.buttonTitle, explanation: offer.explanation)
            BrowserImportSourcePicker(
                title: offer.profileMenuTitle,
                profiles: offer.profiles,
                selectedProfileID: $selectedProfileID,
                isEnabled: !isImporting && offer.canImport
            )
            if resultMessage != nil || errorMessage != nil {
                BrowserImportFeedback(result: resultMessage, error: errorMessage)
            }
            BrowserImportActions(
                primaryTitle: primaryTitle,
                isPrimaryDisabled: isPrimaryDisabled,
                onCancel: dismiss.callAsFunction,
                onPrimary: performPrimary
            )
        }
        .padding(20)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var primaryTitle: String {
        if resultMessage != nil { return "Done" }
        return isImporting ? "Importing…" : "Import"
    }

    private var isPrimaryDisabled: Bool {
        if resultMessage != nil { return false }
        return isImporting || !offer.canImport || selectedProfile == nil
    }

    private var selectedProfile: BrowserProfile? {
        offer.profiles.first { $0.id == selectedProfileID }
    }

    private func performPrimary() {
        if resultMessage != nil {
            dismiss()
            return
        }
        Task { await runImport() }
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

private struct BrowserImportIntroduction: View {
    let title: String
    let explanation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Text(explanation)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct BrowserImportSourcePicker: View {
    let title: String
    let profiles: [BrowserProfile]
    @Binding var selectedProfileID: String
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if profiles.count > 1 {
                Picker(title, selection: $selectedProfileID) {
                    ForEach(profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!isEnabled)
                .accessibilityLabel(title)
            } else if let profile = profiles.first {
                LabeledContent(title) {
                    Text(profile.name)
                        .foregroundStyle(.primary)
                }
                .font(.body)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BrowserImportFeedback: View {
    let result: String?
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let result {
                Text(result)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct BrowserImportActions: View {
    let primaryTitle: String
    let isPrimaryDisabled: Bool
    let onCancel: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button(primaryTitle, action: onPrimary)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isPrimaryDisabled)
        }
    }
}
