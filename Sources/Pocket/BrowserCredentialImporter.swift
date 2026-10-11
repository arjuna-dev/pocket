import AppKit
import Foundation
import Security
import SQLite3

struct ImportedBrowserCredential: Codable, Identifiable {
    let origin: String
    let username: String
    let password: String

    var id: String { "\(origin)|\(username)" }
    var websiteName: String { URL(string: origin)?.host ?? origin }
}

enum BrowserCredentialImportError: LocalizedError {
    case noCredentials
    case cannotOpenProfile
    case cannotReadCSV
    case keychainFailure

    var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "No saved passwords were found in this source."
        case .cannotOpenProfile:
            return "Pocket could not read the browser's saved passwords. Close the browser and try again."
        case .cannotReadCSV:
            return "Pocket could not read this password export. Choose a browser password CSV file."
        case .keychainFailure:
            return "Pocket could not save the imported passwords to Keychain."
        }
    }
}

enum BrowserCredentialImporter {
    static func readChromiumPasswords(from profile: BrowserCookieProfile) throws -> [ImportedBrowserCredential] {
        guard case .chromium(_, let supportDirectory, let service, let account) = profile.kind else {
            throw BrowserCredentialImportError.noCredentials
        }

        let databaseURL = profile.profileDirectory.appendingPathComponent("Login Data")
        let database = try CredentialSQLiteDatabase(url: databaseURL)
        let statement = try database.statement(
            "SELECT origin_url, username_value, password_value, blacklisted_by_user FROM logins"
        )
        defer { sqlite3_finalize(statement) }

        var encryptionKey: Data?
        var credentials: [ImportedBrowserCredential] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard sqlite3_column_int(statement, 3) == 0 else { continue }
            let originString = database.text(statement, column: 0)
            let username = database.text(statement, column: 1)
            let encryptedPassword = database.data(statement, column: 2)
            guard !username.isEmpty, !encryptedPassword.isEmpty else { continue }
            guard let origin = normalizedOrigin(originString) else { continue }

            if encryptionKey == nil {
                encryptionKey = try BrowserCookieImporter.chromiumEncryptionKey(
                    service: service,
                    account: account,
                    supportDirectory: supportDirectory
                )
            }
            guard let password = BrowserCookieImporter.decryptChromiumValue(encryptedPassword, key: encryptionKey!),
                  !password.isEmpty else { continue }
            credentials.append(ImportedBrowserCredential(origin: origin, username: username, password: password))
        }

        guard !credentials.isEmpty else { throw BrowserCredentialImportError.noCredentials }
        return credentials
    }

    static func readPasswordCSV(from url: URL) throws -> [ImportedBrowserCredential] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw BrowserCredentialImportError.cannotReadCSV
        }
        let rows = parseCSV(text)
        guard let header = rows.first else { throw BrowserCredentialImportError.cannotReadCSV }
        let names = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard let urlColumn = names.firstIndex(where: { ["url", "website", "origin"].contains($0) }),
              let usernameColumn = names.firstIndex(where: { ["username", "user name", "login"].contains($0) }),
              let passwordColumn = names.firstIndex(where: { ["password", "pass"].contains($0) }) else {
            throw BrowserCredentialImportError.cannotReadCSV
        }

        let credentials = rows.dropFirst().compactMap { row -> ImportedBrowserCredential? in
            guard row.count > max(urlColumn, usernameColumn, passwordColumn),
                  let origin = normalizedOrigin(row[urlColumn]) else { return nil }
            let username = row[usernameColumn].trimmingCharacters(in: .whitespacesAndNewlines)
            let password = row[passwordColumn]
            guard !username.isEmpty, !password.isEmpty else { return nil }
            return ImportedBrowserCredential(origin: origin, username: username, password: password)
        }
        guard !credentials.isEmpty else { throw BrowserCredentialImportError.noCredentials }
        return credentials
    }

    private static func normalizedOrigin(_ rawValue: String) -> String? {
        guard let components = URLComponents(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        var origin = "\(scheme)://\(host)"
        if let port = components.port { origin += ":\(port)" }
        return origin
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        let characters = Array(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var insideQuotes = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if insideQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    insideQuotes.toggle()
                }
            } else if character == "," && !insideQuotes {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r") && !insideQuotes {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
                row.append(field)
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }

        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        if let first = rows.first, let firstCell = first.first, firstCell.hasPrefix("\u{feff}") {
            rows[0][0] = String(firstCell.dropFirst())
        }
        return rows
    }
}

enum PocketCredentialVault {
    private static let service = "com.pocket.simulator.imported-browser-credentials"

    static func save(_ credentials: [ImportedBrowserCredential]) throws -> Int {
        var savedCount = 0
        for credential in credentials {
            let account = credential.id
            guard let data = try? JSONEncoder().encode(credential) else { continue }
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            let status = SecItemAdd(query as CFDictionary, nil)
            if status == errSecDuplicateItem {
                let lookup: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account
                ]
                let update: [String: Any] = [kSecValueData as String: data]
                guard SecItemUpdate(lookup as CFDictionary, update as CFDictionary) == errSecSuccess else {
                    throw BrowserCredentialImportError.keychainFailure
                }
            } else if status != errSecSuccess {
                throw BrowserCredentialImportError.keychainFailure
            }
            savedCount += 1
        }
        return savedCount
    }

    static func loadAll() -> [ImportedBrowserCredential] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [Data] else { return [] }
        return items.compactMap { try? JSONDecoder().decode(ImportedBrowserCredential.self, from: $0) }
            .sorted { lhs, rhs in
                let left = "\(lhs.websiteName) \(lhs.username)"
                let right = "\(rhs.websiteName) \(rhs.username)"
                return left.localizedStandardCompare(right) == .orderedAscending
            }
    }

    static func delete(_ credential: ImportedBrowserCredential) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.id
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private final class CredentialSQLiteDatabase {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              handle != nil else {
            if let handle { sqlite3_close(handle) }
            handle = nil
            throw BrowserCredentialImportError.cannotOpenProfile
        }
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    func statement(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard let handle,
              sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw BrowserCredentialImportError.cannotOpenProfile }
        return statement
    }

    func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let text = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: UnsafeRawPointer(text).assumingMemoryBound(to: CChar.self))
    }

    func data(_ statement: OpaquePointer, column: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: count)
    }
}
