import SwiftUI

struct PocketChatButton: View {
    @ObservedObject var chat: PocketChatController
    var body: some View {
        Button { Task { @MainActor in await chat.toggle() } } label: {
            Image(systemName: chat.isComposerVisible ? "bubble.left.fill" : "bubble.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(chat.isComposerVisible ? Color.white : Color.white.opacity(0.8))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(chat.isCheckingAccount)
        .help(chat.isComposerVisible ? "Hide Pocket chat" : "Ask Pocket")
        .accessibilityLabel("Pocket chat")
        .accessibilityValue(chat.isComposerVisible ? "Open" : "Closed")
    }
}

struct PocketChatComposer: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var chat: PocketChatController
    @ObservedObject var activity: ScreenChromeActivity
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .foregroundStyle(.secondary)
                TextField("Ask Pocket to rearrange your view", text: Binding(
                    get: { chat.prompt },
                    set: { chat.prompt = $0; activity.activateForTyping(model.focusedScreenID) }
                ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFocused)
                    .onSubmit { chat.submit(to: model) }
                    .accessibilityLabel("Ask Pocket to rearrange your view")
                if chat.isWorking {
                    ProgressView().controlSize(.small)
                    Button { chat.cancelRequest() } label: { Image(systemName: "stop.circle") }
                        .buttonStyle(.plain).help("Cancel request").accessibilityLabel("Cancel request")
                } else {
                    Button { chat.submit(to: model) } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 23))
                    }
                    .buttonStyle(.plain)
                    .disabled(chat.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Send request").accessibilityLabel("Send Pocket request")
                }
                Button { chat.isComposerVisible = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Hide chat").accessibilityLabel("Hide Pocket chat")
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color(white: 0.075)))
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.16), lineWidth: 1) }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .frame(height: PocketChatController.composerHeight)
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        // Preserve the draft, focus, and reserved height while the same timer
        // hides the bars. Typing into the focused field reveals them together.
        .opacity(activity.screenID == nil ? 0 : 1)
        .allowsHitTesting(activity.screenID != nil)
        .accessibilityHidden(activity.screenID == nil)
        .onAppear { isFocused = true }
    }
}

struct PocketChatToastView: View {
    let toast: PocketChatToast
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: toast.isError ? "exclamationmark.circle" : "checkmark.circle")
                .foregroundStyle(toast.isError ? Color.orange : Color.white.opacity(0.8))
            Text(toast.message)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onDismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss notification")
        }
        .padding(12)
        .frame(maxWidth: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1) }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
    }
}

struct PocketChatLoginSheet: View {
    @ObservedObject var chat: PocketChatController
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
            Text("Arrange your view with Pocket")
                .font(.system(size: 22, weight: .semibold))
            Text("Tell Pocket which layout you want and what to open in each screen. Try \"Give me a 2x2 grid with YouTube at the top left.\"")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Log in to ChatGPT to power these requests with your account's Codex usage. Your website logins stay in Pocket.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !chat.message.isEmpty {
                HStack(spacing: 8) {
                    if chat.isLoggingIn { ProgressView().controlSize(.small) }
                    Text(chat.message).font(.system(size: 12))
                        .foregroundStyle(chat.isError ? Color.orange : Color.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") { chat.cancelLogin() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(chat.isLoggingIn ? "Waiting for ChatGPT..." : "Log in to ChatGPT") { chat.login() }
                    .buttonStyle(.borderedProminent)
                    .disabled(chat.isLoggingIn)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(28)
        .frame(width: 440)
        .background(Color(white: 0.065))
        .interactiveDismissDisabled(chat.isLoggingIn)
        .onDisappear { if chat.isLoggingIn { chat.cancelLogin() } }
    }
}
