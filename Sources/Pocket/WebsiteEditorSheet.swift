import AppKit
import SwiftUI

struct WebsiteEditorSheet: View {
    @ObservedObject var model: PocketModel
    let website: SimulatedApp?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var urlString: String
    @State private var validationMessage: String?

    init(model: PocketModel, website: SimulatedApp?) {
        self.model = model
        self.website = website
        _title = State(initialValue: website?.title ?? "")
        _urlString = State(initialValue: website?.urlString ?? "https://")
        _validationMessage = State(initialValue: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WebsiteEditorIntroduction(
                title: website == nil ? "Add Website" : "Edit Website",
                explanation: "Give the site a name and URL for Pocket."
            )
            WebsiteEditorFields(title: $title, urlString: $urlString)
            if let validationMessage {
                WebsiteEditorValidation(message: validationMessage)
            }
            WebsiteEditorActions(
                onCancel: dismiss.callAsFunction,
                onSave: save
            )
        }
        .padding(20)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            validationMessage = "Add a name for this website."
            return
        }

        let cleanURL = normalizedURL()
        guard let cleanURL else {
            validationMessage = "Enter a valid http or https website URL."
            return
        }

        if let website {
            model.updateWebsite(
                website,
                title: cleanTitle,
                subtitle: website.subtitle,
                urlString: cleanURL,
                symbolName: website.symbolName
            )
        } else {
            model.addWebsite(
                title: cleanTitle,
                subtitle: "Website",
                urlString: cleanURL,
                symbolName: "globe"
            )
        }
        dismiss()
    }

    private func normalizedURL() -> String? {
        var value = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if !value.contains("://") {
            value = "https://" + value
        }

        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }

        return url.absoluteString
    }
}

private struct WebsiteEditorIntroduction: View {
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

private struct WebsiteEditorFields: View {
    @Binding var title: String
    @Binding var urlString: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WebsiteEditorField(label: "Name", prompt: "e.g. Notion", text: $title)
            WebsiteEditorField(label: "Website URL", prompt: "https://example.com", text: $urlString)
        }
    }
}

private struct WebsiteEditorField: View {
    let label: String
    let prompt: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.body)
                .foregroundStyle(.primary)

            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(label)
        }
    }
}

private struct WebsiteEditorValidation: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.body)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(message)
    }
}

private struct WebsiteEditorActions: View {
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button("Save", action: onSave)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }
}
