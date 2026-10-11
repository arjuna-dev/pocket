import Foundation

struct PocketAIAccount: Equatable, Sendable {
    let isSignedIn: Bool
    let email: String?
}

struct PocketAILogin: Sendable { let id: String; let url: URL }

protocol PocketAIClient: Sendable {
    func account() async throws -> PocketAIAccount
    func startLogin() async throws -> PocketAILogin
    func finishLogin(_ id: String) async throws
    func cancelLogin(_ id: String) async
    func generate(prompt: String, workspace: PocketWorkspace) async throws -> PocketWorkspaceChange
    func interrupt() async
    func shutdown() async
}

enum PocketAIError: LocalizedError {
    case unavailable, disconnected, timedOut, signInRequired, invalidResponse, server(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Pocket's chat helper is missing. Rebuild Pocket with Codex installed to enable chat."
        case .disconnected: return "Pocket lost its connection to the chat helper. Please try again."
        case .timedOut: return "The request took too long. Please try again."
        case .signInRequired: return "Log in to ChatGPT to use Pocket chat."
        case .invalidResponse: return "Pocket couldn't understand that response. Please try again."
        case .server(let message): return message
        }
    }
}

// JSON-RPC runs off the UI thread. Each Pocket installation has its own auth
// store and configuration, independent of the user's Codex coding sessions.
actor CodexAppServerClient: PocketAIClient {
    private let executable: URL?
    private let directory: URL
    private let requestTimeout: TimeInterval
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var stderr: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var startup: Task<Void, Error>?
    private var generation = UUID()
    private var loginResults: [String: Result<Void, Error>] = [:]
    private var loginWaiters: [String: CheckedContinuation<Void, Error>] = [:]
    private var loginTimers: [String: Task<Void, Never>] = [:]
    private var threadID: String?
    private var turnID: String?
    private var turnWaiter: CheckedContinuation<PocketWorkspaceChange, Error>?
    private var turnTimer: Task<Void, Never>?
    private var finalText: String?

    init(executable: URL? = nil, directory: URL? = nil, requestTimeout: TimeInterval = 30) {
        self.executable = executable ?? Self.findExecutable()
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pocket/Codex", isDirectory: true)
        self.requestTimeout = requestTimeout
    }

    private static func findExecutable() -> URL? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/codex")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        // A native binary avoids depending on Node or the GUI application's PATH.
        let home = FileManager.default.homeDirectoryForCurrentUser
        #if arch(arm64)
        let architecture = "arm64"
        let target = "aarch64-apple-darwin"
        #else
        let architecture = "x64"
        let target = "x86_64-apple-darwin"
        #endif
        let suffix = "@openai/codex/node_modules/@openai/codex-darwin-\(architecture)/vendor/\(target)/bin/codex"
        let candidates = [home.appendingPathComponent(".local/lib/node_modules/\(suffix)"),
                          URL(fileURLWithPath: "/opt/homebrew/lib/node_modules/\(suffix)"),
                          URL(fileURLWithPath: "/usr/local/lib/node_modules/\(suffix)")]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static let configuration: [String] = [
        "model_provider=\"openai\"", "sandbox_mode=\"read-only\"", "approval_policy=\"never\"",
        "web_search=\"disabled\"", "features.shell_tool=false", "features.unified_exec=false",
        "features.apps=false", "features.remote_plugin=false", "features.multi_agent=false",
        "features.hooks=false", "features.goals=false", "features.memories=false", "tools.view_image=false",
        "analytics.enabled=false"
    ]

    private func ensureStarted() async throws {
        if let startup { return try await startup.value }
        let task = Task { try await self.start() }
        startup = task
        do { try await task.value } catch { startup = nil; throw error }
    }

    private func start() async throws {
        guard let executable else { throw PocketAIError.unavailable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let workDirectory = directory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let child = Process()
        child.executableURL = executable
        child.arguments = ["app-server", "--listen", "stdio://"] + Self.configuration.flatMap { ["-c", $0] }
        child.currentDirectoryURL = workDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = directory.path
        environment.removeValue(forKey: "OPENAI_API_KEY")
        environment.removeValue(forKey: "CODEX_ACCESS_TOKEN")
        child.environment = environment
        let stdin = Pipe(), stdout = Pipe(), errorOutput = Pipe()
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = errorOutput
        let token = UUID()
        generation = token
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        stderr = errorOutput.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.receive(data, generation: token) }
        }
        // Drain diagnostics without displaying tokens or account information in logs.
        stderr?.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        child.terminationHandler = { [weak self] _ in
            Task { await self?.terminated(generation: token) }
        }
        process = child
        do {
            try child.run()
            _ = try await request("initialize", params: ["clientInfo": ["name": "pocket", "title": "Pocket", "version": "1.0"]])
            try send(["method": "initialized", "params": [:]])
        } catch { await shutdown(); throw error }
    }

    func account() async throws -> PocketAIAccount {
        try await ensureStarted()
        let result = try await request("account/read", params: ["refreshToken": false])
        let account = result["account"] as? [String: Any]
        return PocketAIAccount(isSignedIn: account?["type"] as? String == "chatgpt", email: account?["email"] as? String)
    }

    func startLogin() async throws -> PocketAILogin {
        try await ensureStarted()
        let result = try await request("account/login/start", params: ["type": "chatgpt", "appBrand": "chatgpt",
            "useHostedLoginSuccessPage": true])
        guard let id = result["loginId"] as? String, let value = result["authUrl"] as? String,
              let url = URL(string: value), url.scheme == "https",
              ["auth.openai.com", "chatgpt.com"].contains(url.host?.lowercased() ?? "") else {
            throw PocketAIError.invalidResponse
        }
        return PocketAILogin(id: id, url: url)
    }

    func finishLogin(_ id: String) async throws {
        if let result = loginResults.removeValue(forKey: id) { return try result.get() }
        try await withCheckedThrowingContinuation { continuation in
            loginWaiters[id] = continuation
            loginTimers[id] = Task {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                self.resolveLogin(id, result: .failure(PocketAIError.timedOut))
            }
        }
    }

    func cancelLogin(_ id: String) async {
        _ = try? await request("account/login/cancel", params: ["loginId": id])
        resolveLogin(id, result: .failure(CancellationError()))
    }

    func generate(prompt: String, workspace: PocketWorkspace) async throws -> PocketWorkspaceChange {
        guard try await account().isSignedIn else { throw PocketAIError.signInRequired }
        try Task.checkCancellation()
        let catalog = try await request("model/list", params: ["includeHidden": false])
        try Task.checkCancellation()
        let models = catalog["data"] as? [[String: Any]] ?? []
        guard let model = models.first(where: { $0["isDefault"] as? Bool == true }) ?? models.first,
              let name = model["model"] as? String else { throw PocketAIError.invalidResponse }
        // Fresh short threads avoid stale workspace history influencing later commands.
        let result = try await request("thread/start", params: ["model": name, "ephemeral": true,
            "cwd": directory.appendingPathComponent("workspace").path, "sandbox": "read-only", "approvalPolicy": "never",
            "baseInstructions": PocketWorkspaceChange.instructions])
        try Task.checkCancellation()
        guard let thread = result["thread"] as? [String: Any], let id = thread["id"] as? String else {
            throw PocketAIError.invalidResponse
        }
        threadID = id
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let state = String(decoding: try encoder.encode(workspace), as: UTF8.self)
        let effortOptions = (model["supportedReasoningEfforts"] as? [[String: Any]] ?? []).compactMap { $0["reasoningEffort"] as? String }
        let effort = effortOptions.contains("low") ? "low" : model["defaultReasoningEffort"] as? String ?? "medium"
        finalText = nil
        return try await withCheckedThrowingContinuation { continuation in
            turnWaiter = continuation
            turnTimer = Task {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { return }
                let thread = self.threadID, turn = self.turnID
                self.resolveTurn(.failure(PocketAIError.timedOut))
                if let thread, let turn {
                    _ = try? await self.request("turn/interrupt", params: ["threadId": thread, "turnId": turn])
                }
            }
            Task {
                do {
                    let response = try await self.request("turn/start", params: ["threadId": id, "effort": effort,
                        "input": [["type": "text", "text": "Workspace JSON:\n\(state)\n\nUser request:\n\(prompt)"]],
                        "outputSchema": PocketWorkspaceChange.schema(for: workspace)])
                    let turn = (response["turn"] as? [String: Any])?["id"] as? String
                    if self.threadID == id, self.turnWaiter != nil {
                        self.turnID = turn
                    } else if let turn {
                        _ = try? await self.request("turn/interrupt", params: ["threadId": id, "turnId": turn])
                    }
                } catch {
                    if self.threadID == id { self.resolveTurn(.failure(error)) }
                }
            }
        }
    }

    func interrupt() async {
        if let threadID, let turnID { _ = try? await request("turn/interrupt", params: ["threadId": threadID, "turnId": turnID]) }
        resolveTurn(.failure(CancellationError()))
    }

    private func request(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            deadlines[id] = Task {
                try? await Task.sleep(for: .seconds(requestTimeout))
                guard !Task.isCancelled else { return }
                self.deadlines.removeValue(forKey: id)
                self.pending.removeValue(forKey: id)?.resume(throwing: PocketAIError.timedOut)
            }
            do { try send(["id": id, "method": method, "params": params]) }
            catch {
                deadlines.removeValue(forKey: id)?.cancel()
                pending.removeValue(forKey: id)?.resume(throwing: error)
            }
        }
    }

    private func send(_ message: [String: Any]) throws {
        guard let input else { throw PocketAIError.disconnected }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0a)
        try input.write(contentsOf: data)
    }

    private func receive(_ data: Data, generation token: UUID) {
        guard token == generation else { return }
        guard !data.isEmpty else { output?.readabilityHandler = nil; return }
        buffer.append(data)
        guard buffer.count < 4_000_000 else { fail(PocketAIError.invalidResponse); return }
        while let newline = buffer.firstIndex(of: 0x0a) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let method = message["method"] as? String {
                if let id = message["id"] {
                    // Pocket chat only accepts structured responses. It never grants
                    // filesystem, command, connector, or account-verification actions.
                    try? send(["id": id, "error": ["code": -32601, "message": "Pocket supports workspace JSON responses only."]])
                } else { notification(method, params: message["params"] as? [String: Any] ?? [:]) }
            } else if let id = message["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                deadlines.removeValue(forKey: id)?.cancel()
                if let error = message["error"] as? [String: Any] {
                    continuation.resume(throwing: PocketAIError.server(error["message"] as? String ?? "The chat request failed."))
                } else { continuation.resume(returning: message["result"] as? [String: Any] ?? [:]) }
            }
        }
    }

    private func notification(_ method: String, params: [String: Any]) {
        if method == "account/login/completed", let id = params["loginId"] as? String {
            resolveLogin(id, result: params["success"] as? Bool == true ? .success(()) :
                .failure(PocketAIError.server(params["error"] as? String ?? "Sign-in was not completed. Please try again.")))
        }
        guard params["threadId"] as? String == threadID else { return }
        if method == "item/completed", let item = params["item"] as? [String: Any], item["type"] as? String == "agentMessage" {
            finalText = item["text"] as? String
        }
        if method == "turn/completed", let turn = params["turn"] as? [String: Any] {
            if turn["status"] as? String == "completed" {
                let items = turn["items"] as? [[String: Any]] ?? []
                let value = items.last(where: { $0["type"] as? String == "agentMessage" })?["text"] as? String ?? finalText
                guard let value, let change = try? JSONDecoder().decode(PocketWorkspaceChange.self, from: Data(value.utf8)) else {
                    resolveTurn(.failure(PocketAIError.invalidResponse)); return
                }
                resolveTurn(.success(change))
            } else {
                let error = turn["error"] as? [String: Any]
                resolveTurn(.failure(PocketAIError.server(error?["message"] as? String ?? "The request was interrupted. Please try again.")))
            }
        }
    }

    private func resolveLogin(_ id: String, result: Result<Void, Error>) {
        loginTimers.removeValue(forKey: id)?.cancel()
        if let waiter = loginWaiters.removeValue(forKey: id) { waiter.resume(with: result) }
        else { loginResults[id] = result }
    }

    private func resolveTurn(_ result: Result<PocketWorkspaceChange, Error>) {
        turnTimer?.cancel(); turnTimer = nil
        let waiter = turnWaiter
        turnWaiter = nil; turnID = nil; threadID = nil; finalText = nil
        waiter?.resume(with: result)
    }

    private func terminated(generation token: UUID) {
        guard token == generation else { return }
        fail(PocketAIError.disconnected)
    }

    private func fail(_ error: Error) {
        let child = process
        generation = UUID()
        deadlines.values.forEach { $0.cancel() }; deadlines.removeAll()
        let requests = Array(pending.values); pending.removeAll()
        requests.forEach { $0.resume(throwing: error) }
        for id in Array(loginWaiters.keys) { resolveLogin(id, result: .failure(error)) }
        resolveTurn(.failure(error))
        output?.readabilityHandler = nil; stderr?.readabilityHandler = nil
        input = nil; output = nil; stderr = nil; process = nil; startup = nil; buffer.removeAll()
        if child?.isRunning == true { child?.terminate() }
    }

    func shutdown() async {
        generation = UUID()
        let child = process
        fail(PocketAIError.disconnected)
        if child?.isRunning == true { child?.terminate() }
    }
}
