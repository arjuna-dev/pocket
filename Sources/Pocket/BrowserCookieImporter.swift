import CommonCrypto
import Foundation
import Security
import SQLite3

struct BrowserCookieProfile: Identifiable, Hashable {
    enum Kind: Hashable {
        case chromium(displayName: String, supportDirectory: URL, keychainService: String, keychainAccount: String)
        case firefox(displayName: String)
    }

    let id: String
    let kind: Kind
    let name: String
    let profileDirectory: URL
    let cookieDatabase: URL

    var browserName: String {
        switch kind {
        case .chromium(let name, _, _, _), .firefox(let name): name
        }
    }

    static func discover(fileManager: FileManager = .default) -> [BrowserCookieProfile] {
        let supportRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        let browsers: [(String, String, String, String)] = [
            ("Google/Chrome", "Google Chrome", "Chrome Safe Storage", "Chrome"),
            ("Microsoft Edge", "Microsoft Edge", "Microsoft Edge Safe Storage", "Microsoft Edge"),
            ("BraveSoftware/Brave-Browser", "Brave", "Brave Safe Storage", "Brave"),
            ("Arc/User Data", "Arc", "Arc Safe Storage", "Arc"),
            ("Vivaldi", "Vivaldi", "Vivaldi Safe Storage", "Vivaldi"),
            ("Opera Software/Opera Stable", "Opera", "Opera Safe Storage", "Opera"),
            ("com.operasoftware.Opera", "Opera", "Opera Safe Storage", "Opera"),
            ("Yandex/YandexBrowser", "Yandex Browser", "Yandex Safe Storage", "Yandex"),
            ("Chromium", "Chromium", "Chromium Safe Storage", "Chromium")
        ]

        var profiles: [BrowserCookieProfile] = []
        for (relativePath, displayName, service, account) in browsers {
            let browserDirectory = supportRoot.appendingPathComponent(relativePath, isDirectory: true)
            guard let entries = try? fileManager.contentsOfDirectory(
                at: browserDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let directories = entries.filter { entry in
                (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            let candidates = directories.filter {
                $0.lastPathComponent == "Default" || $0.lastPathComponent.hasPrefix("Profile ")
            }.sorted { lhs, rhs in
                if lhs.lastPathComponent == "Default" { return true }
                if rhs.lastPathComponent == "Default" { return false }
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }

            for profileDirectory in candidates {
                let database = chromiumCookieDatabase(in: profileDirectory, fileManager: fileManager)
                guard fileManager.fileExists(atPath: database.path) else { continue }
                profiles.append(BrowserCookieProfile(
                    id: "\(relativePath):\(profileDirectory.lastPathComponent)",
                    kind: .chromium(
                        displayName: displayName,
                        supportDirectory: browserDirectory,
                        keychainService: service,
                        keychainAccount: account
                    ),
                    name: profileDirectory.lastPathComponent,
                    profileDirectory: profileDirectory,
                    cookieDatabase: database
                ))
            }
        }

        let firefoxRoot = supportRoot.appendingPathComponent("Firefox", isDirectory: true)
        let profileDirectories = firefoxProfileDirectories(root: firefoxRoot, fileManager: fileManager)
        for (name, profileDirectory) in profileDirectories {
            let database = profileDirectory.appendingPathComponent("cookies.sqlite")
            guard fileManager.fileExists(atPath: database.path) else { continue }
            profiles.append(BrowserCookieProfile(
                id: "firefox:\(profileDirectory.path)",
                kind: .firefox(displayName: "Firefox"),
                name: name,
                profileDirectory: profileDirectory,
                cookieDatabase: database
            ))
        }

        return profiles.sorted {
            let left = "\($0.browserName) \($0.name)"
            let right = "\($1.browserName) \($1.name)"
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    private static func chromiumCookieDatabase(in profileDirectory: URL, fileManager: FileManager) -> URL {
        let networkDatabase = profileDirectory.appendingPathComponent("Network/Cookies")
        if fileManager.fileExists(atPath: networkDatabase.path) { return networkDatabase }
        return profileDirectory.appendingPathComponent("Cookies")
    }

    private static func firefoxProfileDirectories(root: URL, fileManager: FileManager) -> [(String, URL)] {
        let profileList = root.appendingPathComponent("profiles.ini")
        if let contents = try? String(contentsOf: profileList, encoding: .utf8) {
            var sections: [(String, [String: String])] = []
            var sectionName: String?
            var sectionValues: [String: String] = [:]

            func appendSection() {
                if let sectionName { sections.append((sectionName, sectionValues)) }
            }

            for rawLine in contents.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("[") && line.hasSuffix("]") {
                    appendSection()
                    sectionName = String(line.dropFirst().dropLast())
                    sectionValues = [:]
                } else if let separator = line.firstIndex(of: "=") {
                    let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                    let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                    sectionValues[key] = value
                }
            }
            appendSection()

            let profiles = sections.compactMap { name, values -> (String, URL)? in
                guard name.hasPrefix("Profile"), let path = values["Path"] else { return nil }
                let directory = values["IsRelative"] == "1"
                    ? root.appendingPathComponent(path, isDirectory: true)
                    : URL(fileURLWithPath: path, isDirectory: true)
                let profileName = values["Name"] ?? directory.lastPathComponent
                return (profileName, directory)
            }
            if !profiles.isEmpty { return profiles }
        }

        let directory = root.appendingPathComponent("Profiles", isDirectory: true)
        return (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return (url.lastPathComponent, url)
        } ?? []
    }
}

struct BrowserCookieImportResult {
    let cookies: [HTTPCookie]
    let skippedEncryptedCookies: Int
}

enum BrowserCookieImportError: LocalizedError {
    case cannotOpenProfile
    case unsupportedBrowserEncryption
    case keychainAccessDenied
    case noReadableCookies

    var errorDescription: String? {
        switch self {
        case .cannotOpenProfile:
            return "Pocket could not read this browser profile. Close the browser and try again."
        case .unsupportedBrowserEncryption:
            return "This profile uses a browser encryption format Pocket cannot read."
        case .keychainAccessDenied:
            return "Pocket could not access the browser's Safe Storage key in Keychain. Allow the Keychain request and try again."
        case .noReadableCookies:
            return "No readable sign-in cookies were found in this browser profile."
        }
    }
}

enum BrowserCookieImporter {
    static func readCookies(from profile: BrowserCookieProfile) throws -> BrowserCookieImportResult {
        switch profile.kind {
        case .firefox:
            return try readFirefoxCookies(from: profile.cookieDatabase)
        case .chromium(_, let supportDirectory, let service, let account):
            return try readChromiumCookies(
                from: profile.cookieDatabase,
                keychainService: service,
                keychainAccount: account,
                supportDirectory: supportDirectory
            )
        }
    }

    private static func readFirefoxCookies(from databaseURL: URL) throws -> BrowserCookieImportResult {
        let database = try SQLiteDatabase(url: databaseURL)
        let statement = try database.statement(
            "SELECT host, name, value, path, expiry, isSecure, isHttpOnly FROM moz_cookies"
        )
        defer { sqlite3_finalize(statement) }
        var cookies: [HTTPCookie] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let host = database.text(statement, column: 0)
            let name = database.text(statement, column: 1)
            let value = database.text(statement, column: 2)
            let path = database.text(statement, column: 3)
            let expiry = sqlite3_column_int64(statement, 4)
            let isSecure = sqlite3_column_int(statement, 5) != 0
            let isHTTPOnly = sqlite3_column_int(statement, 6) != 0
            guard let cookie = makeCookie(
                domain: host,
                name: name,
                value: value,
                path: path,
                expires: expiry > 0 ? Date(timeIntervalSince1970: TimeInterval(expiry)) : nil,
                isSecure: isSecure,
                isHTTPOnly: isHTTPOnly
            ) else { continue }
            cookies.append(cookie)
        }
        guard !cookies.isEmpty else { throw BrowserCookieImportError.noReadableCookies }
        return BrowserCookieImportResult(cookies: cookies, skippedEncryptedCookies: 0)
    }

    private static func readChromiumCookies(
        from databaseURL: URL,
        keychainService: String,
        keychainAccount: String,
        supportDirectory: URL
    ) throws -> BrowserCookieImportResult {
        let database = try SQLiteDatabase(url: databaseURL)
        let statement = try database.statement(
            "SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly FROM cookies"
        )
        defer { sqlite3_finalize(statement) }

        var encryptedCookiesExist = false
        var encryptionKey: Data?
        var cookies: [HTTPCookie] = []
        var skippedEncryptedCookies = 0

        while sqlite3_step(statement) == SQLITE_ROW {
            let domain = database.text(statement, column: 0)
            let name = database.text(statement, column: 1)
            var value = database.text(statement, column: 2)
            let encryptedValue = database.data(statement, column: 3)
            let path = database.text(statement, column: 4)
            let chromiumExpiry = sqlite3_column_int64(statement, 5)
            let isSecure = sqlite3_column_int(statement, 6) != 0
            let isHTTPOnly = sqlite3_column_int(statement, 7) != 0

            if !encryptedValue.isEmpty {
                encryptedCookiesExist = true
                if encryptionKey == nil {
                    encryptionKey = try chromiumEncryptionKey(
                        service: keychainService,
                        account: keychainAccount,
                        supportDirectory: supportDirectory
                    )
                }
                guard let decrypted = decryptChromiumValue(encryptedValue, key: encryptionKey!) else {
                    skippedEncryptedCookies += 1
                    continue
                }
                value = decrypted
            }

            let expiry: Date? = chromiumExpiry > 0
                ? Date(timeIntervalSince1970: Double(chromiumExpiry) / 1_000_000 - 11_644_473_600)
                : nil
            guard let cookie = makeCookie(
                domain: domain,
                name: name,
                value: value,
                path: path,
                expires: expiry,
                isSecure: isSecure,
                isHTTPOnly: isHTTPOnly
            ) else { continue }
            cookies.append(cookie)
        }

        if encryptedCookiesExist && encryptionKey == nil {
            throw BrowserCookieImportError.keychainAccessDenied
        }
        guard !cookies.isEmpty else {
            if encryptedCookiesExist { throw BrowserCookieImportError.unsupportedBrowserEncryption }
            throw BrowserCookieImportError.noReadableCookies
        }
        return BrowserCookieImportResult(cookies: cookies, skippedEncryptedCookies: skippedEncryptedCookies)
    }

    private static func makeCookie(
        domain: String,
        name: String,
        value: String,
        path: String,
        expires: Date?,
        isSecure: Bool,
        isHTTPOnly: Bool
    ) -> HTTPCookie? {
        let cleanedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedDomain.isEmpty, !name.isEmpty,
              expires.map({ $0 > Date() }) ?? true else { return nil }

        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: cleanedDomain,
            .path: path.isEmpty ? "/" : path,
            .name: name,
            .value: value,
            .version: "0"
        ]
        if isSecure { properties[.secure] = "TRUE" }
        if isHTTPOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)
    }

    static func chromiumEncryptionKey(
        service: String,
        account: String,
        supportDirectory: URL
    ) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let password = result as? Data else {
            throw BrowserCookieImportError.keychainAccessDenied
        }

        // Current Chromium profiles can mark cookies with v20 app-bound
        // encryption. Those require the source browser's privileged service.
        // The classic macOS v10/v11 format uses a Keychain password and PBKDF2.
        _ = supportDirectory
        let salt = Data("saltysalt".utf8)
        var derivedKey = Data(count: kCCKeySizeAES128)
        let keySize = derivedKey.count
        let derivationStatus = derivedKey.withUnsafeMutableBytes { keyBuffer in
            password.withUnsafeBytes { passwordBuffer in
                salt.withUnsafeBytes { saltBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.bindMemory(to: Int8.self).baseAddress,
                        password.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        keyBuffer.bindMemory(to: UInt8.self).baseAddress,
                        keySize
                    )
                }
            }
        }
        guard derivationStatus == kCCSuccess else { throw BrowserCookieImportError.keychainAccessDenied }
        return derivedKey
    }

    static func decryptChromiumValue(_ encrypted: Data, key: Data) -> String? {
        guard encrypted.count > 3, let prefix = String(data: encrypted.prefix(3), encoding: .utf8),
              prefix == "v10" || prefix == "v11" else { return nil }

        let ciphertext = encrypted.dropFirst(3)
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var plaintext = Data(count: ciphertext.count + kCCBlockSizeAES128)
        let outputCapacity = plaintext.count
        var movedBytes = 0
        let status = plaintext.withUnsafeMutableBytes { outputBuffer in
            key.withUnsafeBytes { keyBuffer in
                iv.withUnsafeBytes { ivBuffer in
                    ciphertext.withUnsafeBytes { inputBuffer in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress,
                            key.count,
                            ivBuffer.baseAddress,
                            inputBuffer.baseAddress,
                            ciphertext.count,
                            outputBuffer.baseAddress,
                            outputCapacity,
                            &movedBytes
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        plaintext.removeSubrange(movedBytes..<plaintext.count)
        return String(data: plaintext, encoding: .utf8)
    }
}

private final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              handle != nil else {
            if let handle { sqlite3_close(handle) }
            handle = nil
            throw BrowserCookieImportError.cannotOpenProfile
        }
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    func statement(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard let handle,
              sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw BrowserCookieImportError.cannotOpenProfile
        }
        return statement
    }

    func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let text = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: text)
    }

    func data(_ statement: OpaquePointer, column: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: count)
    }
}
