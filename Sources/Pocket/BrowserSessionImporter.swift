import AppKit
import CommonCrypto
import CryptoKit
import Foundation
import Security
import SQLite3
import WebKit

enum BrowserKind: String, CaseIterable, Identifiable, Sendable {
    case chrome
    case chromeBeta
    case chromeCanary
    case edge
    case brave
    case arc
    case chromium
    case firefox
    case safari

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chrome: return "Chrome"
        case .chromeBeta: return "Chrome Beta"
        case .chromeCanary: return "Chrome Canary"
        case .edge: return "Microsoft Edge"
        case .brave: return "Brave"
        case .arc: return "Arc"
        case .chromium: return "Chromium"
        case .firefox: return "Firefox"
        case .safari: return "Safari"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .chrome: return "com.google.Chrome"
        case .chromeBeta: return "com.google.Chrome.beta"
        case .chromeCanary: return "com.google.Chrome.canary"
        case .edge: return "com.microsoft.edgemac"
        case .brave: return "com.brave.Browser"
        case .arc: return "company.thebrowser.Browser"
        case .chromium: return "org.chromium.Chromium"
        case .firefox: return "org.mozilla.firefox"
        case .safari: return "com.apple.Safari"
        }
    }

    var supportsCookieImport: Bool {
        self != .safari
    }

    var safeStorage: (service: String, account: String)? {
        switch self {
        case .chrome, .chromeBeta, .chromeCanary:
            return ("Chrome Safe Storage", "Chrome")
        case .edge:
            return ("Microsoft Edge Safe Storage", "Microsoft Edge")
        case .brave:
            return ("Brave Safe Storage", "Brave")
        case .arc:
            return ("Arc Safe Storage", "Arc")
        case .chromium:
            return ("Chromium Safe Storage", "Chromium")
        case .firefox, .safari:
            return nil
        }
    }
}

struct BrowserProfile: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var cookieDatabaseURL: URL
    var kind: BrowserKind
    var isDefault: Bool
}

struct BrowserImportSite: Sendable, Equatable {
    var id: String
    var title: String
    var dataStoreKey: String
    var url: URL
}

struct BrowserImportOffer: Equatable {
    var buttonTitle: String
    var browserName: String
    var explanation: String
    var profiles: [BrowserProfile]
    var canImport: Bool
    var profileMenuTitle: String
}

struct BrowserImportReport: Sendable, Equatable {
    struct Site: Sendable, Equatable, Identifiable {
        var id: String { appID }
        var appID: String
        var title: String
        var cookieCount: Int
    }

    var browserName: String
    var profileName: String
    var sites: [Site]

    var summary: String {
        let imported = sites.filter { $0.cookieCount > 0 }
        let missing = sites.filter { $0.cookieCount == 0 }
        if imported.isEmpty {
            return "No saved sessions for your Pocket sites were found in \(browserName)."
        }
        var text = "Imported sessions for \(imported.map(\.title).joined(separator: ", ")) from \(browserName)."
        if !missing.isEmpty {
            text += " Nothing was stored for \(missing.map(\.title).joined(separator: ", "))."
        }
        return text
    }
}

enum BrowserImportError: Error, LocalizedError, Sendable {
    case keychainDenied
    case keychainCanceled
    case keychainMissing
    case cookieStoreMissing
    case unreadableCookieStore
    case decryptFailed
    case couldNotStore

    var errorDescription: String? {
        switch self {
        case .keychainDenied:
            return "macOS did not allow Pocket to read this browser's Keychain item. Your browser cookies were left where they are."
        case .keychainCanceled:
            return "The Keychain prompt was canceled. Your browser cookies were left where they are."
        case .keychainMissing:
            return "Pocket couldn't find this browser's Safe Storage item in Keychain."
        case .cookieStoreMissing:
            return "Pocket couldn't find a cookie store for this profile."
        case .unreadableCookieStore:
            return "Pocket couldn't read this browser's cookie store."
        case .decryptFailed:
            return "Pocket couldn't decrypt this browser's cookies."
        case .couldNotStore:
            return "Pocket found browser cookies but couldn't store them for your sites."
        }
    }
}

enum CookieHostScope {
    private static let googleRegistrableDomains: Set<String> = [
        "google.com", "youtube.com", "youtu.be", "gmail.com", "googlemail.com"
    ]

    /// Google signs YouTube and Gmail in with cookies on these hosts.
    private static let googleAuthDomains: Set<String> = [
        "google.com", "youtube.com", "gmail.com", "accounts.google.com", "mail.google.com"
    ]

    static func domains(for siteURL: URL) -> Set<String> {
        guard let host = siteURL.host?.lowercased(), !host.isEmpty else { return [] }
        let registrable = registrableDomain(for: host)
        var domains: Set<String> = [registrable, host]
        if googleRegistrableDomains.contains(registrable) {
            domains.formUnion(googleAuthDomains)
        }
        return domains
    }

    static func matches(cookieHost: String, siteURL: URL) -> Bool {
        matches(cookieHost: cookieHost, domains: domains(for: siteURL))
    }

    static func matches(cookieHost: String, domains: Set<String>) -> Bool {
        let host = normalizedHost(cookieHost)
        guard !host.isEmpty else { return false }
        for domain in domains {
            let normalized = normalizedHost(domain)
            if host == normalized || host.hasSuffix("." + normalized) {
                return true
            }
        }
        return false
    }

    static func registrableDomain(for host: String) -> String {
        let host = normalizedHost(host)
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return host }
        return parts.suffix(2).joined(separator: ".")
    }

    private static func normalizedHost(_ host: String) -> String {
        host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

enum ChromiumCookieCrypto {
    static func deriveKey(password: Data) -> Data {
        let salt = Array("saltysalt".utf8)
        var key = Data(count: 16)
        let status: CCStatus = key.withUnsafeMutableBytes { keyBuffer in
            password.withUnsafeBytes { passwordBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBuffer.bindMemory(to: Int8.self).baseAddress,
                    password.count,
                    salt,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    1003,
                    keyBuffer.bindMemory(to: UInt8.self).baseAddress,
                    16
                )
            }
        }
        guard status == CCStatus(kCCSuccess) else { return Data() }
        return key
    }

    static func decrypt(encryptedValue: Data, key: Data, hostKey: String) -> String? {
        guard key.count == 16, !encryptedValue.isEmpty else { return nil }
        let versionPrefix = Data("v10".utf8)
        let ciphertext: Data
        if encryptedValue.starts(with: versionPrefix) {
            ciphertext = encryptedValue.dropFirst(versionPrefix.count)
        } else {
            return String(data: encryptedValue, encoding: .utf8)
        }
        guard !ciphertext.isEmpty else { return nil }

        let outputCapacity = ciphertext.count + kCCBlockSizeAES128
        var plaintext = Data(count: outputCapacity)
        var moved = 0
        let keyLength = key.count
        let cipherLength = ciphertext.count
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        let status = plaintext.withUnsafeMutableBytes { plainBuffer in
            ciphertext.withUnsafeBytes { cipherBuffer in
                key.withUnsafeBytes { keyBuffer in
                    iv.withUnsafeBytes { ivBuffer in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress,
                            keyLength,
                            ivBuffer.baseAddress,
                            cipherBuffer.baseAddress,
                            cipherLength,
                            plainBuffer.baseAddress,
                            outputCapacity,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess, moved > 0 else { return nil }
        let decrypted = removingHostHashPrefix(from: plaintext.prefix(moved), hostKey: hostKey)
        guard !decrypted.isEmpty else { return nil }
        return String(data: decrypted, encoding: .utf8)
    }

    private static func removingHostHashPrefix(from plaintext: Data, hostKey: String) -> Data {
        guard plaintext.count >= 32 else { return plaintext }
        let candidates = [hostKey, hostKey.hasPrefix(".") ? String(hostKey.dropFirst()) : nil].compactMap { $0 }
        for candidate in candidates {
            let digest = Data(SHA256.hash(data: Data(candidate.utf8)))
            if plaintext.prefix(32) == digest {
                return Data(plaintext.dropFirst(32))
            }
        }
        return plaintext
    }
}

enum BrowserSessionImporter {
    private static let preferredSources: [BrowserKind] = [
        .chrome, .chromeBeta, .chromeCanary, .edge, .brave, .arc, .chromium, .firefox
    ]

    static func buttonTitle() -> String {
        buttonTitle(for: detectDefaultBrowser())
    }

    static func buttonTitle(for defaultBrowser: BrowserKind?) -> String {
        defaultBrowser == .chrome ? "Import from Chrome" : "Import from your current browser"
    }

    static func websitesButtonTitle() -> String {
        websitesButtonTitle(for: detectDefaultBrowser())
    }

    static func websitesButtonTitle(for defaultBrowser: BrowserKind?) -> String {
        if defaultBrowser == .chrome {
            return "Import sessions for the websites above from Chrome"
        }
        return "Import sessions for the websites above from your current browser"
    }

    static func detectDefaultBrowser() -> BrowserKind? {
        guard let url = URL(string: "https://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url),
              let bundleID = Bundle(url: appURL)?.bundleIdentifier else {
            return nil
        }
        return BrowserKind.allCases.first { $0.bundleIdentifier == bundleID }
    }

    static func loadOffer() -> BrowserImportOffer {
        let defaultBrowser = detectDefaultBrowser()
        let title = buttonTitle(for: defaultBrowser)
        if let defaultBrowser, defaultBrowser.supportsCookieImport {
            let profiles = profiles(for: defaultBrowser)
            if !profiles.isEmpty {
                return BrowserImportOffer(
                    buttonTitle: title,
                    browserName: defaultBrowser.displayName,
                    explanation: explanation(for: defaultBrowser, defaultBrowser: defaultBrowser, usedFallback: false),
                    profiles: profiles,
                    canImport: true,
                    profileMenuTitle: profileMenuTitle(for: defaultBrowser, profiles: profiles)
                )
            }
        }

        if let fallback = preferredSources.first(where: { source in
            source != defaultBrowser && !profiles(for: source).isEmpty
        }) {
            let profiles = profiles(for: fallback)
            return BrowserImportOffer(
                buttonTitle: title,
                browserName: fallback.displayName,
                explanation: explanation(for: fallback, defaultBrowser: defaultBrowser, usedFallback: true),
                profiles: profiles,
                canImport: true,
                profileMenuTitle: profileMenuTitle(for: fallback, profiles: profiles)
            )
        }

        return BrowserImportOffer(
            buttonTitle: title,
            browserName: defaultBrowser?.displayName ?? "your browser",
            explanation: "Pocket couldn't find Chrome, Edge, Brave, Arc, Chromium, or Firefox cookies on this Mac.",
            profiles: [],
            canImport: false,
            profileMenuTitle: "Profile"
        )
    }

    static func profiles(for kind: BrowserKind) -> [BrowserProfile] {
        switch kind {
        case .firefox:
            return firefoxProfiles()
        case .safari:
            return []
        case .arc:
            let spaces = arcSpaceProfiles()
            if !spaces.isEmpty { return spaces }
            return chromiumProfiles(kind: .arc).filter { !isArcSystemProfile($0.name) }
        default:
            return chromiumProfiles(kind: kind)
        }
    }

    private static func profileMenuTitle(for kind: BrowserKind, profiles: [BrowserProfile]) -> String {
        guard kind == .arc, profiles.contains(where: { $0.name.contains(" · ") }) else { return "Profile" }
        return "Space"
    }

    static func importCookies(
        from profile: BrowserProfile,
        into sites: [BrowserImportSite]
    ) async throws -> BrowserImportReport {
        let password: Data?
        if profile.kind.safeStorage != nil {
            password = try await MainActor.run {
                try keychainPassword(for: profile.kind)
            }
        } else {
            password = nil
        }

        let read = try await Task.detached(priority: .userInitiated) {
            try readCookieBatches(from: profile, sites: sites, password: password)
        }.value

        if read.decryptFailures > 0 && read.decodedCount == 0 {
            throw BrowserImportError.decryptFailed
        }

        let stored = await store(read.batches)
        if read.decodedCount > 0 && stored.total == 0 {
            throw BrowserImportError.couldNotStore
        }

        let counts = stored.counts
        return BrowserImportReport(
            browserName: profile.kind.displayName,
            profileName: profile.name,
            sites: sites.map { site in
                BrowserImportReport.Site(
                    appID: site.id,
                    title: site.title,
                    cookieCount: counts[site.id] ?? 0
                )
            }
        )
    }

    private static func explanation(
        for kind: BrowserKind,
        defaultBrowser: BrowserKind?,
        usedFallback: Bool
    ) -> String {
        let storage = storageSentence(for: kind)
        let body: String
        if usedFallback, defaultBrowser == .safari {
            body = "Safari keeps its cookies protected. Pocket will copy sign-in cookies from \(kind.displayName), which is installed on this Mac. They stay on this Mac, in each site's own Pocket store."
        } else if usedFallback, let defaultBrowser, defaultBrowser.supportsCookieImport {
            body = "Pocket couldn't find a \(defaultBrowser.displayName) cookie store. It will copy sign-in cookies from \(kind.displayName). They stay on this Mac, in each site's own Pocket store."
        } else if usedFallback {
            body = "Pocket will copy sign-in cookies from \(kind.displayName). They stay on this Mac, in each site's own Pocket store."
        } else {
            body = "Pocket copies sign-in cookies for the sites in your switcher from \(kind.displayName). They stay on this Mac, in each site's own Pocket store."
        }
        if storage.isEmpty { return body }
        return body + " " + storage
    }

    private static func storageSentence(for kind: BrowserKind) -> String {
        guard kind.safeStorage != nil else { return "" }
        return "macOS asks once for permission to read \(kind.displayName)'s Keychain item, so you can skip signing in again."
    }

    private static func keychainPassword(for kind: BrowserKind) throws -> Data {
        guard let item = kind.safeStorage else {
            throw BrowserImportError.keychainMissing
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: item.service,
            kSecAttrAccount as String: item.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, !data.isEmpty else {
                throw BrowserImportError.keychainMissing
            }
            return data
        case errSecUserCanceled:
            throw BrowserImportError.keychainCanceled
        case errSecItemNotFound:
            throw BrowserImportError.keychainMissing
        default:
            throw BrowserImportError.keychainDenied
        }
    }

    private static func readCookieBatches(
        from profile: BrowserProfile,
        sites: [BrowserImportSite],
        password: Data?
    ) throws -> BrowserCookieReadResult {
        guard FileManager.default.fileExists(atPath: profile.cookieDatabaseURL.path) else {
            throw BrowserImportError.cookieStoreMissing
        }
        let snapshot = try? makeSnapshot(of: profile.cookieDatabaseURL)
        defer { snapshot?.remove() }
        let key = password.map(ChromiumCookieCrypto.deriveKey(password:))
        if let snapshot {
            do {
                return try BrowserCookieReader.read(
                    databaseURL: snapshot.databaseURL,
                    kind: profile.kind,
                    key: key,
                    sites: sites
                )
            } catch {
                // A live browser can leave the copied database unreadable. Fall through
                // to a lock-free read of the original file.
            }
        }
        return try BrowserCookieReader.read(
            databaseURL: profile.cookieDatabaseURL,
            kind: profile.kind,
            key: key,
            sites: sites
        )
    }

    @MainActor
    private static func store(_ batches: [BrowserCookieBatch]) async -> (counts: [String: Int], total: Int) {
        var counts: [String: Int] = [:]
        var total = 0
        for batch in batches {
            guard let identifier = UUID(uuidString: batch.site.dataStoreKey) else { continue }
            let cookieStore = WKWebsiteDataStore(forIdentifier: identifier).httpCookieStore
            var stored = 0
            for decoded in batch.cookies {
                guard let cookie = makeCookie(decoded) else { continue }
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    cookieStore.setCookie(cookie) {
                        continuation.resume()
                    }
                }
                stored += 1
            }
            counts[batch.site.id] = stored
            total += stored
        }
        return (counts, total)
    }

    private static func makeCookie(_ cookie: DecodedBrowserCookie) -> HTTPCookie? {
        guard !cookie.name.isEmpty, !cookie.value.isEmpty else { return nil }
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: cookie.name,
            .value: cookie.value,
            .domain: cookie.domain,
            .path: cookie.path.isEmpty ? "/" : cookie.path
        ]
        if cookie.isSecure {
            properties[.secure] = "TRUE"
        }
        if let expires = cookie.expires {
            properties[.expires] = expires
        }
        if cookie.isHTTPOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }
        switch cookie.sameSite {
        case 0:
            properties[.sameSitePolicy] = HTTPCookieStringPolicy(rawValue: "none")
        case 1:
            properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax
        case 2:
            properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict
        default:
            break
        }
        return HTTPCookie(properties: properties)
    }
}

struct DecodedBrowserCookie: Sendable, Equatable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: Date?
    var isSecure: Bool
    var isHTTPOnly: Bool
    var sameSite: Int
}

struct BrowserCookieBatch: Sendable {
    var site: BrowserImportSite
    var cookies: [DecodedBrowserCookie]
}

struct BrowserCookieReadResult: Sendable {
    var batches: [BrowserCookieBatch]
    var decryptFailures: Int
    var decodedCount: Int
}

enum BrowserCookieReader {
    static func read(
        databaseURL: URL,
        kind: BrowserKind,
        key: Data?,
        sites: [BrowserImportSite]
    ) throws -> BrowserCookieReadResult {
        let database = try SQLiteDatabase(url: databaseURL)
        if kind == .firefox {
            return try readFirefox(database: database, sites: sites)
        }
        return try readChromium(database: database, key: key, sites: sites)
    }

    private static func readChromium(
        database: SQLiteDatabase,
        key: Data?,
        sites: [BrowserImportSite]
    ) throws -> BrowserCookieReadResult {
        let columns = try database.columnNames(table: "cookies")
        guard columns.contains("host_key"), columns.contains("name") else {
            throw BrowserImportError.unreadableCookieStore
        }
        return try readRows(
            database: database,
            sites: sites,
            table: "cookies",
            hostColumn: "host_key",
            selectedColumns: [
                "host_key", "name", "value", "encrypted_value", "path",
                "expires_utc", "is_secure", "is_httponly", "samesite", "has_expires"
            ].filter { columns.contains($0) }
        ) { row in
            let host = row.text("host_key") ?? ""
            let encrypted = row.blob("encrypted_value")
            let storedValue = row.text("value") ?? ""
            let value: String
            let failedDecrypt: Bool
            if !encrypted.isEmpty {
                if let key, let decrypted = ChromiumCookieCrypto.decrypt(
                    encryptedValue: encrypted,
                    key: key,
                    hostKey: host
                ) {
                    value = decrypted
                    failedDecrypt = false
                } else {
                    value = ""
                    failedDecrypt = true
                }
            } else {
                value = storedValue
                failedDecrypt = false
            }
            let hasExpires = row.int("has_expires")
            let expires = dateFromChrome(row.int64("expires_utc"))
            return CookieDraft(
                host: host,
                name: row.text("name") ?? "",
                value: value,
                path: row.text("path") ?? "/",
                expires: hasExpires == 0 ? nil : expires,
                expired: hasExpires != 0 && expires.map { $0 < Date() } == true,
                isSecure: row.int("is_secure") == 1,
                isHTTPOnly: row.int("is_httponly") == 1,
                sameSite: row.int("samesite") ?? -1,
                failedDecrypt: failedDecrypt
            )
        }
    }

    private static func readFirefox(
        database: SQLiteDatabase,
        sites: [BrowserImportSite]
    ) throws -> BrowserCookieReadResult {
        let columns = try database.columnNames(table: "moz_cookies")
        guard columns.contains("host"), columns.contains("name"), columns.contains("value") else {
            throw BrowserImportError.unreadableCookieStore
        }
        return try readRows(
            database: database,
            sites: sites,
            table: "moz_cookies",
            hostColumn: "host",
            selectedColumns: [
                "host", "name", "value", "path", "expiry", "isSecure", "isHttpOnly", "sameSite"
            ].filter { columns.contains($0) }
        ) { row in
            let expiry = row.int64("expiry")
            let expires = expiry.flatMap { value -> Date? in
                guard value > 0 else { return nil }
                return Date(timeIntervalSince1970: TimeInterval(value))
            }
            return CookieDraft(
                host: row.text("host") ?? "",
                name: row.text("name") ?? "",
                value: row.text("value") ?? "",
                path: row.text("path") ?? "/",
                expires: expires,
                expired: expires.map { $0 < Date() } == true,
                isSecure: row.int("isSecure") == 1,
                isHTTPOnly: row.int("isHttpOnly") == 1,
                sameSite: row.int("sameSite") ?? -1,
                failedDecrypt: false
            )
        }
    }

    private static func readRows(
        database: SQLiteDatabase,
        sites: [BrowserImportSite],
        table: String,
        hostColumn: String,
        selectedColumns: [String],
        draft: (SQLiteRow) -> CookieDraft
    ) throws -> BrowserCookieReadResult {
        let scopes = sites.map { (site: $0, domains: CookieHostScope.domains(for: $0.url)) }
        let domains = Array(Set(scopes.flatMap(\.domains))).sorted()
        guard !domains.isEmpty, !selectedColumns.isEmpty else {
            return BrowserCookieReadResult(batches: emptyBatches(sites), decryptFailures: 0, decodedCount: 0)
        }

        let clause = hostClause(column: hostColumn, domains: domains)
        let sql = "SELECT \(selectedColumns.joined(separator: ", ")) FROM \(table) WHERE \(clause.sql)"
        var decryptFailures = 0
        var decodedCount = 0
        var cookiesBySite = Dictionary(uniqueKeysWithValues: sites.map { ($0.id, [DecodedBrowserCookie]()) })

        try database.forEachRow(sql: sql, bindings: clause.bindings) { row in
            let parsed = draft(row)
            guard !parsed.host.isEmpty, !parsed.name.isEmpty else { return }
            if parsed.failedDecrypt {
                decryptFailures += 1
                return
            }
            guard !parsed.expired, !parsed.value.isEmpty else { return }
            let cookie = DecodedBrowserCookie(
                name: parsed.name,
                value: parsed.value,
                domain: parsed.host,
                path: parsed.path.isEmpty ? "/" : parsed.path,
                expires: parsed.expires,
                isSecure: parsed.isSecure,
                isHTTPOnly: parsed.isHTTPOnly,
                sameSite: parsed.sameSite
            )
            var matched = false
            for scope in scopes where CookieHostScope.matches(cookieHost: parsed.host, domains: scope.domains) {
                cookiesBySite[scope.site.id, default: []].append(cookie)
                matched = true
            }
            if matched {
                decodedCount += 1
            }
        }

        let batches = sites.map { site in
            BrowserCookieBatch(site: site, cookies: deduped(cookiesBySite[site.id] ?? []))
        }
        return BrowserCookieReadResult(batches: batches, decryptFailures: decryptFailures, decodedCount: decodedCount)
    }

    private static func emptyBatches(_ sites: [BrowserImportSite]) -> [BrowserCookieBatch] {
        sites.map { BrowserCookieBatch(site: $0, cookies: []) }
    }

    private static func deduped(_ cookies: [DecodedBrowserCookie]) -> [DecodedBrowserCookie] {
        var indexByKey: [String: Int] = [:]
        var result: [DecodedBrowserCookie] = []
        for cookie in cookies {
            let key = "\(cookie.name)\t\(cookie.domain)\t\(cookie.path)"
            if let index = indexByKey[key] {
                result[index] = cookie
            } else {
                indexByKey[key] = result.count
                result.append(cookie)
            }
        }
        return result
    }

    private static func hostClause(column: String, domains: [String]) -> (sql: String, bindings: [String]) {
        let column = column == "host" ? "host" : "host_key"
        var parts: [String] = []
        var bindings: [String] = []
        for domain in domains {
            parts.append("(\(column) = ? OR \(column) = ? OR \(column) LIKE ?)")
            bindings.append(domain)
            bindings.append("." + domain)
            bindings.append("%." + domain)
        }
        return (parts.joined(separator: " OR "), bindings)
    }

    private static func dateFromChrome(_ value: Int64?) -> Date? {
        guard let value, value > 0 else { return nil }
        let unix = TimeInterval(value / 1_000_000) - 11_644_473_600
        guard unix > 0 else { return nil }
        return Date(timeIntervalSince1970: unix)
    }
}

private struct CookieDraft {
    var host: String
    var name: String
    var value: String
    var path: String
    var expires: Date?
    var expired: Bool
    var isSecure: Bool
    var isHTTPOnly: Bool
    var sameSite: Int
    var failedDecrypt: Bool
}

private struct CookieSnapshot {
    var databaseURL: URL
    var directory: URL

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func makeSnapshot(of databaseURL: URL) throws -> CookieSnapshot {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pocket-cookie-import-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileName = databaseURL.lastPathComponent
    let destination = directory.appendingPathComponent(fileName)
    do {
        try FileManager.default.copyItem(at: databaseURL, to: destination)
    } catch {
        try? FileManager.default.removeItem(at: directory)
        throw error
    }
    for suffix in ["-wal", "-shm"] {
        let source = URL(fileURLWithPath: databaseURL.path + suffix)
        guard FileManager.default.fileExists(atPath: source.path) else { continue }
        try? FileManager.default.copyItem(
            at: source,
            to: directory.appendingPathComponent(fileName + suffix)
        )
    }
    return CookieSnapshot(databaseURL: destination, directory: directory)
}

private func isArcSystemProfile(_ name: String) -> Bool {
    name == "__ARC_SYSTEM_PROFILE" || name.hasPrefix("__ARC_")
}

private func arcSpaceProfiles() -> [BrowserProfile] {
    let root = supportDirectory(for: .arc)
    let sidebarURL = root.deletingLastPathComponent().appendingPathComponent("StorableSidebar.json")
    guard let data = try? Data(contentsOf: sidebarURL),
          let json = try? JSONSerialization.jsonObject(with: data) else {
        return []
    }
    let names = chromiumProfileNames(in: root)
    return ArcSidebarReader.profiles(
        in: json,
        profileNames: names,
        cookieDatabase: { directoryName in
            let directory = root.appendingPathComponent(directoryName, isDirectory: true)
            return cookieDatabase(in: directory, firefox: false)
        }
    )
}

enum ArcSidebarReader {
    static func listLabel(spaceName: String, profileName: String) -> String {
        "\(spaceName) · \(profileName)"
    }

    static func profiles(
        in json: Any,
        profileNames: [String: String],
        cookieDatabase: (String) -> URL?
    ) -> [BrowserProfile] {
        guard let root = json as? [String: Any],
              let sidebar = root["sidebar"] as? [String: Any],
              let containers = sidebar["containers"] as? [Any] else {
            return []
        }

        var profiles: [BrowserProfile] = []
        var seenSpaceIDs: Set<String> = []
        for container in containers {
            guard let container = container as? [String: Any],
                  let spaces = container["spaces"] as? [Any] else {
                continue
            }
            for item in spaces {
                guard let space = item as? [String: Any],
                      let spaceID = trimmed(space["id"]),
                      seenSpaceIDs.insert(spaceID).inserted,
                      let spaceName = trimmed(space["title"]),
                      let directory = profileDirectory(in: space["profile"]),
                      let database = cookieDatabase(directory) else {
                    continue
                }
                let storedName = profileNames[directory]?.trimmingCharacters(in: .whitespacesAndNewlines)
                let profileName = (storedName?.isEmpty == false ? storedName : nil) ?? directory
                if isArcSystemProfile(profileName) { continue }
                profiles.append(
                    BrowserProfile(
                        id: "arc:\(spaceID)",
                        name: listLabel(spaceName: spaceName, profileName: profileName),
                        cookieDatabaseURL: database,
                        kind: .arc,
                        isDefault: spaceID == "thebrowser.company.defaultPersonalSpaceID"
                    )
                )
            }
        }
        return profiles
    }

    private static func profileDirectory(in profile: Any?) -> String? {
        guard let profile = profile as? [String: Any] else { return nil }
        if let custom = profile["custom"] as? [String: Any] {
            let record = (custom["_0"] as? [String: Any]) ?? custom
            if let directory = trimmed(record["directoryBasename"]) {
                return directory
            }
        }
        return nil
    }

    private static func trimmed(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func chromiumProfiles(kind: BrowserKind) -> [BrowserProfile] {
    let root = supportDirectory(for: kind)
    guard FileManager.default.fileExists(atPath: root.path) else { return [] }
    let names = chromiumProfileNames(in: root)
    let directoryNames = names.isEmpty ? discoveredChromiumProfiles(in: root) : Set(names.keys)
    var profiles: [BrowserProfile] = []
    for directoryName in directoryNames {
        let directory = root.appendingPathComponent(directoryName, isDirectory: true)
        guard let database = cookieDatabase(in: directory, firefox: false) else { continue }
        let storedName = names[directoryName]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (storedName?.isEmpty == false ? storedName : nil) ?? directoryName
        profiles.append(
            BrowserProfile(
                id: "\(kind.rawValue):\(directoryName)",
                name: displayName,
                cookieDatabaseURL: database,
                kind: kind,
                isDefault: directoryName == "Default"
            )
        )
    }
    return profiles.sorted { lhs, rhs in
        if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

private func firefoxProfiles() -> [BrowserProfile] {
    let root = supportDirectory(for: .firefox)
    let iniURL = root.appendingPathComponent("profiles.ini")
    guard let text = try? String(contentsOf: iniURL, encoding: .utf8) else { return [] }
    let sections = IniFile.parse(text)
    let installDefaults = Set(
        sections
            .filter { $0.name.hasPrefix("Install") }
            .compactMap { $0.values["Default"] }
    )
    var profiles: [BrowserProfile] = []
    for section in sections where section.name.hasPrefix("Profile") {
        guard let path = section.values["Path"] else { continue }
        let directory: URL
        if section.values["IsRelative"] == "0" {
            directory = URL(fileURLWithPath: path)
        } else {
            directory = root.appendingPathComponent(path)
        }
        guard let database = cookieDatabase(in: directory, firefox: true) else { continue }
        let name = section.values["Name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (name?.isEmpty == false ? name : nil) ?? directory.lastPathComponent
        profiles.append(
            BrowserProfile(
                id: "firefox:\(path)",
                name: displayName,
                cookieDatabaseURL: database,
                kind: .firefox,
                isDefault: section.values["Default"] == "1" || installDefaults.contains(path)
            )
        )
    }
    return profiles.sorted { lhs, rhs in
        if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

private func chromiumProfileNames(in root: URL) -> [String: String] {
    let url = root.appendingPathComponent("Local State")
    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let profile = json["profile"] as? [String: Any],
          let cache = profile["info_cache"] as? [String: Any] else {
        return [:]
    }
    var names: [String: String] = [:]
    for (directory, value) in cache {
        let info = value as? [String: Any]
        let name = (info?["name"] as? String) ?? (info?["user_name"] as? String) ?? directory
        names[directory] = name
    }
    return names
}

private func discoveredChromiumProfiles(in root: URL) -> Set<String> {
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }
    var names: Set<String> = []
    for url in contents {
        let name = url.lastPathComponent
        guard name == "Default" || name.hasPrefix("Profile") else { continue }
        if cookieDatabase(in: url, firefox: false) != nil {
            names.insert(name)
        }
    }
    return names
}

private func cookieDatabase(in directory: URL, firefox: Bool) -> URL? {
    if firefox {
        let url = directory.appendingPathComponent("cookies.sqlite")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    let network = directory.appendingPathComponent("Network").appendingPathComponent("Cookies")
    if FileManager.default.fileExists(atPath: network.path) { return network }
    let legacy = directory.appendingPathComponent("Cookies")
    return FileManager.default.fileExists(atPath: legacy.path) ? legacy : nil
}

private func supportDirectory(for kind: BrowserKind) -> URL {
    let appSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support", isDirectory: true)
    switch kind {
    case .chrome:
        return appSupport.appendingPathComponent("Google/Chrome", isDirectory: true)
    case .chromeBeta:
        return appSupport.appendingPathComponent("Google/Chrome Beta", isDirectory: true)
    case .chromeCanary:
        return appSupport.appendingPathComponent("Google/Chrome Canary", isDirectory: true)
    case .edge:
        return appSupport.appendingPathComponent("Microsoft Edge", isDirectory: true)
    case .brave:
        return appSupport.appendingPathComponent("BraveSoftware/Brave-Browser", isDirectory: true)
    case .arc:
        return appSupport.appendingPathComponent("Arc/User Data", isDirectory: true)
    case .chromium:
        return appSupport.appendingPathComponent("Chromium", isDirectory: true)
    case .firefox:
        return appSupport.appendingPathComponent("Firefox", isDirectory: true)
    case .safari:
        return appSupport
    }
}

private struct IniFile {
    struct Section {
        var name: String
        var values: [String: String]
    }

    static func parse(_ text: String) -> [Section] {
        var sections: [Section] = []
        var current: Section?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                if let current { sections.append(current) }
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                current = Section(name: name, values: [:])
                continue
            }
            guard var section = current, let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            section.values[key] = value
            current = section
        }
        if let current { sections.append(current) }
        return sections
    }
}

private final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private let transientDestructor = unsafeBitCast(
        OpaquePointer(bitPattern: -1),
        to: sqlite3_destructor_type.self
    )

    init(url: URL) throws {
        var db: OpaquePointer?
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db {
            sqlite3_busy_timeout(db, 300)
            handle = db
            return
        }
        sqlite3_close(db)
        db = nil
        guard let uri = Self.readOnlyURI(for: url),
              sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let opened = db else {
            sqlite3_close(db)
            throw BrowserImportError.unreadableCookieStore
        }
        sqlite3_busy_timeout(opened, 300)
        handle = opened
    }

    deinit {
        sqlite3_close(handle)
    }

    func columnNames(table: String) throws -> Set<String> {
        let table = Self.validatedTable(table)
        var names: Set<String> = []
        try forEachRow(sql: "PRAGMA table_info(\(table))", bindings: []) { row in
            if let name = row.text("name") {
                names.insert(name)
            }
        }
        return names
    }

    func forEachRow(sql: String, bindings: [String], body: (SQLiteRow) -> Void) throws {
        guard let handle else { throw BrowserImportError.unreadableCookieStore }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw BrowserImportError.unreadableCookieStore
        }
        defer { sqlite3_finalize(statement) }

        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            _ = binding.withCString { cString in
                sqlite3_bind_text(statement, index, cString, -1, transientDestructor)
            }
        }

        var columns: [String: Int32] = [:]
        let count = sqlite3_column_count(statement)
        for index in 0..<count {
            if let name = sqlite3_column_name(statement, index) {
                columns[String(cString: name)] = index
            }
        }

        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                body(SQLiteRow(statement: statement, columns: columns))
            } else if step == SQLITE_DONE {
                return
            } else {
                throw BrowserImportError.unreadableCookieStore
            }
        }
    }

    private static func validatedTable(_ name: String) -> String {
        switch name {
        case "cookies", "moz_cookies":
            return name
        default:
            return "cookies"
        }
    }

    private static func readOnlyURI(for url: URL) -> String? {
        var components = URLComponents()
        components.scheme = "file"
        components.path = url.path
        components.query = "mode=ro&nolock=1"
        return components.string
    }
}

private struct SQLiteRow {
    var statement: OpaquePointer
    var columns: [String: Int32]

    func text(_ name: String) -> String? {
        guard let index = columns[name], sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    func int(_ name: String) -> Int? {
        guard let value = int64(name) else { return nil }
        return Int(value)
    }

    func int64(_ name: String) -> Int64? {
        guard let index = columns[name], sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_int64(statement, index)
    }

    func blob(_ name: String) -> Data {
        guard let index = columns[name] else { return Data() }
        let type = sqlite3_column_type(statement, index)
        guard type == SQLITE_BLOB, let bytes = sqlite3_column_blob(statement, index) else {
            return Data()
        }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0 else { return Data() }
        return Data(bytes: bytes, count: count)
    }
}
