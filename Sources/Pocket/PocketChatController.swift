import AppKit
import Combine

struct PocketChatToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let isError: Bool
}

final class PocketChatController: ObservableObject {
    static let composerHeight: CGFloat = 66
    @Published private(set) var isSignedIn = false
    @Published private(set) var isCheckingAccount = false
    @Published private(set) var isLoggingIn = false
    @Published private(set) var isWorking = false
    @Published var isLoginPresented = false
    @Published var isComposerVisible = false
    @Published var prompt = ""
    @Published private(set) var message = ""
    @Published private(set) var isError = false
    @Published private(set) var toast: PocketChatToast?
    private let client: any PocketAIClient
    private let toastDuration: Duration
    private var toastTask: Task<Void, Never>?
    private var loginID: String?
    private var loginTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var loginGeneration = UUID()
    private var requestGeneration = UUID()
    private var revision = 0

    init(client: (any PocketAIClient)? = nil, toastDuration: Duration = .seconds(5)) {
        self.client = client ?? CodexAppServerClient()
        self.toastDuration = toastDuration
    }

    @MainActor func showToast(_ text: String, isError: Bool = false) {
        message = text; self.isError = isError
        toastTask?.cancel()
        let notification = PocketChatToast(message: text, isError: isError)
        toast = notification
        toastTask = Task { @MainActor [weak self, toastDuration] in
            try? await Task.sleep(for: toastDuration)
            guard !Task.isCancelled, self?.toast?.id == notification.id else { return }
            self?.toast = nil; self?.toastTask = nil
        }
    }

    @MainActor func dismissToast() {
        toastTask?.cancel(); toastTask = nil; toast = nil
    }

    @MainActor func refreshAccount() async {
        guard !isCheckingAccount else { return }
        isCheckingAccount = true
        defer { isCheckingAccount = false }
        do { isSignedIn = try await client.account().isSignedIn; message = ""; isError = false }
        catch { isSignedIn = false; message = error.localizedDescription; isError = true }
    }

    @MainActor func toggle() async {
        if isComposerVisible { isComposerVisible = false; return }
        await refreshAccount()
        if isSignedIn {
            isComposerVisible = true
        } else { isLoginPresented = true }
    }

    @MainActor func login(openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        guard !isLoggingIn else { return }
        isLoggingIn = true; isError = false; message = "Opening ChatGPT sign-in..."
        let generation = UUID()
        loginGeneration = generation
        loginTask = Task { @MainActor in
            do {
                let login = try await client.startLogin()
                guard loginGeneration == generation else { await client.cancelLogin(login.id); return }
                loginID = login.id
                guard openURL(login.url) else {
                    await client.cancelLogin(login.id)
                    throw PocketAIError.server("Couldn't open your browser. Please try signing in again.")
                }
                message = "Finish signing in in your browser."
                try await client.finishLogin(login.id)
                guard loginGeneration == generation else { return }
                let account = try await client.account()
                guard loginGeneration == generation else { return }
                isSignedIn = account.isSignedIn
                guard isSignedIn else { throw PocketAIError.signInRequired }
                isLoggingIn = false; loginID = nil; loginTask = nil
                message = ""; isError = false
                isLoginPresented = false; isComposerVisible = true
            } catch {
                guard loginGeneration == generation else { return }
                if let loginID { await client.cancelLogin(loginID) }
                guard loginGeneration == generation else { return }
                isLoggingIn = false; loginID = nil; loginTask = nil
                message = error.localizedDescription; isError = true
            }
        }
    }

    @MainActor func cancelLogin() {
        loginGeneration = UUID()
        loginTask?.cancel(); loginTask = nil
        if let loginID { Task { await client.cancelLogin(loginID) } }
        loginID = nil; isLoggingIn = false; isLoginPresented = false
        message = ""; isError = false
    }

    @MainActor func submit(to model: PocketModel) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking else { return }
        guard isSignedIn else { isLoginPresented = true; return }
        revision += 1
        let original = model.workspace(revision: revision)
        let generation = UUID()
        requestGeneration = generation
        dismissToast()
        isWorking = true; isError = false; message = "Rearranging your view..."
        requestTask = Task { @MainActor in
            do {
                let change = try await client.generate(prompt: text, workspace: original)
                guard requestGeneration == generation else { return }
                try model.apply(change, expecting: original)
                if prompt.trimmingCharacters(in: .whitespacesAndNewlines) == text { prompt = "" }
                showToast(change.message.isEmpty ? "Your view is ready." : change.message)
            } catch {
                guard requestGeneration == generation else { return }
                if case PocketAIError.signInRequired = error {
                    isSignedIn = false; isLoginPresented = true
                }
                showToast(error.localizedDescription, isError: true)
            }
            guard requestGeneration == generation else { return }
            isWorking = false; requestTask = nil
        }
    }

    @MainActor func cancelRequest() {
        guard isWorking else { return }
        requestGeneration = UUID()
        let generation = requestGeneration
        requestTask?.cancel(); requestTask = nil
        isError = false; message = "Cancelling request..."
        Task { @MainActor in
            await client.interrupt()
            guard requestGeneration == generation else { return }
            isWorking = false; showToast("Request cancelled.")
        }
    }

    @MainActor func shutdown() {
        dismissToast()
        cancelRequest()
        cancelLogin()
        Task { await client.shutdown() }
    }
}
