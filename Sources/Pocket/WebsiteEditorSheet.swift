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
        VStack(alignment: .leading, spacing: 18) {
            header
            websiteFields
            validationNotice
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: 480, height: 280)
        .background(Color.pocketBackground)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(website == nil ? "Add Website" : "Edit Website")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Give the site a name and URL for Pocket.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.pocketMuted)
        }
    }

    private var websiteFields: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Name")
                .formLabelStyle()
            TextField("e.g. Notion", text: $title)
                .textFieldStyle(.roundedBorder)

            Text("Website URL")
                .formLabelStyle()
            TextField("https://example.com", text: $urlString)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var validationNotice: some View {
        if let validationMessage {
            Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.orange)
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            if let website, website.isBuiltIn {
                Text("Built-in website")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.pocketMuted)
            }

            Spacer()

            Button("Save") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.78, green: 0.31, blue: 0.20))
            .keyboardShortcut(.defaultAction)
        }
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

private extension View {
    func formLabelStyle() -> some View {
        font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.72))
    }
}
