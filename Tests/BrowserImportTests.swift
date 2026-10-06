import Foundation
import SQLite3

@main
struct BrowserImportTests {
    static func main() {
        do {
            try run()
            print("Browser import checks passed")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func run() throws {
        try testButtonTitle()
        try testHostMatching()
        try testDecryption()
        try testCookieQuery()
        try testSummary()
        try testSessionCookieProperties()
    }

    static func testButtonTitle() throws {
        try expect(
            BrowserSessionImporter.buttonTitle(for: .chrome) == "Import from Chrome",
            "Chrome keeps its own import label"
        )
        try expect(
            BrowserSessionImporter.buttonTitle(for: .safari) == "Import from your current browser",
            "Safari uses the current-browser label"
        )
        try expect(
            BrowserSessionImporter.buttonTitle(for: .firefox) == "Import from your current browser",
            "Firefox uses the current-browser label"
        )
        try expect(
            BrowserSessionImporter.buttonTitle(for: nil) == "Import from your current browser",
            "An unknown default browser uses the current-browser label"
        )
    }

    static func testHostMatching() throws {
        let youtube = URL(string: "https://www.youtube.com")!
        let gmail = URL(string: "https://mail.google.com")!
        let linkedin = URL(string: "https://www.linkedin.com")!
        let whatsapp = URL(string: "https://web.whatsapp.com")!

        try expect(CookieHostScope.matches(cookieHost: ".google.com", siteURL: youtube), "YouTube accepts Google session cookies")
        try expect(CookieHostScope.matches(cookieHost: "accounts.google.com", siteURL: youtube), "YouTube accepts accounts.google.com")
        try expect(CookieHostScope.matches(cookieHost: ".youtube.com", siteURL: youtube), "YouTube accepts its own cookies")
        try expect(!CookieHostScope.matches(cookieHost: ".linkedin.com", siteURL: youtube), "YouTube ignores LinkedIn")

        try expect(CookieHostScope.matches(cookieHost: ".google.com", siteURL: gmail), "Gmail accepts Google session cookies")
        try expect(CookieHostScope.matches(cookieHost: ".linkedin.com", siteURL: linkedin), "LinkedIn accepts .linkedin.com")
        try expect(CookieHostScope.matches(cookieHost: "www.linkedin.com", siteURL: linkedin), "LinkedIn accepts www.linkedin.com")
        try expect(!CookieHostScope.matches(cookieHost: "notlinkedin.com", siteURL: linkedin), "LinkedIn ignores notlinkedin.com")
        try expect(!CookieHostScope.matches(cookieHost: "linkedin.com.evil.com", siteURL: linkedin), "LinkedIn ignores a lookalike host")

        try expect(CookieHostScope.matches(cookieHost: "web.whatsapp.com", siteURL: whatsapp), "WhatsApp accepts its web host")
        try expect(!CookieHostScope.matches(cookieHost: ".google.com", siteURL: whatsapp), "WhatsApp ignores Google cookies")
    }

    static func testDecryption() throws {
        let password = Data("pocket-test-password".utf8)
        let key = ChromiumCookieCrypto.deriveKey(password: password)
        try expect(key.count == 16, "Derived key is 16 bytes")

        let legacy = data(hex: "763130779773233c2582009c348feca7428aa0")
        try expect(
            ChromiumCookieCrypto.decrypt(encryptedValue: legacy, key: key, hostKey: ".youtube.com") == "legacy-session",
            "v10 cookie without a host hash decrypts"
        )

        let bound = data(hex: "763130f6ab6051e309737d6f3648744e0c2a51166bf529013239d548eff8fb04b35c532f18d73fe92b167a05378e52ef40f9d2")
        try expect(
            ChromiumCookieCrypto.decrypt(encryptedValue: bound, key: key, hostKey: ".youtube.com") == "bound-session",
            "v10 cookie strips the host hash prefix"
        )

        let longValue = data(hex: "7631308d5821a2fb18338b099f9546ffbd3e4f46be7fac806d67eba25652118cc68ebc308cf5f9a72692156ac7993e31351cba")
        try expect(
            ChromiumCookieCrypto.decrypt(encryptedValue: longValue, key: key, hostKey: ".youtube.com") == "abcdefghijklmnopqrstuvwxyz012345-extra",
            "A long cookie value keeps its leading bytes when they are not a host hash"
        )

        let wrongKey = ChromiumCookieCrypto.deriveKey(password: Data("other-password".utf8))
        try expect(
            ChromiumCookieCrypto.decrypt(encryptedValue: legacy, key: wrongKey, hostKey: ".youtube.com") == nil,
            "The wrong Safe Storage key does not decrypt"
        )
    }

    static func testCookieQuery() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pocket-cookie-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("Cookies")
        try createFixtureDatabase(at: databaseURL)

        let password = Data("pocket-test-password".utf8)
        let key = ChromiumCookieCrypto.deriveKey(password: password)
        let sites = [
            BrowserImportSite(
                id: "youtube",
                title: "YouTube",
                dataStoreKey: UUID().uuidString,
                url: URL(string: "https://www.youtube.com")!
            ),
            BrowserImportSite(
                id: "linkedin",
                title: "LinkedIn",
                dataStoreKey: UUID().uuidString,
                url: URL(string: "https://www.linkedin.com")!
            )
        ]
        let read = try BrowserCookieReader.read(
            databaseURL: databaseURL,
            kind: .chrome,
            key: key,
            sites: sites
        )
        let youtube = try values(in: read, siteID: "youtube")
        let linkedin = try values(in: read, siteID: "linkedin")
        try expect(
            youtube == ["bound-session", "google-session", "legacy-session", "session-cookie"],
            "YouTube received its cookies and the Google session, got \(youtube)"
        )
        try expect(linkedin == ["linkedin-session"], "LinkedIn received only its session, got \(linkedin)")
        try expect(read.decryptFailures == 0, "Fixture cookies decrypted")
    }

    static func testSummary() throws {
        let report = BrowserImportReport(
            browserName: "Chrome",
            profileName: "Default",
            sites: [
                BrowserImportReport.Site(appID: "youtube", title: "YouTube", cookieCount: 4),
                BrowserImportReport.Site(appID: "gmail", title: "Gmail", cookieCount: 2),
                BrowserImportReport.Site(appID: "whatsapp", title: "WhatsApp", cookieCount: 0)
            ]
        )
        try expect(
            report.summary == "Imported sessions for YouTube, Gmail from Chrome. Nothing was stored for WhatsApp.",
            "Summary names imported sites and sites with nothing stored, got \(report.summary)"
        )
    }

    static func testSessionCookieProperties() throws {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: "SID",
            .value: "abc",
            .domain: ".google.com",
            .path: "/",
            .secure: "TRUE"
        ]
        properties[.expires] = Date().addingTimeInterval(3600)
        properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax
        guard let cookie = HTTPCookie(properties: properties) else {
            throw Failure(description: "HTTPCookie rejected a session cookie")
        }
        try expect(cookie.isHTTPOnly, "HttpOnly flag is preserved")
        try expect(cookie.isSecure, "Secure flag is preserved")
        try expect(cookie.domain == ".google.com", "Domain cookie keeps its leading dot")
    }

    static func values(in result: BrowserCookieReadResult, siteID: String) throws -> [String] {
        guard let batch = result.batches.first(where: { $0.site.id == siteID }) else {
            throw Failure(description: "Missing batch \(siteID)")
        }
        return batch.cookies.map(\.value).sorted()
    }

    static func createFixtureDatabase(at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw Failure(description: "Could not create the fixture database")
        }
        defer { sqlite3_close(db) }
        let schema = """
        CREATE TABLE cookies (
            host_key TEXT,
            name TEXT,
            value TEXT,
            encrypted_value BLOB,
            path TEXT,
            expires_utc INTEGER,
            is_secure INTEGER,
            is_httponly INTEGER,
            samesite INTEGER,
            has_expires INTEGER
        );
        """
        try exec(db, schema)
        let future = chromeTimestamp(Date().addingTimeInterval(86_400))
        let past = chromeTimestamp(Date().addingTimeInterval(-86_400))
        try insert(
            db,
            host: ".youtube.com",
            name: "LEGACY",
            value: "",
            encryptedHex: "763130779773233c2582009c348feca7428aa0",
            expires: future
        )
        try insert(
            db,
            host: ".youtube.com",
            name: "BOUND",
            value: "",
            encryptedHex: "763130f6ab6051e309737d6f3648744e0c2a51166bf529013239d548eff8fb04b35c532f18d73fe92b167a05378e52ef40f9d2",
            expires: future
        )
        try insert(db, host: ".google.com", name: "APISID", value: "google-session", encryptedHex: nil, expires: future)
        try insert(db, host: ".linkedin.com", name: "li_at", value: "linkedin-session", encryptedHex: nil, expires: future)
        try insert(db, host: "notlinkedin.com", name: "li_at", value: "nope", encryptedHex: nil, expires: future)
        try insert(db, host: ".youtube.com", name: "EXPIRED", value: "expired-session", encryptedHex: nil, expires: past)
        try insert(
            db,
            host: ".youtube.com",
            name: "SESSION",
            value: "session-cookie",
            encryptedHex: nil,
            expires: past,
            hasExpires: 0
        )
    }

    static func insert(
        _ db: OpaquePointer,
        host: String,
        name: String,
        value: String,
        encryptedHex: String?,
        expires: Int64,
        hasExpires: Int = 1
    ) throws {
        let sql = "INSERT INTO cookies (host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite, has_expires) VALUES (?, ?, ?, ?, '/', ?, 1, 1, 1, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw Failure(description: "Could not prepare cookie insert")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
        bind(statement, 1, host, transient)
        bind(statement, 2, name, transient)
        bind(statement, 3, value, transient)
        if let encryptedHex {
            let blob = data(hex: encryptedHex)
            _ = blob.withUnsafeBytes { buffer in
                sqlite3_bind_blob(statement, 4, buffer.baseAddress, Int32(blob.count), transient)
            }
        } else {
            sqlite3_bind_null(statement, 4)
        }
        sqlite3_bind_int64(statement, 5, expires)
        sqlite3_bind_int(statement, 6, Int32(hasExpires))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw Failure(description: "Could not insert \(name)")
        }
    }

    static func bind(_ statement: OpaquePointer, _ index: Int32, _ value: String, _ destructor: sqlite3_destructor_type) {
        _ = value.withCString { cString in
            sqlite3_bind_text(statement, index, cString, -1, destructor)
        }
    }

    static func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw Failure(description: "SQL failed: \(sql)")
        }
    }

    static func chromeTimestamp(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 + 11_644_473_600) * 1_000_000
    }

    static func data(hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return Data() }
            data.append(byte)
            index = next
        }
        return data
    }

    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw Failure(description: message)
        }
    }
}
